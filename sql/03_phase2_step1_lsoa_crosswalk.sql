/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 2 - Step 1: analytics schema + location -> LSOA crosswalk
   Run in DBeaver against: CrimeData
   Prerequisite: python load_bulk_csv.py has loaded police_bulk.street_crimes_raw

   Part A creates objects (run once; safe to re-run).
   Part B is read-only validation: share the results.
   ===================================================================== */


/* =====================================================================
   PART A - CREATE OBJECTS
   ===================================================================== */

CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA analytics IS
  'Analytical layer for Power BI: staging views, dimensions, facts, aggregates. Built from police (API) and police_bulk (CSV); never edits them.';


/* ---------------------------------------------------------------------
   A1. analytics.xref_location_lsoa  (transformation T-101)
   Grain   : one row per police.locations.location_id (18,309 expected)
   Logic   : exact match of the anonymised snap-point coordinates to the
             bulk CSV coordinates, which carry an LSOA code.
             If one point carries more than one LSOA across the 36 files,
             the LSOA seen on the most rows wins and the row is flagged
             'matched_ambiguous'.
   Why MV  : reproducible from source with REFRESH MATERIALIZED VIEW,
             and fast to join (indexed).
   --------------------------------------------------------------------- */
DROP MATERIALIZED VIEW IF EXISTS analytics.xref_location_lsoa;

CREATE MATERIALIZED VIEW analytics.xref_location_lsoa AS
WITH csv_points AS (
    SELECT
        NULLIF(btrim(raw.latitude),  '')::numeric(9,6)    AS latitude,
        NULLIF(btrim(raw.longitude), '')::numeric(9,6)    AS longitude,
        btrim(raw.lsoa_code)                              AS lsoa_code,
        btrim(raw.lsoa_name)                              AS lsoa_name,
        COUNT(*)                                          AS csv_rows,
        MIN(raw.month)                                    AS first_csv_month,
        MAX(raw.month)                                    AS last_csv_month
    FROM police_bulk.street_crimes_raw AS raw
    WHERE COALESCE(btrim(raw.lsoa_code), '') <> ''
      AND COALESCE(btrim(raw.latitude),  '') <> ''
      AND COALESCE(btrim(raw.longitude), '') <> ''
    GROUP BY 1, 2, 3, 4
),
ranked_points AS (
    SELECT
        cp.*,
        COUNT(*)     OVER (PARTITION BY cp.latitude, cp.longitude)                       AS lsoa_candidates,
        ROW_NUMBER() OVER (PARTITION BY cp.latitude, cp.longitude
                           ORDER BY cp.csv_rows DESC, cp.lsoa_code)                     AS candidate_rank
    FROM csv_points AS cp
)
SELECT
    loc.location_id,
    rp.lsoa_code,
    rp.lsoa_name,
    -- LSOA names are '<Local authority> <3 digits><letter>', e.g. 'Sheffield 012A'
    regexp_replace(rp.lsoa_name, '\s+\S+$', '')               AS lsoa_local_authority,
    CASE
        WHEN rp.lsoa_code IS NULL      THEN 'unmatched'
        WHEN rp.lsoa_candidates > 1    THEN 'matched_ambiguous'
        ELSE                                'matched'
    END                                                       AS match_status,
    COALESCE(rp.lsoa_candidates, 0)                           AS lsoa_candidates,
    COALESCE(rp.csv_rows, 0)                                  AS csv_rows_at_point,
    rp.first_csv_month,
    rp.last_csv_month
FROM police.locations AS loc
LEFT JOIN ranked_points AS rp
       ON  rp.latitude       = loc.latitude
       AND rp.longitude      = loc.longitude
       AND rp.candidate_rank = 1;

CREATE UNIQUE INDEX ux_xref_location_lsoa ON analytics.xref_location_lsoa (location_id);
CREATE INDEX ix_xref_location_lsoa_code   ON analytics.xref_location_lsoa (lsoa_code);

COMMENT ON MATERIALIZED VIEW analytics.xref_location_lsoa IS
  'T-101: police.locations -> LSOA 2021 via exact coordinate match to bulk CSVs. Refresh after reloading either source.';


/* =====================================================================
   PART B - VALIDATION (read-only)
   ===================================================================== */

/* ---------------------------------------------------------------------
   V1. Raw CSV load: one row per month. Expect 36 months, Oct 2023 - Sep 2026.
   --------------------------------------------------------------------- */
SELECT
    raw.month,
    COUNT(*)                                                         AS csv_rows,
    COUNT(*) FILTER (WHERE COALESCE(btrim(raw.lsoa_code), '') = '')  AS rows_without_lsoa,
    COUNT(*) FILTER (WHERE COALESCE(btrim(raw.crime_id),  '') = '')  AS rows_without_crime_id,
    COUNT(DISTINCT raw.source_file)                                  AS files
FROM police_bulk.street_crimes_raw AS raw
GROUP BY raw.month
ORDER BY raw.month;


/* ---------------------------------------------------------------------
   V2. Does any coordinate pair carry more than one LSOA across all files?
       (Expect 0 or very few. Non-zero would mean boundary changes or
       inconsistent snapping between releases.)
   --------------------------------------------------------------------- */
WITH point_lsoas AS (
    SELECT raw.latitude, raw.longitude, COUNT(DISTINCT raw.lsoa_code) AS distinct_lsoas
    FROM police_bulk.street_crimes_raw AS raw
    WHERE COALESCE(btrim(raw.lsoa_code), '') <> ''
    GROUP BY raw.latitude, raw.longitude
)
SELECT
    COUNT(*)                                          AS csv_coordinate_pairs,
    COUNT(*) FILTER (WHERE pl.distinct_lsoas > 1)     AS pairs_with_multiple_lsoas,
    MAX(pl.distinct_lsoas)                            AS max_lsoas_per_pair
FROM point_lsoas AS pl;


/* ---------------------------------------------------------------------
   V3. Crosswalk coverage: by location points AND weighted by crimes.
       Crime-weighted coverage is the figure that matters for analysis.
   --------------------------------------------------------------------- */
SELECT
    xr.match_status,
    COUNT(*)                                                                AS location_points,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2)           AS pct_points,
    SUM(crime_counts.crimes)                                                AS crimes,
    ROUND(100.0 * SUM(crime_counts.crimes)
          / NULLIF(SUM(SUM(crime_counts.crimes)) OVER (), 0), 2)            AS pct_located_crimes
FROM analytics.xref_location_lsoa AS xr
LEFT JOIN (
    SELECT crs.location_id, COUNT(*) AS crimes
    FROM police.crimes AS crs
    WHERE crs.location_id IS NOT NULL
    GROUP BY crs.location_id
) AS crime_counts ON crime_counts.location_id = xr.location_id
GROUP BY xr.match_status
ORDER BY location_points DESC;


/* ---------------------------------------------------------------------
   V4. Cross-check of two independent geographies:
       neighbourhood district (derived from the police neighbourhood name,
       via the loader's point-in-polygon) vs. LSOA local authority (from
       the CSVs). Off-diagonal rows are disagreements to investigate.
   --------------------------------------------------------------------- */
SELECT
    split_part(nbh.neighbourhood_name, ' ', 1)        AS neighbourhood_district,
    COALESCE(xr.lsoa_local_authority, '(unmatched)')  AS lsoa_local_authority,
    COUNT(*)                                          AS location_points
FROM analytics.xref_location_lsoa AS xr
JOIN police.locations             AS loc ON loc.location_id     = xr.location_id
JOIN police.neighbourhoods        AS nbh ON nbh.neighbourhood_id = loc.neighbourhood_id
GROUP BY 1, 2
ORDER BY 1, 3 DESC;


/* ---------------------------------------------------------------------
   V5. Why are points unmatched? Compares each unmatched point's first
       crime month with the last month present in the loaded CSVs.
   --------------------------------------------------------------------- */
WITH csv_range AS (
    SELECT MAX(to_date(raw.month, 'YYYY-MM')) AS last_csv_month
    FROM police_bulk.street_crimes_raw AS raw
),
unmatched_usage AS (
    SELECT
        xr.location_id,
        MIN(crs.crime_month)  AS first_crime_month,
        COUNT(crs.crime_id)   AS crimes
    FROM analytics.xref_location_lsoa AS xr
    LEFT JOIN police.crimes AS crs ON crs.location_id = xr.location_id
    WHERE xr.match_status = 'unmatched'
    GROUP BY xr.location_id
)
SELECT
    CASE
        WHEN uu.first_crime_month IS NULL              THEN 'used by outcomes only'
        WHEN uu.first_crime_month > cr.last_csv_month  THEN 'first used after the last CSV month'
        ELSE                                                'used within CSV range'
    END                         AS reason_group,
    COUNT(*)                    AS unmatched_points,
    SUM(uu.crimes)              AS crimes_at_those_points
FROM unmatched_usage AS uu
CROSS JOIN csv_range AS cr
GROUP BY 1
ORDER BY unmatched_points DESC;


/* ---------------------------------------------------------------------
   V6. LSOA granularity: how many LSOAs, and how crimes spread across them
   --------------------------------------------------------------------- */
WITH crimes_per_lsoa AS (
    SELECT xr.lsoa_code, xr.lsoa_local_authority, COUNT(crs.crime_id) AS crimes
    FROM police.crimes                AS crs
    JOIN analytics.xref_location_lsoa AS xr ON xr.location_id = crs.location_id
    WHERE xr.lsoa_code IS NOT NULL
    GROUP BY xr.lsoa_code, xr.lsoa_local_authority
)
SELECT
    CASE WHEN GROUPING(cpl.lsoa_local_authority) = 1 THEN '** All areas **'
         ELSE cpl.lsoa_local_authority END                           AS lsoa_local_authority,
    COUNT(*)                                                         AS lsoas,
    SUM(cpl.crimes)                                                  AS crimes,
    MIN(cpl.crimes)                                                  AS min_crimes_per_lsoa,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cpl.crimes)::int     AS median_crimes_per_lsoa,
    MAX(cpl.crimes)                                                  AS max_crimes_per_lsoa
FROM crimes_per_lsoa AS cpl
GROUP BY ROLLUP (cpl.lsoa_local_authority)
ORDER BY cpl.lsoa_local_authority NULLS LAST;


/* ---------------------------------------------------------------------
   V7. API vs CSV reconciliation on persistent_id over the months both
       sources cover. Shows how far they agree crime-by-crime.
   --------------------------------------------------------------------- */
WITH overlap AS (
    SELECT
        GREATEST((SELECT MIN(crime_month) FROM police.crimes),
                 (SELECT MIN(to_date(month, 'YYYY-MM')) FROM police_bulk.street_crimes_raw)) AS from_month,
        LEAST   ((SELECT MAX(crime_month) FROM police.crimes),
                 (SELECT MAX(to_date(month, 'YYYY-MM')) FROM police_bulk.street_crimes_raw)) AS to_month
),
api AS (
    SELECT crs.persistent_id
    FROM police.crimes AS crs, overlap AS ov
    WHERE COALESCE(btrim(crs.persistent_id), '') <> ''
      AND crs.crime_month BETWEEN ov.from_month AND ov.to_month
),
csv AS (
    SELECT DISTINCT btrim(raw.crime_id) AS persistent_id
    FROM police_bulk.street_crimes_raw AS raw, overlap AS ov
    WHERE COALESCE(btrim(raw.crime_id), '') <> ''
      AND to_date(raw.month, 'YYYY-MM') BETWEEN ov.from_month AND ov.to_month
)
SELECT
    (SELECT from_month FROM overlap)                                             AS overlap_from,
    (SELECT to_month   FROM overlap)                                             AS overlap_to,
    (SELECT COUNT(*) FROM api)                                                   AS api_crimes_with_id,
    (SELECT COUNT(*) FROM csv)                                                   AS csv_crimes_with_id,
    (SELECT COUNT(*) FROM api WHERE EXISTS
        (SELECT 1 FROM csv WHERE csv.persistent_id = api.persistent_id))         AS in_both,
    (SELECT COUNT(*) FROM api WHERE NOT EXISTS
        (SELECT 1 FROM csv WHERE csv.persistent_id = api.persistent_id))         AS api_only,
    (SELECT COUNT(*) FROM csv WHERE NOT EXISTS
        (SELECT 1 FROM api WHERE api.persistent_id = csv.persistent_id))         AS csv_only;
