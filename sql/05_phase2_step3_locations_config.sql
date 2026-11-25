/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 2 - Step 3: location staging + configuration tables
   Run in DBeaver against: CrimeData
   Part A: LSOA fallback for unmatched points + analytics.stg_locations
   Part B: analytics.cfg_crime_category   (editable mapping table)
   Part C: analytics.cfg_outcome_status   (editable mapping table)
   Part D: validation (read-only)

   Re-running is safe. The config tables use INSERT ... ON CONFLICT DO
   NOTHING, so any edits you make to them later are kept.
   ===================================================================== */


/* =====================================================================
   PART A - LOCATIONS
   ===================================================================== */

/* ---------------------------------------------------------------------
   A1. analytics.xref_location_lsoa_fallback   (T-105, DQ-19)
   For the points with no exact CSV match (26 BTP stations + 8 street
   points), take the LSOA of the NEAREST exactly-matched point.
   Distance: equirectangular approximation in metres (accurate to well
   under 1% at these distances; no PostGIS needed).
   Only the unmatched points are processed (34 x ~18,300 comparisons).
   To rebuild after reloading data:
       REFRESH MATERIALIZED VIEW analytics.xref_location_lsoa;
       REFRESH MATERIALIZED VIEW analytics.xref_location_lsoa_fallback;
   --------------------------------------------------------------------- */
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.xref_location_lsoa_fallback AS
WITH unmatched_points AS (
    SELECT loc.location_id,
           loc.latitude::float8  AS lat,
           loc.longitude::float8 AS lng
    FROM analytics.xref_location_lsoa AS xr
    JOIN police.locations             AS loc ON loc.location_id = xr.location_id
    WHERE xr.match_status = 'unmatched'
),
matched_points AS (
    SELECT xr.location_id,
           xr.lsoa_code,
           xr.lsoa_name,
           xr.lsoa_local_authority,
           loc.latitude::float8  AS lat,
           loc.longitude::float8 AS lng
    FROM analytics.xref_location_lsoa AS xr
    JOIN police.locations             AS loc ON loc.location_id = xr.location_id
    WHERE xr.match_status <> 'unmatched'
)
SELECT
    up.location_id,
    nn.location_id                    AS donor_location_id,
    nn.lsoa_code,
    nn.lsoa_name,
    nn.lsoa_local_authority,
    ROUND(nn.distance_m::numeric, 1)  AS distance_m
FROM unmatched_points AS up
CROSS JOIN LATERAL (
    SELECT
        mp.location_id, mp.lsoa_code, mp.lsoa_name, mp.lsoa_local_authority,
        6371000 * sqrt(
              power(radians(mp.lat - up.lat), 2)
            + power(radians(mp.lng - up.lng) * cos(radians((mp.lat + up.lat) / 2)), 2)
        ) AS distance_m
    FROM matched_points AS mp
    ORDER BY distance_m
    LIMIT 1
) AS nn;

CREATE UNIQUE INDEX IF NOT EXISTS ux_xref_lsoa_fallback ON analytics.xref_location_lsoa_fallback (location_id);

COMMENT ON MATERIALIZED VIEW analytics.xref_location_lsoa_fallback IS
  'T-105: nearest exactly-matched point supplies the LSOA for points with no CSV match (DQ-19).';


/* ---------------------------------------------------------------------
   A2. analytics.stg_locations   (T-106)
   Grain : one row per police.locations row (18,309).
   Adds  : neighbourhood name, district, LSOA (exact or fallback),
           match method, station flag, South Yorkshire LSOA flag (DQ-20).
   Rule  : fallback is used only within 500 m; beyond that -> 'unassigned'.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW analytics.stg_locations AS
WITH lsoa_choice AS (
    SELECT
        xr.location_id,
        CASE
            WHEN xr.match_status = 'matched'            THEN 'exact_coordinate'
            WHEN xr.match_status = 'matched_ambiguous'  THEN 'exact_coordinate_ambiguous'
            WHEN fb.distance_m <= 500                   THEN 'nearest_point_fallback'
            ELSE                                             'unassigned'
        END                                                           AS lsoa_match_method,
        CASE WHEN xr.match_status <> 'unmatched' THEN xr.lsoa_code
             WHEN fb.distance_m <= 500           THEN fb.lsoa_code END            AS lsoa_code,
        CASE WHEN xr.match_status <> 'unmatched' THEN xr.lsoa_name
             WHEN fb.distance_m <= 500           THEN fb.lsoa_name END            AS lsoa_name,
        CASE WHEN xr.match_status <> 'unmatched' THEN xr.lsoa_local_authority
             WHEN fb.distance_m <= 500           THEN fb.lsoa_local_authority END AS lsoa_local_authority,
        fb.distance_m                                                 AS fallback_distance_m
    FROM analytics.xref_location_lsoa               AS xr
    LEFT JOIN analytics.xref_location_lsoa_fallback AS fb ON fb.location_id = xr.location_id
)
SELECT
    loc.location_id,
    loc.street_name,
    loc.latitude,
    loc.longitude,
    (loc.street_name ILIKE '%(station)%')                       AS is_station_point,
    loc.neighbourhood_id,
    nbh.neighbourhood_name,
    split_part(nbh.neighbourhood_name, ' ', 1)                  AS neighbourhood_district,
    lc.lsoa_code,
    lc.lsoa_name,
    lc.lsoa_local_authority,
    COALESCE(lc.lsoa_local_authority IN ('Barnsley', 'Doncaster', 'Rotherham', 'Sheffield'), FALSE)
                                                                AS is_south_yorkshire_lsoa,
    lc.lsoa_match_method,
    lc.fallback_distance_m
FROM police.locations           AS loc
JOIN lsoa_choice                AS lc  ON lc.location_id      = loc.location_id
LEFT JOIN police.neighbourhoods AS nbh ON nbh.neighbourhood_id = loc.neighbourhood_id;

COMMENT ON VIEW analytics.stg_locations IS
  'T-106: location + neighbourhood + district + LSOA (exact, or nearest-point fallback within 500 m).';


/* =====================================================================
   PART B - CRIME CATEGORY CONFIGURATION   (T-107, DQ-04, brief 2.4)
   One row per police category, including the two excluded ones, so the
   mapping is complete and auditable. Edit category_group or
   include_in_analysis here; every downstream object reads this table.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS analytics.cfg_crime_category (
    category_code        VARCHAR(60)  PRIMARY KEY,
    category_name        VARCHAR(200) NOT NULL,
    category_group       VARCHAR(100) NOT NULL,
    group_sort_order     SMALLINT     NOT NULL,
    include_in_analysis  BOOLEAN      NOT NULL,
    mapping_note         TEXT
);

INSERT INTO analytics.cfg_crime_category
    (category_code, category_name, category_group, group_sort_order, include_in_analysis, mapping_note)
VALUES
    ('violent-crime',         'Violence and sexual offences', 'Violence and sexual offences', 1,  TRUE,  'Police category; kept as its own group.'),
    ('robbery',               'Robbery',                      'Robbery',                      2,  TRUE,  'Kept separate from theft: involves force or threat.'),
    ('burglary',              'Burglary',                     'Burglary',                     3,  TRUE,  'Kept separate: key concern for home owners.'),
    ('vehicle-crime',         'Vehicle crime',                'Vehicle crime',                4,  TRUE,  NULL),
    ('criminal-damage-arson', 'Criminal damage and arson',    'Criminal damage and arson',    5,  TRUE,  NULL),
    ('shoplifting',           'Shoplifting',                  'Theft',                        6,  TRUE,  'Grouped into Theft. Note: driven by retail footfall, not residents.'),
    ('other-theft',           'Other theft',                  'Theft',                        6,  TRUE,  'Grouped into Theft.'),
    ('theft-from-the-person', 'Theft from the person',        'Theft',                        6,  TRUE,  'Grouped into Theft.'),
    ('bicycle-theft',         'Bicycle theft',                'Theft',                        6,  TRUE,  'Grouped into Theft.'),
    ('public-order',          'Public order',                 'Public order offences',        7,  TRUE,  NULL),
    ('drugs',                 'Drugs',                        'Drug offences',                8,  TRUE,  NULL),
    ('possession-of-weapons', 'Possession of weapons',        'Possession of weapons',        9,  TRUE,  'Not in the brief''s example list; kept separate as a distinct police category relevant to personal safety.'),
    ('other-crime',           'Other crime',                  'Other crime',                  10, TRUE,  NULL),
    ('anti-social-behaviour', 'Anti-social behaviour',        'Anti-social behaviour',        11, TRUE,  'Recorded incidents, not notifiable crimes; no outcomes by design.'),
    ('all-crime',             'All crime',                    '(excluded)',                   99, FALSE, 'API aggregate, not a real category (DQ-04). Never used by a crime.'),
    ('',                      '(blank)',                      '(excluded)',                   99, FALSE, 'Loader artefact T-007 (DQ-04). Never used by a crime.')
ON CONFLICT (category_code) DO NOTHING;

COMMENT ON TABLE analytics.cfg_crime_category IS
  'T-107: configurable analytical grouping of police crime categories. Edit to regroup; downstream objects follow.';


/* =====================================================================
   PART C - OUTCOME STATUS CONFIGURATION   (T-108, DQ-09)
   One row per status a crime can carry (13 reference outcomes + 2
   status-only labels + 2 derived labels). outcome_stage is factual
   (is the case still open?). The positive / negative classification
   for KPIs is deliberately NOT set here; it is defined in Phase 5.
   Names are taken from police.outcome_categories so they match exactly.
   ===================================================================== */
CREATE TABLE IF NOT EXISTS analytics.cfg_outcome_status (
    outcome_status_name   VARCHAR(255) PRIMARY KEY,   -- matches stg_crimes.latest_outcome_status / stg_outcomes.outcome_name
    outcome_code          VARCHAR(80),                -- NULL for status-only / derived labels
    status_source         VARCHAR(30)  NOT NULL,      -- 'reference outcome' | 'status-only label' | 'derived'
    outcome_stage         VARCHAR(20)  NOT NULL,      -- 'Concluded' | 'Pending' | 'Unknown' | 'Not applicable'
    outcome_group         VARCHAR(40),                -- set in Phase 5 (e.g. positive / no further action)
    stage_note            TEXT
);

INSERT INTO analytics.cfg_outcome_status
    (outcome_status_name, outcome_code, status_source, outcome_stage, stage_note)
SELECT
    ocat.outcome_name,
    ocat.outcome_code,
    'reference outcome',
    CASE ocat.outcome_code
        WHEN 'awaiting-court-result'  THEN 'Pending'
        WHEN 'court-result-unavailable' THEN 'Unknown'
        ELSE 'Concluded'
    END,
    CASE ocat.outcome_code
        WHEN 'awaiting-court-result'    THEN 'Case is with the courts; result not yet known.'
        WHEN 'court-result-unavailable' THEN 'Went to court but the result was not supplied.'
        ELSE NULL
    END
FROM police.outcome_categories AS ocat
ON CONFLICT (outcome_status_name) DO NOTHING;

INSERT INTO analytics.cfg_outcome_status
    (outcome_status_name, outcome_code, status_source, outcome_stage, stage_note)
VALUES
    ('Under investigation',       NULL, 'status-only label', 'Pending',        'Latest status only; no outcome event is published for it.'),
    ('Status update unavailable', NULL, 'status-only label', 'Unknown',        'Latest status only; police did not supply a status.'),
    ('Not applicable (ASB)',      NULL, 'derived',           'Not applicable', 'Anti-social behaviour has no outcomes by design (T-102).'),
    ('No outcome recorded',       NULL, 'derived',           'Unknown',        'Safety net for a non-ASB crime with a blank status (expected count: 0).')
ON CONFLICT (outcome_status_name) DO NOTHING;

COMMENT ON TABLE analytics.cfg_outcome_status IS
  'T-108: every outcome status a crime can carry, with a factual stage. outcome_group is defined in Phase 5.';


/* =====================================================================
   PART D - VALIDATION (read-only)
   ===================================================================== */

/* ---------------------------------------------------------------------
   L1. stg_locations: row count, match method, fallback distance, crimes.
       Expect 18,309 points; 'unassigned' = 0 if every fallback is < 500 m.
   --------------------------------------------------------------------- */
SELECT
    sl.lsoa_match_method,
    COUNT(*)                                         AS location_points,
    COUNT(*) FILTER (WHERE sl.is_station_point)      AS station_points,
    MAX(sl.fallback_distance_m)                      AS max_fallback_distance_m,
    SUM(crime_counts.crimes)                         AS crimes
FROM analytics.stg_locations AS sl
LEFT JOIN (
    SELECT location_id, COUNT(*) AS crimes
    FROM analytics.stg_crimes
    WHERE NOT is_duplicate AND location_id IS NOT NULL
    GROUP BY location_id
) AS crime_counts ON crime_counts.location_id = sl.location_id
GROUP BY sl.lsoa_match_method
ORDER BY location_points DESC;


/* ---------------------------------------------------------------------
   L2. The fallback assignments, one row each (expect 34 rows).
       Check the distances look sensible (stations sit near streets).
   --------------------------------------------------------------------- */
SELECT
    sl.street_name,
    sl.neighbourhood_name,
    sl.lsoa_name,
    sl.fallback_distance_m,
    sl.lsoa_match_method
FROM analytics.stg_locations AS sl
WHERE sl.lsoa_match_method IN ('nearest_point_fallback', 'unassigned')
ORDER BY sl.fallback_distance_m DESC;


/* ---------------------------------------------------------------------
   L3. South Yorkshire LSOA flag (DQ-20). Expect a handful of points
       outside the county and ~860 South Yorkshire LSOAs.
   --------------------------------------------------------------------- */
SELECT
    sl.is_south_yorkshire_lsoa,
    COUNT(*)                         AS location_points,
    COUNT(DISTINCT sl.lsoa_code)     AS distinct_lsoas,
    string_agg(DISTINCT CASE WHEN NOT sl.is_south_yorkshire_lsoa THEN sl.lsoa_local_authority END, ', ')
                                     AS out_of_county_areas
FROM analytics.stg_locations AS sl
GROUP BY sl.is_south_yorkshire_lsoa;


/* ---------------------------------------------------------------------
   L4. Category configuration coverage. All three counts must be 0.
   --------------------------------------------------------------------- */
SELECT
    (SELECT COUNT(*) FROM police.crime_categories AS pc
      WHERE NOT EXISTS (SELECT 1 FROM analytics.cfg_crime_category AS cfg
                         WHERE cfg.category_code = pc.category_code))         AS police_categories_missing_from_cfg,
    (SELECT COUNT(*) FROM analytics.stg_crimes AS scr
      WHERE NOT EXISTS (SELECT 1 FROM analytics.cfg_crime_category AS cfg
                         WHERE cfg.category_code = scr.category_code))        AS crimes_with_unmapped_category,
    (SELECT COUNT(*) FROM analytics.stg_crimes AS scr
       JOIN analytics.cfg_crime_category AS cfg ON cfg.category_code = scr.category_code
      WHERE NOT cfg.include_in_analysis)                                      AS crimes_in_excluded_categories;


/* ---------------------------------------------------------------------
   L5. Crimes by analytical group (de-duplicated). Totals must reconcile
       to 527,597 (= 527,601 - 4 duplicates).
   --------------------------------------------------------------------- */
SELECT
    cfg.group_sort_order,
    cfg.category_group,
    string_agg(DISTINCT cfg.category_name, ', ')                       AS police_categories,
    COUNT(scr.crime_id)                                                AS crimes,
    ROUND(100.0 * COUNT(scr.crime_id) / NULLIF(SUM(COUNT(scr.crime_id)) OVER (), 0), 2)
                                                                       AS pct
FROM analytics.cfg_crime_category AS cfg
JOIN analytics.stg_crimes         AS scr ON scr.category_code = cfg.category_code
WHERE NOT scr.is_duplicate
  AND cfg.include_in_analysis
GROUP BY cfg.group_sort_order, cfg.category_group
ORDER BY cfg.group_sort_order;


/* ---------------------------------------------------------------------
   L6. Outcome status configuration coverage + crimes by stage.
       The two "missing" counts must be 0.
   --------------------------------------------------------------------- */
SELECT
    (SELECT COUNT(DISTINCT scr.latest_outcome_status) FROM analytics.stg_crimes AS scr
      WHERE NOT EXISTS (SELECT 1 FROM analytics.cfg_outcome_status AS cfg
                         WHERE cfg.outcome_status_name = scr.latest_outcome_status))  AS crime_statuses_missing_from_cfg,
    (SELECT COUNT(DISTINCT sto.outcome_name) FROM analytics.stg_outcomes AS sto
      WHERE NOT EXISTS (SELECT 1 FROM analytics.cfg_outcome_status AS cfg
                         WHERE cfg.outcome_status_name = sto.outcome_name))           AS outcome_names_missing_from_cfg;

SELECT
    cfg.outcome_stage,
    cfg.outcome_status_name,
    cfg.status_source,
    COUNT(scr.crime_id)                                                AS crimes
FROM analytics.cfg_outcome_status AS cfg
LEFT JOIN analytics.stg_crimes    AS scr
       ON  scr.latest_outcome_status = cfg.outcome_status_name
       AND NOT scr.is_duplicate
GROUP BY cfg.outcome_stage, cfg.outcome_status_name, cfg.status_source
ORDER BY cfg.outcome_stage, crimes DESC;
