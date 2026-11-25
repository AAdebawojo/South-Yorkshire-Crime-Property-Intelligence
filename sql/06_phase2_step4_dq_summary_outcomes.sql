/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 2 - Step 4: data quality summary + outcome completeness and lag
   Run in DBeaver against: CrimeData
   Part A: creates 3 views (all importable into Power BI later)
   Part B: read-only queries to share
   ===================================================================== */


/* =====================================================================
   PART A - VIEWS
   ===================================================================== */

/* ---------------------------------------------------------------------
   A1. analytics.vw_dq_summary   (T-109)
   One row per data quality check, with value, denominator, % and a
   PASS / INFO / WARN status. Re-run any time; it always reflects the
   current data. Intended for the methodology section and a report
   "data quality" tooltip or page.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.vw_dq_summary AS
WITH crime_base AS (
    SELECT
        COUNT(*)                                                             AS staging_rows,
        COUNT(*) FILTER (WHERE is_duplicate)                                 AS duplicate_rows,
        COUNT(*) FILTER (WHERE NOT is_duplicate)                             AS crimes,
        COUNT(*) FILTER (WHERE NOT is_duplicate AND has_location)            AS located,
        COUNT(*) FILTER (WHERE NOT is_duplicate AND NOT is_asb)              AS non_asb
    FROM analytics.stg_crimes
),
geo AS (
    SELECT
        COUNT(*) FILTER (WHERE sl.lsoa_match_method LIKE 'exact%')           AS exact_lsoa,
        COUNT(*) FILTER (WHERE sl.lsoa_match_method = 'nearest_point_fallback') AS fallback_lsoa,
        COUNT(*) FILTER (WHERE sl.lsoa_match_method = 'unassigned')          AS no_lsoa,
        COUNT(*) FILTER (WHERE sl.lsoa_code IS NOT NULL
                           AND NOT sl.is_south_yorkshire_lsoa)               AS out_of_county
    FROM analytics.stg_crimes    AS scr
    JOIN analytics.stg_locations AS sl ON sl.location_id = scr.location_id
    WHERE NOT scr.is_duplicate
),
stages AS (
    SELECT
        COUNT(*) FILTER (WHERE cos.outcome_stage = 'Concluded')              AS concluded,
        COUNT(*) FILTER (WHERE cos.outcome_stage = 'Pending')                AS pending,
        COUNT(*) FILTER (WHERE cos.outcome_stage = 'Unknown')                AS unknown_stage,
        COUNT(*) FILTER (WHERE cos.outcome_stage IS NULL)                    AS unmapped_status
    FROM analytics.stg_crimes              AS scr
    LEFT JOIN analytics.cfg_outcome_status AS cos ON cos.outcome_status_name = scr.latest_outcome_status
    WHERE NOT scr.is_duplicate AND NOT scr.is_asb
),
other AS (
    SELECT
        (SELECT COUNT(*) FROM police.crimes)                                 AS source_rows,
        (SELECT COUNT(*) FROM analytics.dq_outcome_exceptions)               AS orphan_outcomes,
        (SELECT COUNT(*) FROM analytics.stg_outcomes)                        AS outcome_rows,
        (SELECT COUNT(*) FROM analytics.stg_crimes AS scr
           LEFT JOIN analytics.cfg_crime_category AS cfg ON cfg.category_code = scr.category_code
          WHERE cfg.category_code IS NULL OR NOT cfg.include_in_analysis)    AS unmapped_category
)
SELECT check_id, check_area, check_description, measured_value, denominator,
       ROUND(100.0 * measured_value / NULLIF(denominator, 0), 2) AS pct,
       status, treatment
FROM crime_base, geo, stages, other,
LATERAL (VALUES
    ('DQS-01', 'Completeness', 'Staging crime rows equal source rows',          crime_base.staging_rows, other.source_rows,
        CASE WHEN crime_base.staging_rows = other.source_rows THEN 'PASS' ELSE 'WARN' END, 'Views never drop rows'),
    ('DQS-02', 'Duplicates',   'Duplicate crime rows flagged (DQ-02)',          crime_base.duplicate_rows, crime_base.staging_rows,
        'INFO', 'Flagged, excluded from facts'),
    ('DQS-03', 'Validity',     'Crimes with an unmapped or excluded category',  other.unmapped_category, crime_base.staging_rows,
        CASE WHEN other.unmapped_category = 0 THEN 'PASS' ELSE 'WARN' END, 'cfg_crime_category'),
    ('DQS-04', 'Geography',    'Crimes with a map location',                    crime_base.located, crime_base.crimes,
        'INFO', 'No-location crimes kept; counted at force/district level only'),
    ('DQS-05', 'Geography',    'Located crimes with an exact LSOA match',       geo.exact_lsoa, crime_base.located,
        CASE WHEN geo.exact_lsoa >= 0.99 * crime_base.located THEN 'PASS' ELSE 'WARN' END, 'T-101'),
    ('DQS-06', 'Geography',    'Located crimes with LSOA from nearest point',   geo.fallback_lsoa, crime_base.located,
        'INFO', 'T-105, within 500 m'),
    ('DQS-07', 'Geography',    'Located crimes with no LSOA',                   geo.no_lsoa, crime_base.located,
        CASE WHEN geo.no_lsoa <= 0.001 * crime_base.located THEN 'PASS' ELSE 'WARN' END, 'Unknown LSOA member'),
    ('DQS-08', 'Geography',    'Located crimes in LSOAs outside South Yorkshire', geo.out_of_county, crime_base.located,
        'INFO', 'Excluded from LSOA rankings (DQ-20)'),
    ('DQS-09', 'Outcomes',     'Outcome rows not linked to a crime',            other.orphan_outcomes, other.outcome_rows,
        CASE WHEN other.orphan_outcomes <= 0.001 * other.outcome_rows THEN 'PASS' ELSE 'WARN' END, 'dq_outcome_exceptions'),
    ('DQS-10', 'Outcomes',     'Non-ASB crimes with an unmapped status',        stages.unmapped_status, crime_base.non_asb,
        CASE WHEN stages.unmapped_status = 0 THEN 'PASS' ELSE 'WARN' END, 'cfg_outcome_status'),
    ('DQS-11', 'Outcomes',     'Non-ASB crimes with a concluded outcome',       stages.concluded, crime_base.non_asb,
        'INFO', 'See vw_outcome_completeness_month for the lag effect'),
    ('DQS-12', 'Outcomes',     'Non-ASB crimes still pending',                  stages.pending, crime_base.non_asb,
        'INFO', 'Mostly recent months (reporting lag)'),
    ('DQS-13', 'Outcomes',     'Non-ASB crimes with unknown status',            stages.unknown_stage, crime_base.non_asb,
        'INFO', 'Not treated as unsuccessful')
) AS checks(check_id, check_area, check_description, measured_value, denominator, status, treatment);

COMMENT ON VIEW analytics.vw_dq_summary IS 'T-109: live data quality scorecard.';


/* ---------------------------------------------------------------------
   A2. analytics.vw_outcome_completeness_month   (T-110, DQ-12)
   Grain: one row per crime month. Non-ASB, non-duplicate crimes only.
   Shows how the share of concluded crimes rises with time since the
   crime: the evidence for choosing a "mature" window in Phase 5.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.vw_outcome_completeness_month AS
WITH latest_month AS (
    SELECT MAX(month) AS last_month FROM police.available_months
)
SELECT
    scr.crime_month,
    ((EXTRACT(YEAR  FROM lm.last_month) - EXTRACT(YEAR  FROM scr.crime_month)) * 12
    + EXTRACT(MONTH FROM lm.last_month) - EXTRACT(MONTH FROM scr.crime_month))::int  AS months_of_follow_up,
    COUNT(*)                                                                         AS crimes_non_asb,
    COUNT(*) FILTER (WHERE cos.outcome_stage = 'Concluded')                          AS concluded,
    COUNT(*) FILTER (WHERE cos.outcome_stage = 'Pending')                            AS pending,
    COUNT(*) FILTER (WHERE cos.outcome_stage = 'Unknown')                            AS unknown_status,
    ROUND(100.0 * COUNT(*) FILTER (WHERE cos.outcome_stage = 'Concluded')
          / NULLIF(COUNT(*), 0), 2)                                                  AS pct_concluded,
    ROUND(100.0 * COUNT(*) FILTER (WHERE cos.outcome_stage = 'Pending')
          / NULLIF(COUNT(*), 0), 2)                                                  AS pct_pending
FROM analytics.stg_crimes              AS scr
JOIN analytics.cfg_outcome_status      AS cos ON cos.outcome_status_name = scr.latest_outcome_status
CROSS JOIN latest_month                AS lm
WHERE NOT scr.is_duplicate
  AND NOT scr.is_asb
GROUP BY scr.crime_month, lm.last_month;

COMMENT ON VIEW analytics.vw_outcome_completeness_month IS
  'T-110: outcome stage mix by crime month (non-ASB). Evidence for reporting lag (DQ-12).';


/* ---------------------------------------------------------------------
   A3. analytics.vw_outcome_maturity_curve   (T-111, DQ-12)
   For crimes with at least 24 months of follow-up, the cumulative share
   that had reached a CONCLUDED outcome event within k months (k = 0..24).
   Population: linkable crimes (located, with id, non-ASB, non-duplicate),
   because only these can have outcome events.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.vw_outcome_maturity_curve AS
WITH latest_month AS (
    SELECT MAX(month) AS last_month FROM police.available_months
),
cohort AS (
    SELECT scr.crime_id, scr.crime_month
    FROM analytics.stg_crimes AS scr
    CROSS JOIN latest_month   AS lm
    WHERE NOT scr.is_duplicate
      AND scr.outcome_linkability = 'linkable'
      AND scr.crime_month <= (lm.last_month - INTERVAL '24 months')
),
first_concluded AS (
    SELECT sto.linked_crime_id               AS crime_id,
           MIN(sto.months_crime_to_outcome)  AS months_to_conclusion
    FROM analytics.stg_outcomes        AS sto
    JOIN analytics.cfg_outcome_status  AS cos ON cos.outcome_status_name = sto.outcome_name
    WHERE sto.is_linked_to_crime
      AND cos.outcome_stage = 'Concluded'
    GROUP BY sto.linked_crime_id
),
lags AS (
    SELECT gs.k AS months_since_crime FROM generate_series(0, 24) AS gs(k)
)
SELECT
    lg.months_since_crime,
    (SELECT COUNT(*) FROM cohort)                                       AS cohort_crimes,
    (SELECT MIN(crime_month) FROM cohort)                               AS cohort_from,
    (SELECT MAX(crime_month) FROM cohort)                               AS cohort_to,
    COUNT(fc.crime_id)                                                  AS concluded_by_then,
    ROUND(100.0 * COUNT(fc.crime_id) / NULLIF((SELECT COUNT(*) FROM cohort), 0), 2)
                                                                        AS cumulative_pct_concluded
FROM lags AS lg
LEFT JOIN (cohort AS ch
           JOIN first_concluded AS fc ON fc.crime_id = ch.crime_id)
       ON fc.months_to_conclusion <= lg.months_since_crime
GROUP BY lg.months_since_crime;

COMMENT ON VIEW analytics.vw_outcome_maturity_curve IS
  'T-111: cumulative % of a mature cohort reaching a concluded outcome by months since crime (DQ-12).';


/* =====================================================================
   PART B - QUERIES TO SHARE (read-only)
   ===================================================================== */

-- R1. Data quality scorecard (13 rows)
SELECT * FROM analytics.vw_dq_summary ORDER BY check_id;

-- R2. Outcome completeness by crime month (36 rows)
SELECT * FROM analytics.vw_outcome_completeness_month ORDER BY crime_month;

-- R3. Outcome maturity curve (25 rows)
SELECT * FROM analytics.vw_outcome_maturity_curve ORDER BY months_since_crime;

-- R4. Neighbourhood names as published (display-name check before Phase 3)
SELECT
    nbh.neighbourhood_id,
    nbh.neighbourhood_name,
    length(nbh.neighbourhood_name)               AS name_length,
    split_part(nbh.neighbourhood_name, ' ', 1)   AS derived_district
FROM police.neighbourhoods AS nbh
ORDER BY derived_district, nbh.neighbourhood_name;
