/* =====================================================================
   PHASE 5 - STEP 1 : SEVERITY WEIGHTS, OUTCOME GROUPS, KPI BASELINE
   Database : CrimeData   (run in DBeaver, connected as the owner)

   Part A : analytics.cfg_crime_severity_weight   (editable, T-212, D-13)
   Part B : outcome groups in analytics.cfg_outcome_status  (T-213, D-14)
   Part C : sync the dimensions + extend pbi.dim_crime_category /
            pbi.dim_outcome_status (new columns are appended at the end)
   Part D : validation  S1-S8  (read-only; these figures are the baseline
            the Power BI measures must reproduce)

   Re-running is safe. Config rows use ON CONFLICT DO NOTHING and the
   outcome-group UPDATE only fills rows that are still NULL, so your
   edits are kept. To re-derive the weights, run
   derive_severity_weights.py and edit Part A.
   ===================================================================== */


/* =====================================================================
   PART A - CRIME SEVERITY WEIGHTS
   weight = offence-volume-weighted mean of ONS Crime Severity Score
   weights (equivalent days of custody) over the Home Office offence
   codes in each police.uk category, using South Yorkshire offence
   counts for 2023/24 Q3 - 2026/27 Q1 (the crime window).
   ASB has no row: it is not a notifiable crime and has no ONS weight;
   it is a separate Safety Index component (D-13).
   ===================================================================== */
CREATE TABLE IF NOT EXISTS analytics.cfg_crime_severity_weight (
    category_code         VARCHAR(60)   PRIMARY KEY
                          REFERENCES analytics.cfg_crime_category (category_code),
    severity_weight       NUMERIC(10,2) NOT NULL CHECK (severity_weight > 0),
    sy_offences_in_window INT,
    weight_source         TEXT          NOT NULL,
    weight_method         TEXT          NOT NULL,
    window_label          VARCHAR(40),
    note                  TEXT
);

INSERT INTO analytics.cfg_crime_severity_weight
    (category_code, severity_weight, sy_offences_in_window, weight_source, weight_method, window_label, note)
SELECT v.category_code, v.severity_weight, v.sy_offences,
       'ONS Crime Severity Score weights (year ending Mar 2025 release); Home Office PFA recorded crime open data (South Yorkshire)',
       'Volume-weighted mean of ONS offence weights over HO offence codes mapped to the police.uk category (derive_severity_weights.py)',
       'FY2023/24 Q3 - FY2026/27 Q1',
       v.note
FROM (VALUES
    ('robbery',               993.55,   5715, NULL),
    ('burglary',              475.82,  24897, 'Residential + non-residential burglary.'),
    ('violent-crime',         301.19, 162135, 'Includes stalking and harassment (police.uk mapping, confirmed).'),
    ('drugs',                 294.98,  14775, 'Trafficking pulls the mean up; possession alone is much lower.'),
    ('possession-of-weapons', 141.00,   5713, NULL),
    ('other-crime',           100.98,  14483, 'Miscellaneous crimes against society.'),
    ('theft-from-the-person',  87.01,   2873, NULL),
    ('other-theft',            79.93,  26554, NULL),
    ('vehicle-crime',          73.08,  30489, NULL),
    ('criminal-damage-arson',  32.66,  40226, NULL),
    ('bicycle-theft',          18.55,   2242, NULL),
    ('public-order',           17.23,  36001, 'Includes harassment, alarm or distress (police.uk mapping).'),
    ('shoplifting',            13.09,  40826, NULL)
) AS v (category_code, severity_weight, sy_offences, note)
ON CONFLICT (category_code) DO NOTHING;

COMMENT ON TABLE analytics.cfg_crime_severity_weight IS
  'T-212 / D-13: one ONS-derived severity weight per police.uk category (days of custody). Editable; ASB deliberately absent.';


/* =====================================================================
   PART B - OUTCOME GROUPS  (T-213, D-14)
   Positive = Charged/summonsed + Out-of-court resolution.
   'Court result unavailable' counts as charged: the case reached court.
   ===================================================================== */
ALTER TABLE analytics.cfg_outcome_status ADD COLUMN IF NOT EXISTS outcome_group_sort  SMALLINT;
ALTER TABLE analytics.cfg_outcome_status ADD COLUMN IF NOT EXISTS is_positive_outcome BOOLEAN;

UPDATE analytics.cfg_outcome_status AS cfg
SET outcome_group = grp.outcome_group
FROM (
    SELECT cos.outcome_status_name,
           CASE
             WHEN cos.outcome_status_name IN ('Awaiting court outcome', 'Court result unavailable',
                                              'Suspect charged as part of another case')
                  THEN 'Charged / summonsed'
             WHEN cos.outcome_status_name IN ('Local resolution', 'Offender given a caution',
                                              'Offender given penalty notice', 'Offender given a drugs possession warning')
                  THEN 'Out-of-court resolution'
             WHEN cos.outcome_status_name IN ('Investigation complete; no suspect identified',
                                              'Unable to prosecute suspect')
                  THEN 'No suspect / unable to prosecute'
             WHEN cos.outcome_status_name ILIKE '%not in the public interest%'
                  THEN 'Not in public interest'
             WHEN cos.outcome_status_name = 'Action to be taken by another organisation'
                  THEN 'Transferred'
             WHEN cos.outcome_stage = 'Pending'        THEN 'Pending'
             WHEN cos.outcome_stage = 'Not applicable' THEN 'Not applicable'
             WHEN cos.outcome_stage = 'Unknown'        THEN 'Unknown'
           END AS outcome_group
    FROM analytics.cfg_outcome_status AS cos
) AS grp
WHERE grp.outcome_status_name = cfg.outcome_status_name
  AND cfg.outcome_group IS NULL;

-- sort + positive flag always follow the group (edit the group, these follow)
UPDATE analytics.cfg_outcome_status
SET outcome_group_sort = CASE outcome_group
                           WHEN 'Charged / summonsed'              THEN 1
                           WHEN 'Out-of-court resolution'          THEN 2
                           WHEN 'No suspect / unable to prosecute' THEN 3
                           WHEN 'Not in public interest'           THEN 4
                           WHEN 'Transferred'                      THEN 5
                           WHEN 'Pending'                          THEN 6
                           WHEN 'Unknown'                          THEN 7
                           WHEN 'Not applicable'                   THEN 8
                         END,
    is_positive_outcome = COALESCE(outcome_group IN ('Charged / summonsed', 'Out-of-court resolution'), FALSE);


/* =====================================================================
   PART C - DIMENSIONS + POWER BI VIEWS
   sp_refresh_model() already copies outcome_group into the dimension;
   here the same sync is done once so no full model refresh is needed.
   The new attributes are read from the config tables in the pbi views,
   so they stay current after any edit.
   ===================================================================== */
UPDATE analytics.dim_outcome_status AS dos
SET outcome_group = cfg.outcome_group
FROM analytics.cfg_outcome_status AS cfg
WHERE cfg.outcome_status_name = dos.outcome_status_name
  AND dos.outcome_group IS DISTINCT FROM cfg.outcome_group;

UPDATE analytics.dim_outcome_status
SET outcome_group = 'Unknown'
WHERE is_unknown_member AND outcome_group IS NULL;

CREATE OR REPLACE VIEW pbi.dim_crime_category AS
SELECT dcc.category_key, dcc.category_code, dcc.category_name, dcc.category_group, dcc.group_sort_order,
       dcc.is_unknown_member,
       (dcc.category_code = 'anti-social-behaviour')  AS is_asb,
       sw.severity_weight
FROM analytics.dim_crime_category               AS dcc
LEFT JOIN analytics.cfg_crime_severity_weight   AS sw ON sw.category_code = dcc.category_code;

CREATE OR REPLACE VIEW pbi.dim_outcome_status AS
SELECT dos.outcome_status_key, dos.outcome_status_name, dos.outcome_code, dos.status_source, dos.outcome_stage,
       dos.stage_sort, dos.outcome_group, dos.is_unknown_member,
       COALESCE(cfg.outcome_group_sort, 7)           AS outcome_group_sort,
       COALESCE(cfg.is_positive_outcome, FALSE)      AS is_positive_outcome
FROM analytics.dim_outcome_status          AS dos
LEFT JOIN analytics.cfg_outcome_status     AS cfg ON cfg.outcome_status_name = dos.outcome_status_name;


/* =====================================================================
   PART D - VALIDATION  (read-only)
   ===================================================================== */

-- S1. Weights: expect 13 rows, every non-ASB analysed category weighted, 0 missing.
SELECT cc.category_code, cc.category_name, sw.severity_weight, sw.sy_offences_in_window,
       CASE WHEN cc.category_code = 'anti-social-behaviour' THEN 'ASB - separate component'
            WHEN sw.severity_weight IS NULL THEN 'MISSING WEIGHT'
            ELSE 'ok' END AS check_result
FROM analytics.cfg_crime_category              AS cc
LEFT JOIN analytics.cfg_crime_severity_weight  AS sw ON sw.category_code = cc.category_code
WHERE cc.include_in_analysis
ORDER BY sw.severity_weight DESC NULLS LAST;

-- S2. Outcome groups: expect 17 statuses, 0 with a NULL group; crimes per group (all months).
SELECT cfg.outcome_group_sort, cfg.outcome_group, cfg.is_positive_outcome,
       string_agg(cfg.outcome_status_name, ' | ' ORDER BY cfg.outcome_status_name) AS statuses,
       COUNT(*)                                                               AS status_count,
       (SELECT COUNT(*) FROM pbi.fact_crime AS fc
          JOIN pbi.dim_outcome_status AS dos ON dos.outcome_status_key = fc.outcome_status_key
         WHERE dos.outcome_group IS NOT DISTINCT FROM cfg.outcome_group)      AS crimes
FROM analytics.cfg_outcome_status AS cfg
GROUP BY cfg.outcome_group_sort, cfg.outcome_group, cfg.is_positive_outcome
ORDER BY cfg.outcome_group_sort NULLS FIRST;

-- S3. Headline baseline (South Yorkshire LSOAs + unknown LSOA crimes counted in totals).
--     Annualised rate = crimes / months * 12 / population * 1,000.
--     Severity score = annual sum of weights / population (ONS CSS units, per resident).
WITH win AS (SELECT COUNT(*)::numeric AS months FROM pbi.dim_month),
pop AS (
    SELECT SUM(fp.population_total)::numeric AS population
    FROM pbi.fact_population AS fp
    JOIN pbi.dim_lsoa AS dl ON dl.lsoa_key = fp.lsoa_key
    WHERE dl.is_south_yorkshire
      AND fp.mid_year = (SELECT MAX(mid_year) FROM pbi.fact_population)
),
c AS (
    SELECT COUNT(*) FILTER (WHERE NOT dcc.is_asb)                                  AS crimes_excl_asb,
           COUNT(*) FILTER (WHERE dcc.is_asb)                                      AS asb_incidents,
           SUM(dcc.severity_weight)                                                AS severity_days,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature)         AS mature_crimes,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature AND dos.is_positive_outcome) AS mature_positive,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature AND dos.outcome_group = 'Unknown') AS mature_unknown,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature AND dos.outcome_group = 'Pending') AS mature_pending
    FROM pbi.fact_crime              AS fc
    JOIN pbi.dim_crime_category      AS dcc ON dcc.category_key       = fc.category_key
    JOIN pbi.dim_month               AS dm  ON dm.month_key           = fc.month_key
    JOIN pbi.dim_outcome_status      AS dos ON dos.outcome_status_key = fc.outcome_status_key
)
SELECT win.months, pop.population, c.crimes_excl_asb, c.asb_incidents,
       ROUND(c.crimes_excl_asb / win.months * 12 / NULLIF(pop.population, 0) * 1000, 1) AS crime_rate_per_1000_pa,
       ROUND(c.asb_incidents   / win.months * 12 / NULLIF(pop.population, 0) * 1000, 1) AS asb_rate_per_1000_pa,
       ROUND(c.severity_days   / win.months * 12 / NULLIF(pop.population, 0), 2)        AS severity_score_pa,
       ROUND(c.severity_days   / NULLIF(c.crimes_excl_asb, 0), 1)                       AS avg_severity_per_crime,
       c.mature_crimes,
       ROUND(100.0 * c.mature_positive / NULLIF(c.mature_crimes, 0), 2)                 AS positive_outcome_rate_pct,
       ROUND(100.0 * c.mature_unknown  / NULLIF(c.mature_crimes, 0), 2)                 AS unknown_outcome_pct,
       ROUND(100.0 * c.mature_pending  / NULLIF(c.mature_crimes, 0), 2)                 AS pending_outcome_pct
FROM win, pop, c;

-- S4. Same measures by local authority (crimes in South Yorkshire LSOAs only).
WITH win AS (SELECT COUNT(*)::numeric AS months FROM pbi.dim_month),
pop AS (
    SELECT dl.local_authority, SUM(fp.population_total)::numeric AS population
    FROM pbi.fact_population AS fp
    JOIN pbi.dim_lsoa AS dl ON dl.lsoa_key = fp.lsoa_key
    WHERE dl.is_south_yorkshire AND fp.mid_year = (SELECT MAX(mid_year) FROM pbi.fact_population)
    GROUP BY dl.local_authority
),
c AS (
    SELECT dl.local_authority,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb)  AS crimes_excl_asb,
           COUNT(*) FILTER (WHERE dcc.is_asb)      AS asb_incidents,
           SUM(dcc.severity_weight)                AS severity_days,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature)                         AS mature_crimes,
           COUNT(*) FILTER (WHERE NOT dcc.is_asb AND dm.is_outcome_mature AND dos.is_positive_outcome) AS mature_positive
    FROM pbi.fact_crime          AS fc
    JOIN pbi.dim_lsoa            AS dl  ON dl.lsoa_key            = fc.lsoa_key
    JOIN pbi.dim_crime_category  AS dcc ON dcc.category_key       = fc.category_key
    JOIN pbi.dim_month           AS dm  ON dm.month_key           = fc.month_key
    JOIN pbi.dim_outcome_status  AS dos ON dos.outcome_status_key = fc.outcome_status_key
    WHERE dl.is_south_yorkshire
    GROUP BY dl.local_authority
)
SELECT c.local_authority, pop.population, c.crimes_excl_asb, c.asb_incidents,
       ROUND(c.crimes_excl_asb / win.months * 12 / NULLIF(pop.population, 0) * 1000, 1) AS crime_rate_per_1000_pa,
       ROUND(c.asb_incidents   / win.months * 12 / NULLIF(pop.population, 0) * 1000, 1) AS asb_rate_per_1000_pa,
       ROUND(c.severity_days   / win.months * 12 / NULLIF(pop.population, 0), 2)        AS severity_score_pa,
       ROUND(100.0 * c.mature_positive / NULLIF(c.mature_crimes, 0), 2)                 AS positive_outcome_rate_pct
FROM c
JOIN pop ON pop.local_authority = c.local_authority
CROSS JOIN win
ORDER BY crime_rate_per_1000_pa DESC;

-- S5. Last 12 vs prior 12 months (excl. ASB, and ASB separately).
SELECT CASE WHEN dcc.is_asb THEN 'ASB' ELSE 'Crime excl. ASB' END                   AS measure,
       COUNT(*) FILTER (WHERE dm.is_last_12_months)                                AS last_12,
       COUNT(*) FILTER (WHERE dm.is_prior_12_months)                               AS prior_12,
       ROUND(100.0 * (COUNT(*) FILTER (WHERE dm.is_last_12_months)
                    - COUNT(*) FILTER (WHERE dm.is_prior_12_months))
             / NULLIF(COUNT(*) FILTER (WHERE dm.is_prior_12_months), 0), 2)        AS pct_change
FROM pbi.fact_crime         AS fc
JOIN pbi.dim_crime_category AS dcc ON dcc.category_key = fc.category_key
JOIN pbi.dim_month          AS dm  ON dm.month_key     = fc.month_key
GROUP BY dcc.is_asb
ORDER BY measure;

-- S6. Category share and severity share (excl. ASB), whole window.
SELECT dcc.category_name, COUNT(*) AS crimes,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                                   AS pct_of_crimes,
       ROUND(100.0 * SUM(dcc.severity_weight) / SUM(SUM(dcc.severity_weight)) OVER (), 2)   AS pct_of_severity
FROM pbi.fact_crime         AS fc
JOIN pbi.dim_crime_category AS dcc ON dcc.category_key = fc.category_key
WHERE NOT dcc.is_asb
GROUP BY dcc.category_name
ORDER BY crimes DESC;

-- S7. Seasonality: average crimes per month by season, complete seasons only (DQ-24).
WITH season_months AS (
    SELECT dm.season_label, dm.season, dm.season_sort, COUNT(*) AS months_in_data
    FROM pbi.dim_month AS dm
    GROUP BY dm.season_label, dm.season, dm.season_sort
)
SELECT sm.season, sm.season_sort,
       COUNT(DISTINCT sm.season_label)                                      AS complete_seasons,
       ROUND(COUNT(*)::numeric / NULLIF(COUNT(DISTINCT dm.month_key), 0), 0)  AS avg_crimes_per_month_excl_asb
FROM season_months     AS sm
JOIN pbi.dim_month     AS dm  ON dm.season_label = sm.season_label
JOIN pbi.fact_crime    AS fc  ON fc.month_key    = dm.month_key
JOIN pbi.dim_crime_category AS dcc ON dcc.category_key = fc.category_key AND NOT dcc.is_asb
WHERE sm.months_in_data = 3
GROUP BY sm.season, sm.season_sort
ORDER BY sm.season_sort;

-- S8. Time to outcome: months from crime to latest status, positive outcomes, mature months.
SELECT dos.outcome_group,
       COUNT(*)                                                                   AS crimes,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fc.months_to_latest_outcome)    AS median_months,
       ROUND(AVG(fc.months_to_latest_outcome), 2)                                 AS mean_months
FROM pbi.fact_crime          AS fc
JOIN pbi.dim_outcome_status  AS dos ON dos.outcome_status_key = fc.outcome_status_key
JOIN pbi.dim_month           AS dm  ON dm.month_key           = fc.month_key
WHERE dm.is_outcome_mature
  AND fc.months_to_latest_outcome IS NOT NULL
GROUP BY dos.outcome_group, dos.outcome_group_sort
ORDER BY dos.outcome_group_sort;
