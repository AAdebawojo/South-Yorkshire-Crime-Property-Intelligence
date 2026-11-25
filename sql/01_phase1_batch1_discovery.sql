/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 1 - Batch 1: Database discovery
   Run in DBeaver against: CrimeData (PostgreSQL)
   Read-only: no query here changes any data. Q0 only refreshes the
   planner's statistics so the row estimates in Q4 are accurate.
   ===================================================================== */


/* ---------------------------------------------------------------------
   Q0. Refresh planner statistics (safe; makes Q4 estimates accurate)
   --------------------------------------------------------------------- */
ANALYZE;


/* ---------------------------------------------------------------------
   Q1. Tables, views and column definitions in the police schema
   --------------------------------------------------------------------- */
SELECT
    tbl.table_type,
    col.table_name,
    col.ordinal_position,
    col.column_name,
    col.data_type,
    col.character_maximum_length,
    col.numeric_precision,
    col.numeric_scale,
    col.is_nullable,
    col.column_default
FROM information_schema.columns AS col
JOIN information_schema.tables  AS tbl
      ON  tbl.table_schema = col.table_schema
      AND tbl.table_name   = col.table_name
WHERE col.table_schema = 'police'
ORDER BY tbl.table_type, col.table_name, col.ordinal_position;


/* ---------------------------------------------------------------------
   Q2. Primary key, foreign key, unique and check constraints
       (definition column shows referenced table and ON DELETE rules)
   --------------------------------------------------------------------- */
SELECT
    con.conrelid::regclass                      AS table_name,
    CASE con.contype
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'f' THEN 'FOREIGN KEY'
        WHEN 'u' THEN 'UNIQUE'
        WHEN 'c' THEN 'CHECK'
        ELSE con.contype::text
    END                                         AS constraint_type,
    con.conname                                 AS constraint_name,
    pg_get_constraintdef(con.oid)               AS definition
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_namespace  AS nsp ON nsp.oid = con.connamespace
WHERE nsp.nspname = 'police'
ORDER BY con.conrelid::regclass::text, constraint_type, constraint_name;


/* ---------------------------------------------------------------------
   Q3. Indexes (includes unique indexes that are not constraints)
   --------------------------------------------------------------------- */
SELECT
    idx.tablename                                                   AS table_name,
    idx.indexname                                                   AS index_name,
    pg_size_pretty(pg_relation_size(
        format('%I.%I', idx.schemaname, idx.indexname)::regclass))  AS index_size,
    idx.indexdef                                                    AS index_definition
FROM pg_catalog.pg_indexes AS idx
WHERE idx.schemaname = 'police'
ORDER BY idx.tablename, idx.indexname;


/* ---------------------------------------------------------------------
   Q4. Storage and ESTIMATED row counts (fast, from catalog statistics)
   --------------------------------------------------------------------- */
SELECT
    cls.relname                                         AS table_name,
    cls.reltuples::bigint                               AS estimated_rows,
    pg_size_pretty(pg_table_size(cls.oid))              AS table_size,
    pg_size_pretty(pg_indexes_size(cls.oid))            AS indexes_size,
    pg_size_pretty(pg_total_relation_size(cls.oid))     AS total_size
FROM pg_catalog.pg_class     AS cls
JOIN pg_catalog.pg_namespace AS nsp ON nsp.oid = cls.relnamespace
WHERE nsp.nspname = 'police'
  AND cls.relkind = 'r'
ORDER BY pg_total_relation_size(cls.oid) DESC;


/* ---------------------------------------------------------------------
   Q5. EXACT row counts per table
   --------------------------------------------------------------------- */
SELECT 'available_months'              AS table_name, COUNT(*) AS exact_rows FROM police.available_months
UNION ALL SELECT 'crime_categories',              COUNT(*) FROM police.crime_categories
UNION ALL SELECT 'crimes',                        COUNT(*) FROM police.crimes
UNION ALL SELECT 'forces',                        COUNT(*) FROM police.forces
UNION ALL SELECT 'load_log',                      COUNT(*) FROM police.load_log
UNION ALL SELECT 'load_runs',                     COUNT(*) FROM police.load_runs
UNION ALL SELECT 'locations',                     COUNT(*) FROM police.locations
UNION ALL SELECT 'neighbourhood_boundary_points', COUNT(*) FROM police.neighbourhood_boundary_points
UNION ALL SELECT 'neighbourhoods',                COUNT(*) FROM police.neighbourhoods
UNION ALL SELECT 'outcome_categories',            COUNT(*) FROM police.outcome_categories
UNION ALL SELECT 'outcomes',                      COUNT(*) FROM police.outcomes
ORDER BY table_name;


/* ---------------------------------------------------------------------
   Q6. Reporting period coverage
       months_expected = calendar months between first and last crime month;
       if months_present < months_expected there are gap months.
   --------------------------------------------------------------------- */
WITH crime_coverage AS (
    SELECT
        MIN(crs.crime_month)            AS first_crime_month,
        MAX(crs.crime_month)            AS last_crime_month,
        COUNT(DISTINCT crs.crime_month) AS crime_months_present
    FROM police.crimes AS crs
),
api_coverage AS (
    SELECT
        MIN(avm.month)  AS first_available_month,
        MAX(avm.month)  AS last_available_month,
        COUNT(*)        AS available_months
    FROM police.available_months AS avm
),
outcome_coverage AS (
    SELECT
        MIN(otc.outcome_month)  AS first_outcome_month,
        MAX(otc.outcome_month)  AS last_outcome_month,
        MIN(otc.crime_month)    AS earliest_crime_month_in_outcomes
    FROM police.outcomes AS otc
)
SELECT
    cc.first_crime_month,
    cc.last_crime_month,
    cc.crime_months_present,
    ( (EXTRACT(YEAR  FROM cc.last_crime_month) - EXTRACT(YEAR  FROM cc.first_crime_month)) * 12
    +  EXTRACT(MONTH FROM cc.last_crime_month) - EXTRACT(MONTH FROM cc.first_crime_month) + 1
    )::int                                AS crime_months_expected,
    ac.first_available_month,
    ac.last_available_month,
    ac.available_months,
    oc.first_outcome_month,
    oc.last_outcome_month,
    oc.earliest_crime_month_in_outcomes
FROM crime_coverage   AS cc
CROSS JOIN api_coverage     AS ac
CROSS JOIN outcome_coverage AS oc;


/* ---------------------------------------------------------------------
   Q7. Monthly crime volume, located vs. no-location
       generate_series exposes any calendar month with zero rows.
   --------------------------------------------------------------------- */
WITH month_spine AS (
    SELECT gs.month_start::date AS month_start
    FROM generate_series(
            (SELECT MIN(crime_month) FROM police.crimes),
            (SELECT MAX(crime_month) FROM police.crimes),
            INTERVAL '1 month') AS gs(month_start)
)
SELECT
    ms.month_start                                          AS crime_month,
    COUNT(crs.crime_id)                                     AS total_crimes,
    COUNT(crs.location_id)                                  AS crimes_with_location,
    COUNT(crs.crime_id) FILTER (WHERE crs.location_id IS NULL) AS crimes_without_location
FROM month_spine AS ms
LEFT JOIN police.crimes AS crs
       ON crs.crime_month = ms.month_start
GROUP BY ms.month_start
ORDER BY ms.month_start;


/* ---------------------------------------------------------------------
   Q8. Distinct counts of the main entities: reference table vs. usage
   --------------------------------------------------------------------- */
SELECT
    (SELECT COUNT(*)                        FROM police.forces)             AS forces_in_reference,
    (SELECT COUNT(DISTINCT force_id)        FROM police.crimes)             AS forces_used_by_crimes,
    (SELECT COUNT(*)                        FROM police.neighbourhoods)     AS neighbourhoods_in_reference,
    (SELECT COUNT(DISTINCT neighbourhood_id) FROM police.locations)         AS neighbourhoods_used_by_locations,
    (SELECT COUNT(*)                        FROM police.crime_categories)   AS crime_categories_in_reference,
    (SELECT COUNT(DISTINCT category_code)   FROM police.crimes)             AS crime_categories_used,
    (SELECT COUNT(*)                        FROM police.outcome_categories) AS outcome_categories_in_reference,
    (SELECT COUNT(DISTINCT outcome_code)    FROM police.outcomes)           AS outcome_categories_used,
    (SELECT COUNT(*)                        FROM police.locations)          AS distinct_location_points;


/* ---------------------------------------------------------------------
   Q9. Implied (non-enforced) relationship: outcomes -> crimes
       outcomes has no FK to crimes; the candidate join key is persistent_id.
       This measures how well that key actually links the two tables.
   --------------------------------------------------------------------- */
SELECT
    COUNT(*)                                                    AS outcome_rows,
    COUNT(*) FILTER (WHERE crs_match.persistent_id IS NOT NULL) AS outcomes_matching_a_crime,
    ROUND(100.0 * COUNT(*) FILTER (WHERE crs_match.persistent_id IS NOT NULL)
          / NULLIF(COUNT(*), 0), 2)                             AS pct_outcomes_matched,
    (SELECT COUNT(*) FROM police.crimes
      WHERE persistent_id IS NULL OR persistent_id = '')        AS crimes_without_persistent_id,
    (SELECT COUNT(*) - COUNT(DISTINCT persistent_id) FROM police.crimes
      WHERE persistent_id <> '')                                AS crimes_sharing_a_persistent_id
FROM police.outcomes AS otc
LEFT JOIN (SELECT DISTINCT persistent_id
             FROM police.crimes
            WHERE persistent_id <> '') AS crs_match
       ON crs_match.persistent_id = otc.persistent_id;


/* ---------------------------------------------------------------------
   Q10. Environment: PostgreSQL version and PostGIS availability
        (decides how we build neighbourhood polygons in Phases 2 and 9)
   --------------------------------------------------------------------- */
SELECT version() AS postgres_version;

SELECT
    ext.name,
    ext.default_version   AS available_version,
    ext.installed_version
FROM pg_catalog.pg_available_extensions AS ext
WHERE ext.name IN ('postgis', 'postgis_topology');
