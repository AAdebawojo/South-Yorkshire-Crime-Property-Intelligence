/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 1 - Batch 2: Source data profiling  (section 1.4)
   Run in DBeaver against: CrimeData (PostgreSQL 18)
   All queries are read-only.
   ===================================================================== */


/* ---------------------------------------------------------------------
   P1. Completeness of police.crimes, one row per column
       Empty strings are counted separately from NULLs, because the loader
       may store a missing text value as '' rather than NULL.
   --------------------------------------------------------------------- */
WITH crime_completeness AS (
    SELECT
        COUNT(*)                                                                 AS total_rows,
        COUNT(*) FILTER (WHERE crs.persistent_id IS NULL)                        AS persistent_id_null,
        COUNT(*) FILTER (WHERE crs.persistent_id IS NOT NULL
                           AND btrim(crs.persistent_id) = '')                    AS persistent_id_empty,
        COUNT(*) FILTER (WHERE crs.location_id IS NULL)                          AS location_id_null,
        COUNT(*) FILTER (WHERE crs.location_type IS NULL
                            OR btrim(crs.location_type) = '')                    AS location_type_missing,
        COUNT(*) FILTER (WHERE crs.location_subtype IS NULL
                            OR btrim(crs.location_subtype) = '')                 AS location_subtype_missing,
        COUNT(*) FILTER (WHERE crs.context IS NULL OR btrim(crs.context) = '')   AS context_missing,
        COUNT(*) FILTER (WHERE crs.latest_outcome IS NULL
                            OR btrim(crs.latest_outcome) = '')                   AS latest_outcome_missing,
        COUNT(*) FILTER (WHERE crs.latest_outcome_month IS NULL)                 AS latest_outcome_month_null
    FROM police.crimes AS crs
)
SELECT
    col.column_check,
    col.rows_affected,
    ROUND(100.0 * col.rows_affected / NULLIF(cc.total_rows, 0), 2) AS pct_of_crimes
FROM crime_completeness AS cc
CROSS JOIN LATERAL (VALUES
    ('persistent_id IS NULL',            cc.persistent_id_null),
    ('persistent_id = empty string',     cc.persistent_id_empty),
    ('location_id IS NULL',              cc.location_id_null),
    ('location_type missing',            cc.location_type_missing),
    ('location_subtype missing',         cc.location_subtype_missing),
    ('context missing',                  cc.context_missing),
    ('latest_outcome missing',           cc.latest_outcome_missing),
    ('latest_outcome_month IS NULL',     cc.latest_outcome_month_null)
) AS col(column_check, rows_affected)
ORDER BY col.rows_affected DESC;


/* ---------------------------------------------------------------------
   P2. Category profile: volume and gaps per crime category
       Tests whether the missing persistent_id / outcome rows are
       concentrated in particular categories (e.g. anti-social behaviour).
   --------------------------------------------------------------------- */
SELECT
    cat.category_code,
    cat.category_name,
    COUNT(crs.crime_id)                                                         AS crimes,
    ROUND(100.0 * COUNT(crs.crime_id) / NULLIF(SUM(COUNT(crs.crime_id)) OVER (), 0), 2)
                                                                                AS pct_of_all_crimes,
    COUNT(crs.crime_id) FILTER (WHERE COALESCE(btrim(crs.persistent_id), '') = '')
                                                                                AS no_persistent_id,
    COUNT(crs.crime_id) FILTER (WHERE crs.location_id IS NULL)                  AS no_location,
    COUNT(crs.crime_id) FILTER (WHERE COALESCE(btrim(crs.latest_outcome), '') = '')
                                                                                AS no_latest_outcome
FROM police.crime_categories AS cat
LEFT JOIN police.crimes      AS crs ON crs.category_code = cat.category_code
GROUP BY cat.category_code, cat.category_name
ORDER BY crimes DESC;


/* ---------------------------------------------------------------------
   P3. Outcome label consistency
       crimes.latest_outcome stores an outcome NAME as free text;
       outcome_categories stores CODE + NAME. This FULL JOIN shows every
       reference outcome, every distinct latest_outcome text, and whether
       the two line up. Rows with NULL on one side are label mismatches.
   --------------------------------------------------------------------- */
WITH reference_outcomes AS (
    SELECT
        ocat.outcome_code,
        ocat.outcome_name,
        COUNT(otc.outcome_row_id) AS outcome_rows
    FROM police.outcome_categories AS ocat
    LEFT JOIN police.outcomes      AS otc ON otc.outcome_code = ocat.outcome_code
    GROUP BY ocat.outcome_code, ocat.outcome_name
),
latest_outcome_labels AS (
    SELECT
        crs.latest_outcome,
        COUNT(*) AS crimes_with_label
    FROM police.crimes AS crs
    WHERE COALESCE(btrim(crs.latest_outcome), '') <> ''
    GROUP BY crs.latest_outcome
)
SELECT
    ref.outcome_code,
    ref.outcome_name                AS reference_outcome_name,
    ref.outcome_rows,
    lbl.latest_outcome              AS crimes_latest_outcome_text,
    lbl.crimes_with_label
FROM reference_outcomes          AS ref
FULL OUTER JOIN latest_outcome_labels AS lbl
       ON lower(btrim(lbl.latest_outcome)) = lower(btrim(ref.outcome_name))
ORDER BY COALESCE(lbl.crimes_with_label, 0) DESC, ref.outcome_rows DESC NULLS LAST;


/* ---------------------------------------------------------------------
   P4. Duplicate check: crimes that share a persistent_id
       (Q9 found 4 surplus rows). Shows every row involved, so we can tell
       whether they are the same incident re-issued under a new crime_id
       or genuinely different records.
   --------------------------------------------------------------------- */
WITH shared_persistent_ids AS (
    SELECT crs.persistent_id
    FROM police.crimes AS crs
    WHERE COALESCE(btrim(crs.persistent_id), '') <> ''
    GROUP BY crs.persistent_id
    HAVING COUNT(*) > 1
)
SELECT
    crs.persistent_id,
    crs.crime_id,
    crs.crime_month,
    crs.category_code,
    crs.location_id,
    crs.location_type,
    crs.latest_outcome,
    crs.latest_outcome_month,
    crs.loaded_at
FROM police.crimes          AS crs
JOIN shared_persistent_ids  AS spi ON spi.persistent_id = crs.persistent_id
ORDER BY crs.persistent_id, crs.crime_month, crs.crime_id;


/* ---------------------------------------------------------------------
   P5. Grain check for records WITHOUT a persistent_id
       Several anti-social behaviour reports at the same snapped point in
       the same month are expected (legitimate repeats, not duplicates).
       This sizes how often that happens.
   --------------------------------------------------------------------- */
WITH no_id_groups AS (
    SELECT
        crs.crime_month,
        crs.category_code,
        crs.location_id,
        COUNT(*) AS records_in_group
    FROM police.crimes AS crs
    WHERE COALESCE(btrim(crs.persistent_id), '') = ''
    GROUP BY crs.crime_month, crs.category_code, crs.location_id
)
SELECT
    CASE WHEN nig.records_in_group = 1 THEN '1'
         WHEN nig.records_in_group <= 3 THEN '2-3'
         WHEN nig.records_in_group <= 10 THEN '4-10'
         ELSE '11+' END                                  AS records_per_month_category_location,
    COUNT(*)                                             AS groups,
    SUM(nig.records_in_group)                            AS records
FROM no_id_groups AS nig
GROUP BY 1
ORDER BY MIN(nig.records_in_group);


/* ---------------------------------------------------------------------
   P6. Outcomes grain: how many outcome rows per crime (persistent_id)
       A crime commonly has a chain of outcomes (e.g. under investigation
       -> unable to prosecute). This sizes the one-to-many fan-out.
   --------------------------------------------------------------------- */
WITH outcomes_per_crime AS (
    SELECT
        otc.persistent_id,
        COUNT(*)                                      AS outcome_rows,
        COUNT(DISTINCT otc.outcome_code)              AS distinct_outcome_codes,
        COUNT(*) FILTER (WHERE otc.person_id IS NOT NULL) AS rows_with_person_id
    FROM police.outcomes AS otc
    GROUP BY otc.persistent_id
)
SELECT
    opc.outcome_rows                                        AS outcome_rows_per_crime,
    COUNT(*)                                                AS crimes,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS pct_of_crimes_with_outcomes,
    SUM(opc.rows_with_person_id)                            AS rows_with_person_id,
    COUNT(*) FILTER (WHERE opc.distinct_outcome_codes < opc.outcome_rows)
                                                            AS crimes_with_repeated_code
FROM outcomes_per_crime AS opc
GROUP BY opc.outcome_rows
ORDER BY opc.outcome_rows;


/* ---------------------------------------------------------------------
   P7. The outcome rows that match no crime (Q9 found 23)
   --------------------------------------------------------------------- */
SELECT
    otc.outcome_row_id,
    otc.persistent_id,
    otc.crime_id,
    otc.outcome_code,
    otc.outcome_month,
    otc.crime_category_code,
    otc.crime_month,
    otc.location_id,
    (SELECT COUNT(*) FROM police.crimes AS crs
      WHERE crs.crime_id = otc.crime_id)  AS crime_id_matches   -- does the API id match instead?
FROM police.outcomes AS otc
WHERE NOT EXISTS (
        SELECT 1
        FROM police.crimes AS crs
        WHERE crs.persistent_id = otc.persistent_id)
ORDER BY otc.outcome_month, otc.persistent_id;


/* ---------------------------------------------------------------------
   P8. Integrity and validity tests (implied relationships + dates)
       One row per test. failing_rows = 0 means the test passes.
       Enforced FKs are not retested: PostgreSQL already guarantees them.
   --------------------------------------------------------------------- */
SELECT test_id, test_description, failing_rows
FROM (
    SELECT 'IT-01' AS test_id, 'crimes.crime_month not in available_months' AS test_description,
           (SELECT COUNT(*) FROM police.crimes AS crs
             WHERE NOT EXISTS (SELECT 1 FROM police.available_months AS avm
                                WHERE avm.month = crs.crime_month)) AS failing_rows
    UNION ALL
    SELECT 'IT-02', 'crimes.crime_month not the first day of a month',
           (SELECT COUNT(*) FROM police.crimes WHERE EXTRACT(DAY FROM crime_month) <> 1)
    UNION ALL
    SELECT 'IT-03', 'crimes.latest_outcome_month earlier than crime_month',
           (SELECT COUNT(*) FROM police.crimes WHERE latest_outcome_month < crime_month)
    UNION ALL
    SELECT 'IT-04', 'crimes.latest_outcome present but latest_outcome_month missing (or vice versa)',
           (SELECT COUNT(*) FROM police.crimes
             WHERE (COALESCE(btrim(latest_outcome), '') = '') <> (latest_outcome_month IS NULL))
    UNION ALL
    SELECT 'IT-05', 'outcomes.outcome_month earlier than outcomes.crime_month',
           (SELECT COUNT(*) FROM police.outcomes WHERE outcome_month < crime_month)
    UNION ALL
    SELECT 'IT-06', 'outcomes.crime_category_code not in crime_categories',
           (SELECT COUNT(*) FROM police.outcomes AS otc
             WHERE otc.crime_category_code IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM police.crime_categories AS cat
                                WHERE cat.category_code = otc.crime_category_code))
    UNION ALL
    SELECT 'IT-07', 'outcomes whose crime_category / crime_month disagree with the matched crime',
           (SELECT COUNT(*) FROM police.outcomes AS otc
              JOIN police.crimes AS crs ON crs.persistent_id = otc.persistent_id
             WHERE crs.category_code IS DISTINCT FROM otc.crime_category_code
                OR crs.crime_month   IS DISTINCT FROM otc.crime_month)
    UNION ALL
    SELECT 'IT-08', 'outcomes natural key duplicates (persistent_id, code, month, person)',
           (SELECT COALESCE(SUM(n - 1), 0) FROM (
                SELECT COUNT(*) AS n FROM police.outcomes
                GROUP BY persistent_id, outcome_code, outcome_month, person_id
                HAVING COUNT(*) > 1) AS dup)
    UNION ALL
    SELECT 'IT-09', 'locations with no neighbourhood assigned',
           (SELECT COUNT(*) FROM police.locations WHERE neighbourhood_id IS NULL)
    UNION ALL
    SELECT 'IT-10', 'locations used by neither crimes nor outcomes',
           (SELECT COUNT(*) FROM police.locations AS loc
             WHERE NOT EXISTS (SELECT 1 FROM police.crimes   AS crs WHERE crs.location_id = loc.location_id)
               AND NOT EXISTS (SELECT 1 FROM police.outcomes AS otc WHERE otc.location_id = loc.location_id))
    UNION ALL
    SELECT 'IT-11', 'location_id present but location_type missing',
           (SELECT COUNT(*) FROM police.crimes
             WHERE location_id IS NOT NULL AND COALESCE(btrim(location_type), '') = '')
    UNION ALL
    SELECT 'IT-12', 'crime_categories never used by any crime',
           (SELECT COUNT(*) FROM police.crime_categories AS cat
             WHERE NOT EXISTS (SELECT 1 FROM police.crimes AS crs WHERE crs.category_code = cat.category_code))
) AS tests
ORDER BY test_id;


/* ---------------------------------------------------------------------
   P9. Geospatial validation of police.locations
       The "expected area" envelope is derived from the neighbourhood
       boundary vertices themselves, not a hard-coded box.
   --------------------------------------------------------------------- */
WITH boundary_envelope AS (
    SELECT
        MIN(nbp.latitude)  AS min_lat, MAX(nbp.latitude)  AS max_lat,
        MIN(nbp.longitude) AS min_lng, MAX(nbp.longitude) AS max_lng
    FROM police.neighbourhood_boundary_points AS nbp
),
duplicate_points AS (
    SELECT loc.latitude, loc.longitude
    FROM police.locations AS loc
    GROUP BY loc.latitude, loc.longitude
    HAVING COUNT(*) > 1
)
SELECT
    (SELECT COUNT(*) FROM police.locations)                                         AS location_points,
    MIN(loc.latitude)  AS min_lat,  MAX(loc.latitude)  AS max_lat,
    MIN(loc.longitude) AS min_lng,  MAX(loc.longitude) AS max_lng,
    env.min_lat AS env_min_lat, env.max_lat AS env_max_lat,
    env.min_lng AS env_min_lng, env.max_lng AS env_max_lng,
    COUNT(*) FILTER (WHERE loc.latitude  NOT BETWEEN -90  AND 90
                        OR loc.longitude NOT BETWEEN -180 AND 180)                  AS outside_global_range,
    COUNT(*) FILTER (WHERE loc.latitude = 0 AND loc.longitude = 0)                  AS null_island_points,
    COUNT(*) FILTER (WHERE loc.latitude  NOT BETWEEN env.min_lat AND env.max_lat
                        OR loc.longitude NOT BETWEEN env.min_lng AND env.max_lng)   AS outside_boundary_envelope,
    (SELECT COUNT(*) FROM duplicate_points)                                         AS coordinate_pairs_shared_by_2plus_ids,
    COUNT(*) FILTER (WHERE COALESCE(btrim(loc.street_name), '') = '')               AS missing_street_name,
    COUNT(*) FILTER (WHERE loc.street_name NOT ILIKE 'On or near%')                 AS street_name_unusual_pattern
FROM police.locations AS loc
CROSS JOIN boundary_envelope AS env
GROUP BY env.min_lat, env.max_lat, env.min_lng, env.max_lng;


/* ---------------------------------------------------------------------
   P10. Neighbourhood profile (expect 18 rows)
        Checks names, population (a candidate rate denominator), centre,
        boundary geometry and how much activity each neighbourhood holds.
   --------------------------------------------------------------------- */
WITH boundary_stats AS (
    SELECT
        nbp.neighbourhood_id,
        COUNT(*)                                            AS boundary_points,
        BOOL_AND(TRUE)                                      AS has_points,
        (ARRAY_AGG(nbp.latitude  ORDER BY nbp.point_order))[1]                     AS first_lat,
        (ARRAY_AGG(nbp.longitude ORDER BY nbp.point_order))[1]                     AS first_lng,
        (ARRAY_AGG(nbp.latitude  ORDER BY nbp.point_order DESC))[1]                AS last_lat,
        (ARRAY_AGG(nbp.longitude ORDER BY nbp.point_order DESC))[1]                AS last_lng,
        MAX(nbp.point_order) - MIN(nbp.point_order) + 1 - COUNT(*)                 AS point_order_gaps
    FROM police.neighbourhood_boundary_points AS nbp
    GROUP BY nbp.neighbourhood_id
),
activity AS (
    SELECT
        loc.neighbourhood_id,
        COUNT(DISTINCT loc.location_id) AS location_points,
        COUNT(crs.crime_id)             AS crimes
    FROM police.locations    AS loc
    LEFT JOIN police.crimes  AS crs ON crs.location_id = loc.location_id
    GROUP BY loc.neighbourhood_id
)
SELECT
    nbh.neighbourhood_id,
    nbh.neighbourhood_name,
    COUNT(*) OVER (PARTITION BY lower(btrim(nbh.neighbourhood_name)))  AS name_occurrences,
    nbh.population,
    nbh.centre_latitude,
    nbh.centre_longitude,
    split_part(nbh.boundary_wkt, ' ', 1)                               AS wkt_geometry_type,
    bst.boundary_points,
    (bst.first_lat = bst.last_lat AND bst.first_lng = bst.last_lng)   AS ring_closed_in_source,
    bst.point_order_gaps,
    act.location_points,
    act.crimes
FROM police.neighbourhoods  AS nbh
LEFT JOIN boundary_stats    AS bst ON bst.neighbourhood_id = nbh.neighbourhood_id
LEFT JOIN activity          AS act ON act.neighbourhood_id = nbh.neighbourhood_id
ORDER BY act.crimes DESC NULLS LAST;


/* ---------------------------------------------------------------------
   P11. Location type and subtype distribution
        'BTP' = British Transport Police (railway locations).
   --------------------------------------------------------------------- */
SELECT
    COALESCE(crs.location_type, '(no location)')              AS location_type,
    COALESCE(NULLIF(btrim(crs.location_subtype), ''), '(blank)') AS location_subtype,
    COUNT(*)                                                  AS crimes
FROM police.crimes AS crs
GROUP BY 1, 2
ORDER BY crimes DESC;
