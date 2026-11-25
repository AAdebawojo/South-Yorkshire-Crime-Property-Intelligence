/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 2 - Step 2: diagnostics + core staging views
   Run in DBeaver against: CrimeData
   Part A: read-only diagnostics on the two gaps found in step 1
   Part B: creates analytics.stg_crimes, analytics.stg_outcomes,
           analytics.dq_outcome_exceptions (views; police is untouched)
   Part C: read-only validation of Part B
   ===================================================================== */


/* =====================================================================
   PART A - DIAGNOSTICS (read-only)
   ===================================================================== */

/* ---------------------------------------------------------------------
   D1. The 34 location points with no LSOA (520 crimes).
       Hypothesis: British Transport Police station points. BTP crimes are
       not in the South Yorkshire Police CSV (CSV = reporting force), so
       their points can never match.
   --------------------------------------------------------------------- */
SELECT
    COALESCE(crs.location_type, '(no crimes)')                     AS location_type,
    COUNT(DISTINCT xr.location_id)                                 AS unmatched_points,
    COUNT(crs.crime_id)                                            AS crimes,
    string_agg(DISTINCT loc.street_name, ' | ')                    AS street_names
FROM analytics.xref_location_lsoa AS xr
JOIN police.locations             AS loc ON loc.location_id = xr.location_id
LEFT JOIN police.crimes           AS crs ON crs.location_id = xr.location_id
WHERE xr.match_status = 'unmatched'
GROUP BY 1
ORDER BY crimes DESC;


/* ---------------------------------------------------------------------
   D2. API-only crimes (1,162): in the API but not in the CSV.
       Grouped by category and by where they sit, to see whether they
       cluster near force boundaries or in particular categories.
   --------------------------------------------------------------------- */
WITH csv_ids AS (
    SELECT DISTINCT btrim(raw.crime_id) AS persistent_id
    FROM police_bulk.street_crimes_raw AS raw
    WHERE COALESCE(btrim(raw.crime_id), '') <> ''
),
api_only AS (
    SELECT crs.*
    FROM police.crimes AS crs
    WHERE COALESCE(btrim(crs.persistent_id), '') <> ''
      AND NOT EXISTS (SELECT 1 FROM csv_ids WHERE csv_ids.persistent_id = crs.persistent_id)
)
SELECT
    ao.category_code,
    CASE WHEN ao.location_id IS NULL THEN '(no location)'
         ELSE COALESCE(xr.lsoa_local_authority, '(LSOA unmatched)') END   AS lsoa_local_authority,
    COUNT(*)                                                              AS api_only_crimes,
    MIN(ao.crime_month)                                                   AS first_month,
    MAX(ao.crime_month)                                                   AS last_month
FROM api_only AS ao
LEFT JOIN analytics.xref_location_lsoa AS xr ON xr.location_id = ao.location_id
GROUP BY 1, 2
ORDER BY api_only_crimes DESC
LIMIT 25;


/* ---------------------------------------------------------------------
   D3. CSV-only crimes (588): in the CSV but not in the API.
       Expected: South Yorkshire Police crimes located outside the county,
       or points dropped by the loader's boundary tolerance (T-004).
   --------------------------------------------------------------------- */
WITH api_ids AS (
    SELECT DISTINCT persistent_id
    FROM police.crimes
    WHERE COALESCE(btrim(persistent_id), '') <> ''
)
SELECT
    CASE WHEN COALESCE(btrim(raw.lsoa_code), '') = '' THEN '(no LSOA)'
         ELSE regexp_replace(raw.lsoa_name, '\s+\S+$', '') END     AS csv_lsoa_local_authority,
    raw.falls_within,
    COUNT(*)                                                       AS csv_only_crimes
FROM police_bulk.street_crimes_raw AS raw
WHERE COALESCE(btrim(raw.crime_id), '') <> ''
  AND NOT EXISTS (SELECT 1 FROM api_ids WHERE api_ids.persistent_id = btrim(raw.crime_id))
GROUP BY 1, 2
ORDER BY csv_only_crimes DESC
LIMIT 25;


/* =====================================================================
   PART B - STAGING VIEWS
   ===================================================================== */

/* ---------------------------------------------------------------------
   B1. analytics.stg_crimes   (T-102)
   Grain   : one row per police.crimes row (527,601) - nothing removed.
   Cleans  : '' -> NULL; drops context (100% empty, DQ-13) and
             location_subtype (replaced by is_btp, DQ-13).
   Flags   : is_asb, is_btp, has_location, is_duplicate (DQ-02 rule:
             per persistent_id keep latest_outcome_month DESC, crime_id ASC).
   Outcome : latest_outcome_status never NULL:
             ASB -> 'Not applicable (ASB)'; otherwise the source text.
             outcome_linkability says whether outcome events CAN link.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.stg_crimes AS
WITH cleaned AS (
    SELECT
        crs.crime_id,
        NULLIF(btrim(crs.persistent_id), '')        AS persistent_id,
        crs.category_code,
        crs.crime_month,
        crs.location_id,
        NULLIF(btrim(crs.location_type), '')        AS location_type,
        NULLIF(btrim(crs.latest_outcome), '')       AS latest_outcome,
        crs.latest_outcome_month,
        crs.force_id
    FROM police.crimes AS crs
),
ranked AS (
    SELECT
        cln.*,
        CASE
            WHEN cln.persistent_id IS NULL THEN 1
            ELSE ROW_NUMBER() OVER (
                     PARTITION BY cln.persistent_id
                     ORDER BY cln.latest_outcome_month DESC NULLS LAST, cln.crime_id ASC)
        END                                          AS persistent_id_rank
    FROM cleaned AS cln
)
SELECT
    rnk.crime_id,
    rnk.persistent_id,
    rnk.category_code,
    rnk.crime_month,
    rnk.location_id,
    rnk.location_type,
    (rnk.location_id IS NOT NULL)                           AS has_location,
    (rnk.category_code = 'anti-social-behaviour')           AS is_asb,
    (COALESCE(rnk.location_type, '') = 'BTP')              AS is_btp,
    (rnk.persistent_id_rank > 1)                            AS is_duplicate,
    CASE
        WHEN rnk.category_code = 'anti-social-behaviour'    THEN 'Not applicable (ASB)'
        ELSE COALESCE(rnk.latest_outcome, 'No outcome recorded')
    END                                                     AS latest_outcome_status,
    rnk.latest_outcome_month,
    CASE
        WHEN rnk.category_code = 'anti-social-behaviour'    THEN 'not_applicable_asb'
        WHEN rnk.persistent_id IS NULL                      THEN 'not_linkable_no_id'
        WHEN rnk.location_id   IS NULL                      THEN 'linkable_no_location'
        ELSE                                                     'linkable'
    END                                                     AS outcome_linkability,
    rnk.force_id
FROM ranked AS rnk;

COMMENT ON VIEW analytics.stg_crimes IS
  'T-102: cleaned crimes, one row per source row; is_duplicate flags DQ-02 surplus rows (exclude in facts).';


/* ---------------------------------------------------------------------
   B2. analytics.stg_outcomes   (T-103)
   Grain   : one row per police.outcomes row (402,656) - nothing removed.
   Links   : to the SURVIVING crime row only (is_duplicate = false), so the
             4 duplicate crime pairs cannot double the outcome rows.
   Drops   : person_id (100% NULL, DQ-14).
   Flags   : is_linked_to_crime; is_latest_event (latest event per crime,
             ties broken by outcome_row_id - documented assumption).
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.stg_outcomes AS
SELECT
    otc.outcome_row_id,
    otc.persistent_id,
    otc.crime_id                                         AS api_crime_id,
    otc.outcome_code,
    ocat.outcome_name,
    otc.outcome_month,
    NULLIF(btrim(otc.crime_category_code), '')           AS crime_category_code,
    otc.crime_month,
    otc.location_id,
    scr.crime_id                                         AS linked_crime_id,
    (scr.crime_id IS NOT NULL)                           AS is_linked_to_crime,
    (ROW_NUMBER() OVER (
        PARTITION BY otc.persistent_id
        ORDER BY otc.outcome_month DESC, otc.outcome_row_id DESC) = 1)
                                                         AS is_latest_event,
    -- whole months from crime to this outcome (reporting-lag analysis)
    ((EXTRACT(YEAR  FROM otc.outcome_month) - EXTRACT(YEAR  FROM otc.crime_month)) * 12
    + EXTRACT(MONTH FROM otc.outcome_month) - EXTRACT(MONTH FROM otc.crime_month))::int
                                                         AS months_crime_to_outcome
FROM police.outcomes              AS otc
JOIN police.outcome_categories    AS ocat ON ocat.outcome_code = otc.outcome_code
LEFT JOIN analytics.stg_crimes    AS scr
       ON  scr.persistent_id = otc.persistent_id
       AND scr.is_duplicate  = FALSE;

COMMENT ON VIEW analytics.stg_outcomes IS
  'T-103: outcome events linked to the surviving crime row; person_id dropped; unlinked rows kept and flagged.';


/* ---------------------------------------------------------------------
   B3. analytics.dq_outcome_exceptions   (DQ-03)
       The outcome rows that cannot be linked to any crime.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.dq_outcome_exceptions AS
SELECT
    sto.outcome_row_id,
    sto.persistent_id,
    sto.api_crime_id,
    sto.outcome_code,
    sto.outcome_month,
    sto.crime_category_code,
    sto.crime_month,
    sto.location_id,
    'No matching crime on persistent_id or crime_id'::text AS exception_reason
FROM analytics.stg_outcomes AS sto
WHERE sto.is_linked_to_crime = FALSE;


/* =====================================================================
   PART C - VALIDATION (read-only)
   ===================================================================== */

/* ---------------------------------------------------------------------
   S1. Before/after reconciliation: no rows lost or added.
   --------------------------------------------------------------------- */
SELECT 'crimes' AS object,
       (SELECT COUNT(*) FROM police.crimes)          AS source_rows,
       (SELECT COUNT(*) FROM analytics.stg_crimes)   AS staging_rows
UNION ALL
SELECT 'outcomes',
       (SELECT COUNT(*) FROM police.outcomes),
       (SELECT COUNT(*) FROM analytics.stg_outcomes);


/* ---------------------------------------------------------------------
   S2. stg_crimes flag profile + DQ-01/DQ-02 confirmation.
       Expect: duplicates = 4; no_id_not_asb_not_btp = 0 (proves the 500
       non-ASB crimes without an id are exactly the BTP crimes).
   --------------------------------------------------------------------- */
SELECT
    COUNT(*)                                                             AS total_rows,
    COUNT(*) FILTER (WHERE is_duplicate)                                 AS duplicates_flagged,
    COUNT(*) FILTER (WHERE NOT is_duplicate)                             AS rows_after_dedup,
    COUNT(*) FILTER (WHERE is_asb)                                       AS asb,
    COUNT(*) FILTER (WHERE is_btp)                                       AS btp,
    COUNT(*) FILTER (WHERE persistent_id IS NULL AND is_btp)             AS btp_without_id,
    COUNT(*) FILTER (WHERE persistent_id IS NULL
                       AND NOT is_asb AND NOT COALESCE(is_btp, FALSE))   AS no_id_not_asb_not_btp,
    COUNT(*) FILTER (WHERE NOT has_location)                             AS no_location,
    COUNT(DISTINCT persistent_id)                                        AS distinct_persistent_ids,
    COUNT(*) FILTER (WHERE persistent_id IS NOT NULL AND NOT is_duplicate) AS non_dup_rows_with_id
FROM analytics.stg_crimes;


/* ---------------------------------------------------------------------
   S3. Outcome linkability of crimes (one row per class).
   --------------------------------------------------------------------- */
SELECT
    outcome_linkability,
    COUNT(*)                                                        AS crimes,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2)   AS pct
FROM analytics.stg_crimes
WHERE NOT is_duplicate
GROUP BY outcome_linkability
ORDER BY crimes DESC;


/* ---------------------------------------------------------------------
   S4. stg_outcomes link check. Expect linked 402,633 / unlinked 23,
       exceptions view = 23, and latest events = distinct persistent_ids.
   --------------------------------------------------------------------- */
SELECT
    COUNT(*)                                            AS outcome_rows,
    COUNT(*) FILTER (WHERE is_linked_to_crime)          AS linked_rows,
    COUNT(*) FILTER (WHERE NOT is_linked_to_crime)      AS unlinked_rows,
    (SELECT COUNT(*) FROM analytics.dq_outcome_exceptions) AS exception_view_rows,
    COUNT(*) FILTER (WHERE is_latest_event)             AS latest_event_rows,
    COUNT(DISTINCT persistent_id)                       AS distinct_crimes_in_outcomes,
    MIN(months_crime_to_outcome)                        AS min_lag_months,
    MAX(months_crime_to_outcome)                        AS max_lag_months
FROM analytics.stg_outcomes;


/* ---------------------------------------------------------------------
   S5. Does crimes.latest_outcome agree with the latest outcome EVENT?
       Top combinations; agreement shows the two sources are consistent,
       disagreements show where the status-only labels sit.
   --------------------------------------------------------------------- */
SELECT
    scr.latest_outcome_status                                    AS crime_latest_status,
    sto.outcome_name                                             AS latest_event_name,
    (lower(scr.latest_outcome_status) = lower(sto.outcome_name)) AS agrees,
    COUNT(*)                                                     AS crimes
FROM analytics.stg_crimes   AS scr
JOIN analytics.stg_outcomes AS sto
      ON  sto.linked_crime_id = scr.crime_id
      AND sto.is_latest_event
WHERE NOT scr.is_duplicate
GROUP BY 1, 2, 3
ORDER BY crimes DESC
LIMIT 20;
