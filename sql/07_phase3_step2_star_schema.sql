/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 3 - Step 2: star schema (dimensions, facts, refresh procedure)
   Run in DBeaver against: CrimeData   (Alt+X runs the whole script)

   Part A  parameter table
   Part B  dimension objects
   Part C  fact materialized views (created empty)
   Part D  refresh procedure + first load:  CALL analytics.sp_refresh_model();
   Part E  model validation (read-only) - share the results

   Safe to re-run. To reload everything later (e.g. after new API data):
       CALL analytics.sp_refresh_model();
   ===================================================================== */


/* =====================================================================
   PART A - PARAMETERS
   ===================================================================== */
CREATE TABLE IF NOT EXISTS analytics.cfg_parameter (
    parameter_name   VARCHAR(60)  PRIMARY KEY,
    parameter_value  NUMERIC      NOT NULL,
    description      TEXT         NOT NULL
);

INSERT INTO analytics.cfg_parameter (parameter_name, parameter_value, description)
VALUES ('outcome_maturity_months', 6,
        'Outcome KPIs use only crime months at least this many months before the latest month (DQ-12; R3: 98.6% of outcomes recorded by 6 months).')
ON CONFLICT (parameter_name) DO NOTHING;


/* =====================================================================
   PART B - DIMENSIONS
   Keys: integer surrogate keys (identity), stable across refreshes
   because members are upserted on their business key. Every dimension
   has a fixed -1 "unknown / not applicable" member so no fact row is
   ever orphaned or blank. dim_month uses the natural key YYYYMM.
   ===================================================================== */

/* ---------------------------------------------------------------------
   B1. analytics.dim_month   (view; month grain - decision D-05)
   One row per month the API holds (36). month_index supports MoM / YoY /
   rolling windows in DAX by simple arithmetic.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.dim_month AS
WITH months AS (
    SELECT
        avm.month                                         AS month_start,
        -- calendar-based index: stays correct even if a month were ever missing
        ((EXTRACT(YEAR FROM avm.month) * 12 + EXTRACT(MONTH FROM avm.month))
         - MIN(EXTRACT(YEAR FROM avm.month) * 12 + EXTRACT(MONTH FROM avm.month)) OVER ()
         + 1)::int                                        AS month_index,
        MAX(avm.month) OVER ()                            AS latest_month
    FROM police.available_months AS avm
),
maturity AS (
    SELECT parameter_value::int AS maturity_months
    FROM analytics.cfg_parameter
    WHERE parameter_name = 'outcome_maturity_months'
),
derived AS (
    SELECT
        m.*,
        EXTRACT(YEAR  FROM m.month_start)::int                                       AS year_number,
        EXTRACT(MONTH FROM m.month_start)::int                                       AS month_number,
        ((EXTRACT(YEAR  FROM m.latest_month) - EXTRACT(YEAR  FROM m.month_start)) * 12
        + EXTRACT(MONTH FROM m.latest_month) - EXTRACT(MONTH FROM m.month_start))::int AS months_before_latest
    FROM months AS m
)
SELECT
    (d.year_number * 100 + d.month_number)                                AS month_key,
    d.month_start,
    (d.month_start + INTERVAL '1 month - 1 day')::date                    AS month_end,
    d.month_index,
    d.year_number                                                         AS year,
    EXTRACT(QUARTER FROM d.month_start)::int                              AS quarter_number,
    'Q' || EXTRACT(QUARTER FROM d.month_start)::int                       AS quarter_label,
    d.year_number || ' Q' || EXTRACT(QUARTER FROM d.month_start)::int     AS year_quarter,
    d.month_number,
    trim(to_char(d.month_start, 'Month'))                                 AS month_name,
    to_char(d.month_start, 'Mon')                                         AS month_short,
    to_char(d.month_start, 'YYYY-MM')                                     AS year_month,
    to_char(d.month_start, 'Mon YYYY')                                    AS month_label,
    -- UK financial year, April to March
    CASE WHEN d.month_number >= 4
         THEN 'FY ' || d.year_number || '/' || right((d.year_number + 1)::text, 2)
         ELSE 'FY ' || (d.year_number - 1) || '/' || right(d.year_number::text, 2)
    END                                                                   AS financial_year,
    CASE WHEN d.month_number >= 4 THEN d.year_number ELSE d.year_number - 1 END
                                                                          AS financial_year_start,
    -- Meteorological seasons (Met Office convention)
    CASE WHEN d.month_number IN (12, 1, 2) THEN 'Winter'
         WHEN d.month_number IN (3, 4, 5)  THEN 'Spring'
         WHEN d.month_number IN (6, 7, 8)  THEN 'Summer'
         ELSE 'Autumn' END                                                AS season,
    CASE WHEN d.month_number IN (12, 1, 2) THEN 4
         WHEN d.month_number IN (3, 4, 5)  THEN 1
         WHEN d.month_number IN (6, 7, 8)  THEN 2
         ELSE 3 END                                                       AS season_sort,
    CASE WHEN d.month_number = 12 THEN 'Winter ' || d.year_number || '/' || right((d.year_number + 1)::text, 2)
         WHEN d.month_number IN (1, 2) THEN 'Winter ' || (d.year_number - 1) || '/' || right(d.year_number::text, 2)
         ELSE (CASE WHEN d.month_number IN (3,4,5) THEN 'Spring '
                    WHEN d.month_number IN (6,7,8) THEN 'Summer '
                    ELSE 'Autumn ' END) || d.year_number END              AS season_label,
    d.months_before_latest,
    (d.months_before_latest = 0)                                          AS is_latest_month,
    (d.months_before_latest < 12)                                         AS is_last_12_months,
    (d.months_before_latest BETWEEN 12 AND 23)                            AS is_prior_12_months,
    (d.months_before_latest >= mt.maturity_months)                        AS is_outcome_mature
FROM derived AS d
CROSS JOIN maturity AS mt;

COMMENT ON VIEW analytics.dim_month IS
  'T-201: month-grain date dimension (D-05). month_key = YYYYMM. is_outcome_mature uses cfg_parameter.';


/* ---------------------------------------------------------------------
   B2. analytics.dim_lsoa   (table)
   One row per LSOA seen in the data + unknown member -1.
   Phase 4 will add population, IMD, price and census attributes.
   --------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS analytics.dim_lsoa (
    lsoa_key            INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    lsoa_code           VARCHAR(12)  NOT NULL UNIQUE,
    lsoa_name           VARCHAR(100) NOT NULL,
    local_authority     VARCHAR(100) NOT NULL,
    is_south_yorkshire  BOOLEAN      NOT NULL,
    is_unknown_member   BOOLEAN      NOT NULL DEFAULT FALSE
);

INSERT INTO analytics.dim_lsoa (lsoa_key, lsoa_code, lsoa_name, local_authority, is_south_yorkshire, is_unknown_member)
VALUES (-1, 'UNKNOWN', 'Unknown LSOA', 'Unknown', FALSE, TRUE)
ON CONFLICT DO NOTHING;


/* ---------------------------------------------------------------------
   B3. analytics.dim_neighbourhood   (table)
   display_name strips a trailing "Neighbourhood Polic..." suffix (DQ-21);
   the published name is kept.
   --------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS analytics.dim_neighbourhood (
    neighbourhood_key   INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    neighbourhood_id    VARCHAR(60)  NOT NULL UNIQUE,
    published_name      VARCHAR(255) NOT NULL,
    display_name        VARCHAR(255) NOT NULL,
    district            VARCHAR(60)  NOT NULL,
    centre_latitude     NUMERIC(9,6),
    centre_longitude    NUMERIC(9,6),
    boundary_wkt        TEXT,
    is_unknown_member   BOOLEAN      NOT NULL DEFAULT FALSE
);

INSERT INTO analytics.dim_neighbourhood
    (neighbourhood_key, neighbourhood_id, published_name, display_name, district, is_unknown_member)
VALUES (-1, 'NO_LOCATION', 'No location', 'No location', 'No location', TRUE)
ON CONFLICT DO NOTHING;


/* ---------------------------------------------------------------------
   B4. analytics.dim_location   (table; for point maps and drill-down)
   Geography attributes are copied in for map tooltips.
   --------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS analytics.dim_location (
    location_key        INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    location_id         BIGINT       NOT NULL UNIQUE,
    street_name         VARCHAR(255) NOT NULL,
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    is_station_point    BOOLEAN      NOT NULL,
    lsoa_code           VARCHAR(12),
    lsoa_name           VARCHAR(100),
    lsoa_match_method   VARCHAR(30)  NOT NULL,
    neighbourhood_name  VARCHAR(255),
    district            VARCHAR(60),
    is_unknown_member   BOOLEAN      NOT NULL DEFAULT FALSE
);

INSERT INTO analytics.dim_location
    (location_key, location_id, street_name, is_station_point, lsoa_match_method, is_unknown_member)
VALUES (-1, -1, 'No location', FALSE, 'not applicable', TRUE)
ON CONFLICT DO NOTHING;


/* ---------------------------------------------------------------------
   B5. analytics.dim_crime_category   (table; from cfg_crime_category)
   --------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS analytics.dim_crime_category (
    category_key        INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    category_code       VARCHAR(60)  NOT NULL UNIQUE,
    category_name       VARCHAR(200) NOT NULL,
    category_group      VARCHAR(100) NOT NULL,
    group_sort_order    SMALLINT     NOT NULL,
    is_unknown_member   BOOLEAN      NOT NULL DEFAULT FALSE
);

INSERT INTO analytics.dim_crime_category
    (category_key, category_code, category_name, category_group, group_sort_order, is_unknown_member)
VALUES (-1, 'UNKNOWN', 'Unknown category', 'Unknown', 99, TRUE)
ON CONFLICT DO NOTHING;


/* ---------------------------------------------------------------------
   B6. analytics.dim_outcome_status   (table; from cfg_outcome_status)
   outcome_group is filled in Phase 5.
   --------------------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS analytics.dim_outcome_status (
    outcome_status_key   INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    outcome_status_name  VARCHAR(255) NOT NULL UNIQUE,
    outcome_code         VARCHAR(80),
    status_source        VARCHAR(30)  NOT NULL,
    outcome_stage        VARCHAR(20)  NOT NULL,
    stage_sort           SMALLINT     NOT NULL,
    outcome_group        VARCHAR(40),
    is_unknown_member    BOOLEAN      NOT NULL DEFAULT FALSE
);

INSERT INTO analytics.dim_outcome_status
    (outcome_status_key, outcome_status_name, status_source, outcome_stage, stage_sort, is_unknown_member)
VALUES (-1, 'Unknown status', 'derived', 'Unknown', 9, TRUE)
ON CONFLICT DO NOTHING;


/* =====================================================================
   PART C - FACTS (materialized views, created empty; filled in Part D)
   ===================================================================== */

/* ---------------------------------------------------------------------
   C1. analytics.fact_crime
   Grain : one recorded crime (duplicates excluded)  -> expect 527,597
   Keys  : month, LSOA, neighbourhood, location, category, latest status
   crime_id is kept for traceability and the outcome link; it is not
   imported into Power BI.
   --------------------------------------------------------------------- */
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.fact_crime AS
SELECT
    scr.crime_id,
    (EXTRACT(YEAR FROM scr.crime_month) * 100 + EXTRACT(MONTH FROM scr.crime_month))::int  AS month_key,
    COALESCE(dl.lsoa_key, -1)                     AS lsoa_key,
    COALESCE(dn.neighbourhood_key, -1)            AS neighbourhood_key,
    COALESCE(dloc.location_key, -1)               AS location_key,
    COALESCE(dc.category_key, -1)                 AS category_key,
    COALESCE(dos.outcome_status_key, -1)          AS outcome_status_key,
    CASE WHEN scr.latest_outcome_month IS NOT NULL THEN
        ((EXTRACT(YEAR  FROM scr.latest_outcome_month) - EXTRACT(YEAR  FROM scr.crime_month)) * 12
        + EXTRACT(MONTH FROM scr.latest_outcome_month) - EXTRACT(MONTH FROM scr.crime_month))::int
    END                                           AS months_to_latest_outcome,
    scr.has_location,
    scr.is_btp
FROM analytics.stg_crimes                 AS scr
LEFT JOIN analytics.stg_locations         AS sl   ON sl.location_id          = scr.location_id
LEFT JOIN analytics.dim_lsoa              AS dl   ON dl.lsoa_code            = sl.lsoa_code
LEFT JOIN analytics.dim_neighbourhood     AS dn   ON dn.neighbourhood_id     = sl.neighbourhood_id
LEFT JOIN analytics.dim_location          AS dloc ON dloc.location_id        = scr.location_id
LEFT JOIN analytics.dim_crime_category    AS dc   ON dc.category_code        = scr.category_code
LEFT JOIN analytics.dim_outcome_status    AS dos  ON dos.outcome_status_name = scr.latest_outcome_status
WHERE NOT scr.is_duplicate
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_crime_crime_id ON analytics.fact_crime (crime_id);

COMMENT ON MATERIALIZED VIEW analytics.fact_crime IS
  'T-202: one row per recorded crime (duplicates excluded). Count measure = COUNTROWS.';


/* ---------------------------------------------------------------------
   C2. analytics.fact_outcome
   Grain : one outcome event linked to a crime  -> expect 402,633
   Geography / category / crime month are copied from fact_crime, so the
   two facts share dimensions and never need a fact-to-fact relationship.
   --------------------------------------------------------------------- */
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.fact_outcome AS
SELECT
    sto.outcome_row_id,
    sto.linked_crime_id                                                                       AS crime_id,
    (EXTRACT(YEAR FROM sto.outcome_month) * 100 + EXTRACT(MONTH FROM sto.outcome_month))::int AS outcome_month_key,
    fc.month_key                                                                              AS crime_month_key,
    fc.lsoa_key,
    fc.neighbourhood_key,
    fc.location_key,
    fc.category_key,
    COALESCE(dos.outcome_status_key, -1)                                                      AS outcome_status_key,
    sto.months_crime_to_outcome,
    sto.is_latest_event
FROM analytics.stg_outcomes             AS sto
JOIN analytics.fact_crime               AS fc  ON fc.crime_id = sto.linked_crime_id
LEFT JOIN analytics.dim_outcome_status  AS dos ON dos.outcome_status_name = sto.outcome_name
WHERE sto.is_linked_to_crime
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_outcome_row ON analytics.fact_outcome (outcome_row_id);

COMMENT ON MATERIALIZED VIEW analytics.fact_outcome IS
  'T-203: one row per outcome event linked to a crime; dimension keys inherited from fact_crime.';


/* =====================================================================
   PART D - REFRESH PROCEDURE + FIRST LOAD
   Order matters: LSOA lookups -> dimensions -> fact_crime -> fact_outcome
   ===================================================================== */
CREATE OR REPLACE PROCEDURE analytics.sp_refresh_model()
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. geography lookups
    REFRESH MATERIALIZED VIEW analytics.xref_location_lsoa;
    REFRESH MATERIALIZED VIEW analytics.xref_location_lsoa_fallback;

    -- 2. dimensions (upsert on business key: surrogate keys never change)
    INSERT INTO analytics.dim_lsoa (lsoa_code, lsoa_name, local_authority, is_south_yorkshire)
    SELECT DISTINCT ON (sl.lsoa_code)
           sl.lsoa_code, sl.lsoa_name, sl.lsoa_local_authority, sl.is_south_yorkshire_lsoa
    FROM analytics.stg_locations AS sl
    WHERE sl.lsoa_code IS NOT NULL
    ORDER BY sl.lsoa_code
    ON CONFLICT (lsoa_code) DO UPDATE
       SET lsoa_name          = EXCLUDED.lsoa_name,
           local_authority    = EXCLUDED.local_authority,
           is_south_yorkshire = EXCLUDED.is_south_yorkshire;

    INSERT INTO analytics.dim_neighbourhood
        (neighbourhood_id, published_name, display_name, district,
         centre_latitude, centre_longitude, boundary_wkt)
    SELECT
        nbh.neighbourhood_id,
        nbh.neighbourhood_name,
        btrim(regexp_replace(nbh.neighbourhood_name, '\s+Neighbourhood\s+Polic.*$', '', 'i')),
        split_part(nbh.neighbourhood_name, ' ', 1),
        nbh.centre_latitude,
        nbh.centre_longitude,
        nbh.boundary_wkt
    FROM police.neighbourhoods AS nbh
    ON CONFLICT (neighbourhood_id) DO UPDATE
       SET published_name   = EXCLUDED.published_name,
           display_name     = EXCLUDED.display_name,
           district         = EXCLUDED.district,
           centre_latitude  = EXCLUDED.centre_latitude,
           centre_longitude = EXCLUDED.centre_longitude,
           boundary_wkt     = EXCLUDED.boundary_wkt;

    INSERT INTO analytics.dim_location
        (location_id, street_name, latitude, longitude, is_station_point,
         lsoa_code, lsoa_name, lsoa_match_method, neighbourhood_name, district)
    SELECT
        sl.location_id,
        COALESCE(sl.street_name, '(unnamed)'),
        sl.latitude,
        sl.longitude,
        sl.is_station_point,
        sl.lsoa_code,
        sl.lsoa_name,
        sl.lsoa_match_method,
        dn.display_name,
        dn.district
    FROM analytics.stg_locations          AS sl
    LEFT JOIN analytics.dim_neighbourhood AS dn ON dn.neighbourhood_id = sl.neighbourhood_id
    ON CONFLICT (location_id) DO UPDATE
       SET street_name        = EXCLUDED.street_name,
           latitude           = EXCLUDED.latitude,
           longitude          = EXCLUDED.longitude,
           is_station_point   = EXCLUDED.is_station_point,
           lsoa_code          = EXCLUDED.lsoa_code,
           lsoa_name          = EXCLUDED.lsoa_name,
           lsoa_match_method  = EXCLUDED.lsoa_match_method,
           neighbourhood_name = EXCLUDED.neighbourhood_name,
           district           = EXCLUDED.district;

    INSERT INTO analytics.dim_crime_category
        (category_code, category_name, category_group, group_sort_order)
    SELECT cfg.category_code, cfg.category_name, cfg.category_group, cfg.group_sort_order
    FROM analytics.cfg_crime_category AS cfg
    WHERE cfg.include_in_analysis
    ON CONFLICT (category_code) DO UPDATE
       SET category_name    = EXCLUDED.category_name,
           category_group   = EXCLUDED.category_group,
           group_sort_order = EXCLUDED.group_sort_order;

    INSERT INTO analytics.dim_outcome_status
        (outcome_status_name, outcome_code, status_source, outcome_stage, stage_sort, outcome_group)
    SELECT
        cfg.outcome_status_name,
        cfg.outcome_code,
        cfg.status_source,
        cfg.outcome_stage,
        CASE cfg.outcome_stage WHEN 'Concluded' THEN 1 WHEN 'Pending' THEN 2
                               WHEN 'Unknown' THEN 3 ELSE 4 END,
        cfg.outcome_group
    FROM analytics.cfg_outcome_status AS cfg
    ON CONFLICT (outcome_status_name) DO UPDATE
       SET outcome_code  = EXCLUDED.outcome_code,
           status_source = EXCLUDED.status_source,
           outcome_stage = EXCLUDED.outcome_stage,
           stage_sort    = EXCLUDED.stage_sort,
           outcome_group = EXCLUDED.outcome_group;

    -- 3. facts
    REFRESH MATERIALIZED VIEW analytics.fact_crime;
    REFRESH MATERIALIZED VIEW analytics.fact_outcome;
END;
$$;

COMMENT ON PROCEDURE analytics.sp_refresh_model() IS
  'Rebuilds lookups, upserts dimensions, refreshes facts. Run after any data reload.';

CALL analytics.sp_refresh_model();


/* =====================================================================
   PART E - MODEL VALIDATION (read-only)
   ===================================================================== */

/* M1. Row counts per model object */
SELECT 'dim_month'          AS object, COUNT(*) AS rows FROM analytics.dim_month
UNION ALL SELECT 'dim_lsoa',           COUNT(*) FROM analytics.dim_lsoa
UNION ALL SELECT 'dim_neighbourhood',  COUNT(*) FROM analytics.dim_neighbourhood
UNION ALL SELECT 'dim_location',       COUNT(*) FROM analytics.dim_location
UNION ALL SELECT 'dim_crime_category', COUNT(*) FROM analytics.dim_crime_category
UNION ALL SELECT 'dim_outcome_status', COUNT(*) FROM analytics.dim_outcome_status
UNION ALL SELECT 'fact_crime',         COUNT(*) FROM analytics.fact_crime
UNION ALL SELECT 'fact_outcome',       COUNT(*) FROM analytics.fact_outcome;


/* M2. Key uniqueness: duplicates must be 0 for every dimension */
SELECT 'dim_month'          AS dimension, COUNT(*) - COUNT(DISTINCT month_key)          AS duplicate_keys FROM analytics.dim_month
UNION ALL SELECT 'dim_lsoa',           COUNT(*) - COUNT(DISTINCT lsoa_key)           FROM analytics.dim_lsoa
UNION ALL SELECT 'dim_neighbourhood',  COUNT(*) - COUNT(DISTINCT neighbourhood_key)  FROM analytics.dim_neighbourhood
UNION ALL SELECT 'dim_location',       COUNT(*) - COUNT(DISTINCT location_key)       FROM analytics.dim_location
UNION ALL SELECT 'dim_crime_category', COUNT(*) - COUNT(DISTINCT category_key)       FROM analytics.dim_crime_category
UNION ALL SELECT 'dim_outcome_status', COUNT(*) - COUNT(DISTINCT outcome_status_key) FROM analytics.dim_outcome_status;


/* M3. Grain: fact rows must be unique on their grain columns (both 0) */
SELECT
    (SELECT COUNT(*) - COUNT(DISTINCT crime_id)       FROM analytics.fact_crime)   AS fact_crime_duplicate_grain,
    (SELECT COUNT(*) - COUNT(DISTINCT outcome_row_id) FROM analytics.fact_outcome) AS fact_outcome_duplicate_grain;


/* M4. Referential integrity: fact keys with no dimension row (all must be 0) */
SELECT 'fact_crime.month_key' AS foreign_key,
       COUNT(*) FILTER (WHERE dm.month_key IS NULL) AS orphan_rows
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_month AS dm ON dm.month_key = f.month_key
UNION ALL
SELECT 'fact_crime.lsoa_key', COUNT(*) FILTER (WHERE d.lsoa_key IS NULL)
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_lsoa AS d ON d.lsoa_key = f.lsoa_key
UNION ALL
SELECT 'fact_crime.neighbourhood_key', COUNT(*) FILTER (WHERE d.neighbourhood_key IS NULL)
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_neighbourhood AS d ON d.neighbourhood_key = f.neighbourhood_key
UNION ALL
SELECT 'fact_crime.location_key', COUNT(*) FILTER (WHERE d.location_key IS NULL)
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_location AS d ON d.location_key = f.location_key
UNION ALL
SELECT 'fact_crime.category_key', COUNT(*) FILTER (WHERE d.category_key IS NULL)
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_crime_category AS d ON d.category_key = f.category_key
UNION ALL
SELECT 'fact_crime.outcome_status_key', COUNT(*) FILTER (WHERE d.outcome_status_key IS NULL)
FROM analytics.fact_crime AS f LEFT JOIN analytics.dim_outcome_status AS d ON d.outcome_status_key = f.outcome_status_key
UNION ALL
SELECT 'fact_outcome.outcome_month_key', COUNT(*) FILTER (WHERE dm.month_key IS NULL)
FROM analytics.fact_outcome AS f LEFT JOIN analytics.dim_month AS dm ON dm.month_key = f.outcome_month_key
UNION ALL
SELECT 'fact_outcome.crime_month_key', COUNT(*) FILTER (WHERE dm.month_key IS NULL)
FROM analytics.fact_outcome AS f LEFT JOIN analytics.dim_month AS dm ON dm.month_key = f.crime_month_key
UNION ALL
SELECT 'fact_outcome.outcome_status_key', COUNT(*) FILTER (WHERE d.outcome_status_key IS NULL)
FROM analytics.fact_outcome AS f LEFT JOIN analytics.dim_outcome_status AS d ON d.outcome_status_key = f.outcome_status_key;


/* M5. Use of the unknown (-1) members. Expected:
       location -1 = no-location crimes (25,583)
       neighbourhood -1 = 25,583
       lsoa -1 = 25,583 no-location + 16 unassigned = 25,599
       category -1 = 0, outcome status -1 = 0 */
SELECT
    COUNT(*) FILTER (WHERE location_key       = -1) AS location_unknown,
    COUNT(*) FILTER (WHERE neighbourhood_key  = -1) AS neighbourhood_unknown,
    COUNT(*) FILTER (WHERE lsoa_key           = -1) AS lsoa_unknown,
    COUNT(*) FILTER (WHERE category_key       = -1) AS category_unknown,
    COUNT(*) FILTER (WHERE outcome_status_key = -1) AS status_unknown
FROM analytics.fact_crime;


/* M6. Reconciliation of fact_crime to staging, by category group
       (must match L5 exactly; diff all 0) */
WITH staged AS (
    SELECT cfg.category_group, COUNT(*) AS staging_crimes
    FROM analytics.stg_crimes AS scr
    JOIN analytics.cfg_crime_category AS cfg ON cfg.category_code = scr.category_code
    WHERE NOT scr.is_duplicate
    GROUP BY cfg.category_group
),
modelled AS (
    SELECT dc.category_group, COUNT(*) AS fact_crimes
    FROM analytics.fact_crime AS f
    JOIN analytics.dim_crime_category AS dc ON dc.category_key = f.category_key
    GROUP BY dc.category_group
)
SELECT s.category_group, s.staging_crimes, m.fact_crimes, s.staging_crimes - COALESCE(m.fact_crimes, 0) AS diff
FROM staged AS s LEFT JOIN modelled AS m ON m.category_group = s.category_group
ORDER BY s.staging_crimes DESC;


/* M7. dim_month content check (36 rows): flags and labels */
SELECT month_key, month_label, month_index, financial_year, season_label,
       months_before_latest, is_last_12_months, is_prior_12_months, is_outcome_mature
FROM analytics.dim_month
ORDER BY month_key;


/* M8. Neighbourhood display names (DQ-21) and crimes per neighbourhood */
SELECT dn.neighbourhood_key, dn.neighbourhood_id, dn.published_name, dn.display_name, dn.district,
       COUNT(f.crime_id) AS crimes
FROM analytics.dim_neighbourhood AS dn
LEFT JOIN analytics.fact_crime   AS f ON f.neighbourhood_key = dn.neighbourhood_key
GROUP BY dn.neighbourhood_key, dn.neighbourhood_id, dn.published_name, dn.display_name, dn.district
ORDER BY dn.district, dn.display_name;
