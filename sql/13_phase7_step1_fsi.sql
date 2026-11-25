/* =====================================================================
   PHASE 7 - STEP 1 : FAMILY SUITABILITY INDEX (FSI)   (T-217, D-16)
   Database : CrimeData   (run in DBeaver after phase6_step1_nsi.sql)

   Decisions (user, 12 Nov 2026)
     Weights        A family-first: safety 35 / affordability 20 /
                    schools 20 / family community 10 / environment 15
     Affordability  buyer budget: over-budget LSOAs are excluded;
                    within budget, more headroom scores higher
     Centres        high-footfall centres excluded from recommendations
     Value list     yes: LSOAs safer than their price predicts

   Components (all 0-100, higher = better for a family, percentile
   rank within the 860 South Yorkshire LSOAs, mid-ranks for ties):
     Safety         NSI Score (Phase 6)
     Schools        IoD 2025 Children & Young People education decile
                    (proxy; Ofsted deferred, D-08)
     Family         % households with dependent children (Census 2021)
     Environment    mean of IoD Living + Outdoor Environment deciles
     Affordability  budget-dependent, NOT a percentile:
                    MIN(100, 200 x (1 - price / budget)); price = typical
                    HOUSE price (houses only; all-property median if no
                    house figure). price > budget -> excluded.
                    At half the budget or less the score is 100.
   The overall IMD is not used (it contains the crime domain, D-11).

   Part A : parameters
   Part B : analytics.fact_fsi_lsoa       (materialized view: components,
                                           value-for-money residual)
   Part C : analytics.fn_fsi(budget, weights...)  (FSI for any budget)
            analytics.vw_fsi_default      (FSI at the default budget)
            analytics.sp_refresh_fsi()
   Part D : pbi.dim_lsoa extended (columns appended)
   Part E : validation F1-F8
   ===================================================================== */


/* =====================================================================
   PART A - PARAMETERS
   ===================================================================== */
INSERT INTO analytics.cfg_parameter (parameter_name, parameter_value, description) VALUES
    ('fsi_weight_safety',        0.35,   'FSI weight: safety (NSI percentile). D-16 option A.'),
    ('fsi_weight_affordability', 0.20,   'FSI weight: affordability against the buyer budget.'),
    ('fsi_weight_schools',       0.20,   'FSI weight: IoD Children & Young People education (schools proxy).'),
    ('fsi_weight_family',        0.10,   'FSI weight: % households with dependent children.'),
    ('fsi_weight_environment',   0.15,   'FSI weight: IoD living + outdoor environment.'),
    ('fsi_default_budget',       250000, 'Default buyer budget (GBP) for the SQL baseline and the Power BI slider default.'),
    ('fsi_value_min_nsi',        50,     'Good-value list: minimum NSI score.')
ON CONFLICT (parameter_name) DO NOTHING;


/* =====================================================================
   PART B - COMPONENTS AND VALUE FOR MONEY
   ===================================================================== */
DROP MATERIALIZED VIEW IF EXISTS analytics.fact_fsi_lsoa CASCADE;   -- drops vw_fsi_default and pbi.dim_lsoa; all recreated below

CREATE MATERIALIZED VIEW analytics.fact_fsi_lsoa AS
WITH base AS (
    SELECT n.lsoa_key,
           n.lsoa_code,
           dl.lsoa_name,
           n.local_authority,
           n.population_2024,
           n.nsi_score,
           n.is_high_footfall_centre,
           pr.children_young_people_decile                                     AS schools_decile,
           pr.pct_households_dependent_children                                AS pct_dependent_children,
           ROUND((pr.living_env_decile + pr.outdoors_env_decile) / 2.0, 1)     AS environment_decile_avg,
           COALESCE(vp.house_price_indicator, vp.price_indicator)::numeric     AS family_price,
           CASE WHEN vp.house_price_indicator IS NOT NULL THEN 'houses' ELSE 'all property' END AS family_price_basis
    FROM analytics.fact_nsi_lsoa        AS n
    JOIN analytics.dim_lsoa             AS dl ON dl.lsoa_key = n.lsoa_key
    JOIN analytics.vw_lsoa_profile      AS pr ON pr.lsoa_key = n.lsoa_key
    LEFT JOIN analytics.vw_lsoa_price   AS vp ON vp.lsoa_key = n.lsoa_key
),
pct AS (   -- higher = better for a family; mid-ranks for ties
    SELECT b.*,
           100.0 * (RANK() OVER (ORDER BY b.nsi_score)              - 1 + (COUNT(*) OVER (PARTITION BY b.nsi_score)              - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_safety,
           100.0 * (RANK() OVER (ORDER BY b.schools_decile)         - 1 + (COUNT(*) OVER (PARTITION BY b.schools_decile)         - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_schools,
           100.0 * (RANK() OVER (ORDER BY b.pct_dependent_children) - 1 + (COUNT(*) OVER (PARTITION BY b.pct_dependent_children) - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_family,
           100.0 * (RANK() OVER (ORDER BY b.environment_decile_avg) - 1 + (COUNT(*) OVER (PARTITION BY b.environment_decile_avg) - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_environment
    FROM base AS b
),
fit AS (   -- value for money: NSI ~ ln(price), fitted on non-centre LSOAs
    SELECT regr_slope(nsi_score, LN(family_price))     AS slope,
           regr_intercept(nsi_score, LN(family_price)) AS intercept,
           regr_r2(nsi_score, LN(family_price))        AS r2
    FROM base
    WHERE NOT is_high_footfall_centre AND family_price > 0
),
val AS (
    SELECT p.*,
           f.slope, f.intercept, f.r2,
           f.intercept + f.slope * LN(p.family_price)                   AS nsi_expected_for_price,
           p.nsi_score - (f.intercept + f.slope * LN(p.family_price))   AS value_residual
    FROM pct AS p
    CROSS JOIN fit AS f

)
SELECT vr.lsoa_key, vr.lsoa_code, vr.lsoa_name, vr.local_authority, vr.population_2024,
       vr.nsi_score, vr.is_high_footfall_centre,
       vr.schools_decile, vr.pct_dependent_children, vr.environment_decile_avg,
       vr.family_price, vr.family_price_basis,
       ROUND(vr.pct_safety::numeric, 1)       AS pct_safety,
       ROUND(vr.pct_schools::numeric, 1)      AS pct_schools,
       ROUND(vr.pct_family::numeric, 1)       AS pct_family,
       ROUND(vr.pct_environment::numeric, 1)  AS pct_environment,
       ROUND(vr.nsi_expected_for_price::numeric, 1) AS nsi_expected_for_price,
       ROUND(vr.value_residual::numeric, 1)         AS value_residual,
       ROUND(vr.slope::numeric, 3)                  AS value_fit_slope,
       ROUND(vr.r2::numeric, 3)                     AS value_fit_r2
FROM val AS vr
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_fsi_lsoa ON analytics.fact_fsi_lsoa (lsoa_key);

COMMENT ON MATERIALIZED VIEW analytics.fact_fsi_lsoa IS
  'T-217 / D-16: FSI components per South Yorkshire LSOA (budget-independent) and the value-for-money residual. Refresh: CALL analytics.sp_refresh_fsi();';


/* =====================================================================
   PART C - FSI FOR A GIVEN BUDGET
   ===================================================================== */
CREATE OR REPLACE FUNCTION analytics.fn_fsi(
    p_budget        NUMERIC,
    p_w_safety      NUMERIC DEFAULT NULL,
    p_w_afford      NUMERIC DEFAULT NULL,
    p_w_schools     NUMERIC DEFAULT NULL,
    p_w_family      NUMERIC DEFAULT NULL,
    p_w_environment NUMERIC DEFAULT NULL)
RETURNS TABLE (
    lsoa_key INT, lsoa_code VARCHAR, lsoa_name VARCHAR, local_authority VARCHAR,
    family_price NUMERIC, affordability_score NUMERIC,
    is_over_budget BOOLEAN, is_eligible BOOLEAN, exclusion_reason TEXT,
    fsi_score NUMERIC, fsi_rank BIGINT, fsi_rank_in_la BIGINT)
LANGUAGE sql STABLE
AS $$
WITH w AS (
    SELECT COALESCE(p_w_safety,      MAX(parameter_value) FILTER (WHERE parameter_name = 'fsi_weight_safety'))        AS ws,
           COALESCE(p_w_afford,      MAX(parameter_value) FILTER (WHERE parameter_name = 'fsi_weight_affordability')) AS wa,
           COALESCE(p_w_schools,     MAX(parameter_value) FILTER (WHERE parameter_name = 'fsi_weight_schools'))       AS wsc,
           COALESCE(p_w_family,      MAX(parameter_value) FILTER (WHERE parameter_name = 'fsi_weight_family'))        AS wf,
           COALESCE(p_w_environment, MAX(parameter_value) FILTER (WHERE parameter_name = 'fsi_weight_environment'))   AS we
    FROM analytics.cfg_parameter
),
s AS (
    SELECT f.*,
           ROUND(LEAST(100, GREATEST(0, 200 * (1 - f.family_price / NULLIF(p_budget, 0))))::numeric, 1) AS afford,
           (f.family_price > p_budget)                                                               AS over_budget
    FROM analytics.fact_fsi_lsoa AS f
),
scored AS (
    SELECT s.*,
           NOT s.is_high_footfall_centre AND NOT s.over_budget AND s.family_price IS NOT NULL AS eligible,
           CASE WHEN s.is_high_footfall_centre THEN 'High-footfall centre'
                WHEN s.family_price IS NULL      THEN 'No price'
                WHEN s.over_budget               THEN 'Over budget' END                   AS reason,
           ROUND(((w.ws * s.pct_safety + w.wa * s.afford + w.wsc * s.pct_schools
                 + w.wf * s.pct_family + w.we * s.pct_environment)
                 / NULLIF(w.ws + w.wa + w.wsc + w.wf + w.we, 0))::numeric, 1)              AS fsi
    FROM s CROSS JOIN w
)
SELECT sc.lsoa_key::int, sc.lsoa_code::varchar, sc.lsoa_name::varchar, sc.local_authority::varchar,
       sc.family_price, sc.afford, sc.over_budget, sc.eligible, sc.reason,
       CASE WHEN sc.eligible THEN sc.fsi END,
       CASE WHEN sc.eligible THEN RANK() OVER (PARTITION BY sc.eligible ORDER BY sc.fsi DESC) END,
       CASE WHEN sc.eligible THEN RANK() OVER (PARTITION BY sc.eligible, sc.local_authority ORDER BY sc.fsi DESC) END
FROM scored AS sc;
$$;

COMMENT ON FUNCTION analytics.fn_fsi(NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC, NUMERIC) IS
  'T-217: FSI per LSOA for a budget (GBP) and optional weights (default: cfg_parameter). Ineligible LSOAs (centre / over budget) get no score.';

CREATE OR REPLACE VIEW analytics.vw_fsi_default AS
SELECT fx.*
FROM analytics.cfg_parameter AS cp,
     LATERAL analytics.fn_fsi(cp.parameter_value) AS fx
WHERE cp.parameter_name = 'fsi_default_budget';

CREATE OR REPLACE PROCEDURE analytics.sp_refresh_fsi()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.fact_fsi_lsoa;
END;
$$;

COMMENT ON PROCEDURE analytics.sp_refresh_fsi() IS
  'Run after sp_refresh_nsi(). Order after a data reload: sp_refresh_model -> sp_refresh_nsi -> sp_refresh_fsi.';


/* =====================================================================
   PART D - POWER BI: pbi.dim_lsoa (previous columns unchanged; FSI appended)
   Affordability, eligibility and the FSI itself are computed in DAX from
   the buyer's budget; only budget-independent columns are imported.
   ===================================================================== */
CREATE OR REPLACE VIEW pbi.dim_lsoa AS
SELECT dl.lsoa_key, dl.lsoa_code, dl.lsoa_name, dl.local_authority, dl.is_south_yorkshire, dl.is_unknown_member,
       pr.population_2024, pr.children_0_15_2024, pr.pct_children_0_15, pr.pct_aged_65_plus, pr.median_age_2024,
       pr.imd_score, pr.imd_rank, pr.imd_decile,
       pr.income_decile, pr.employment_decile, pr.education_decile, pr.health_decile,
       pr.crime_domain_score, pr.crime_domain_decile,
       pr.barriers_decile, pr.living_env_decile, pr.outdoors_env_decile,
       pr.idaci_score, pr.idaci_decile, pr.children_young_people_decile,
       pr.households_2021, pr.pct_households_dependent_children, pr.pct_lone_parent_households,
       pr.pct_owner_occupied, pr.pct_social_rented, pr.pct_private_rented,
       pr.best_fit_neighbourhood_key, pr.best_fit_share,
       vp.msoa_code, vp.msoa_name, vp.sales_count, vp.house_sales_count,
       vp.price_indicator, vp.price_method, vp.house_price_indicator, vp.house_price_method,
       vp.lsoa_lower_quartile_price,
       -- Phase 6: NSI
       nsi.crime_rate_raw, nsi.crime_rate_smoothed,
       nsi.severity_score_raw, nsi.severity_score_smoothed,
       nsi.asb_rate_raw, nsi.asb_rate_smoothed,
       nsi.shrink_weight_crime,
       nsi.trend_z_adj, nsi.trend_pct_change, nsi.trend_class,
       nsi.pct_severity, nsi.pct_crime_rate, nsi.pct_asb_rate, nsi.pct_trend,
       nsi.nsi_score, nsi.nsi_band, nsi.nsi_band_sort, nsi.nsi_rank, nsi.nsi_rank_in_la,
       nsi.is_high_footfall_centre,
       -- Phase 7: FSI components and value for money
       fsi.family_price, fsi.family_price_basis,
       fsi.pct_safety, fsi.pct_schools, fsi.pct_family, fsi.pct_environment,
       fsi.environment_decile_avg,
       fsi.nsi_expected_for_price, fsi.value_residual
FROM analytics.dim_lsoa             AS dl
LEFT JOIN analytics.vw_lsoa_profile AS pr  ON pr.lsoa_key  = dl.lsoa_key
LEFT JOIN analytics.vw_lsoa_price   AS vp  ON vp.lsoa_key  = dl.lsoa_key
LEFT JOIN analytics.fact_nsi_lsoa   AS nsi ON nsi.lsoa_key = dl.lsoa_key
LEFT JOIN analytics.fact_fsi_lsoa   AS fsi ON fsi.lsoa_key = dl.lsoa_key;


/* =====================================================================
   PART E - VALIDATION (read-only)
   ===================================================================== */

-- F1. Coverage at the default budget (GBP 250,000). Expect 860 LSOAs, 0 NULL
--     components, 29 centres excluded; the rest split eligible / over budget.
SELECT COUNT(*)                                                   AS lsoas,
       COUNT(*) FILTER (WHERE f.pct_schools IS NULL OR f.pct_family IS NULL
                           OR f.pct_environment IS NULL OR f.family_price IS NULL) AS missing_component,
       COUNT(*) FILTER (WHERE d.is_eligible)                      AS eligible,
       COUNT(*) FILTER (WHERE d.exclusion_reason = 'High-footfall centre') AS excluded_centre,
       COUNT(*) FILTER (WHERE d.exclusion_reason = 'Over budget')          AS excluded_over_budget,
       COUNT(*) FILTER (WHERE f.family_price_basis = 'all property')       AS price_not_houses_only,
       MIN(d.fsi_score) AS min_fsi, MAX(d.fsi_score) AS max_fsi, ROUND(AVG(d.fsi_score), 1) AS mean_fsi
FROM analytics.fact_fsi_lsoa  AS f
JOIN analytics.vw_fsi_default AS d ON d.lsoa_key = f.lsoa_key;

-- F2. How related are the components? (Spearman; |rho| > 0.7 = largely the same signal)
WITH r AS (
    SELECT RANK() OVER (ORDER BY pct_safety)      AS s,
           RANK() OVER (ORDER BY pct_schools)     AS sc,
           RANK() OVER (ORDER BY pct_family)      AS fa,
           RANK() OVER (ORDER BY pct_environment) AS en,
           RANK() OVER (ORDER BY family_price)    AS pr
    FROM analytics.fact_fsi_lsoa
)
SELECT ROUND(corr(s, sc)::numeric, 3) AS safety_schools, ROUND(corr(s, fa)::numeric, 3) AS safety_family,
       ROUND(corr(s, en)::numeric, 3) AS safety_environment, ROUND(corr(s, pr)::numeric, 3) AS safety_price,
       ROUND(corr(sc, pr)::numeric, 3) AS schools_price, ROUND(corr(sc, en)::numeric, 3) AS schools_environment,
       ROUND(corr(fa, pr)::numeric, 3) AS family_price
FROM r;

-- F3. Top 15 LSOAs for a family at the default budget.
SELECT d.fsi_rank, d.lsoa_code, d.lsoa_name, d.local_authority, d.fsi_score,
       f.nsi_score, d.family_price, d.affordability_score,
       f.schools_decile, ROUND(f.pct_dependent_children::numeric, 1) AS pct_dep_children, f.environment_decile_avg
FROM analytics.vw_fsi_default AS d
JOIN analytics.fact_fsi_lsoa  AS f ON f.lsoa_key = d.lsoa_key
WHERE d.is_eligible
ORDER BY d.fsi_rank, d.lsoa_code
LIMIT 15;

-- F4. By district at the default budget: eligible LSOAs, mean FSI, share of the top 50.
SELECT d.local_authority,
       COUNT(*)                                             AS lsoas,
       COUNT(*) FILTER (WHERE d.is_eligible)                AS eligible,
       ROUND(AVG(d.fsi_score), 1)                           AS mean_fsi_eligible,
       COUNT(*) FILTER (WHERE d.fsi_rank <= 50)             AS in_top_50
FROM analytics.vw_fsi_default AS d
GROUP BY d.local_authority
ORDER BY in_top_50 DESC;

-- F5. Weight sensitivity at the default budget: B safety-first (50/15/15/10/10) and
--     C value-first (30/35/15/10/10) vs A. Ranks over LSOAs eligible in all.
WITH a AS (SELECT lsoa_key, fsi_score FROM analytics.vw_fsi_default WHERE is_eligible),
     b AS (SELECT lsoa_key, fsi_score FROM analytics.fn_fsi(250000, 0.50, 0.15, 0.15, 0.10, 0.10) WHERE is_eligible),
     c AS (SELECT lsoa_key, fsi_score FROM analytics.fn_fsi(250000, 0.30, 0.35, 0.15, 0.10, 0.10) WHERE is_eligible),
     r AS (
        SELECT RANK() OVER (ORDER BY a.fsi_score DESC) AS ra,
               RANK() OVER (ORDER BY b.fsi_score DESC) AS rb,
               RANK() OVER (ORDER BY c.fsi_score DESC) AS rc
        FROM a JOIN b USING (lsoa_key) JOIN c USING (lsoa_key)
     )
SELECT 'B safety-first' AS scenario, ROUND(corr(ra, rb)::numeric, 3) AS spearman_vs_a,
       COUNT(*) FILTER (WHERE ra <= 50 AND rb <= 50) AS top50_overlap FROM r
UNION ALL
SELECT 'C value-first', ROUND(corr(ra, rc)::numeric, 3),
       COUNT(*) FILTER (WHERE ra <= 50 AND rc <= 50) FROM r;

-- F6. Value for money: fit of NSI on ln(house price), non-centre LSOAs.
--     Then the 15 LSOAs most safer than their price predicts (NSI >= 50, not centres).
SELECT MAX(value_fit_slope) AS nsi_points_per_ln_price, MAX(value_fit_r2) AS r2,
       ROUND(MAX(value_fit_slope) * LN(2)::numeric, 1) AS nsi_points_per_price_doubling
FROM analytics.fact_fsi_lsoa;

SELECT lsoa_code, lsoa_name, local_authority, family_price, nsi_score, nsi_expected_for_price, value_residual,
       schools_decile
FROM analytics.fact_fsi_lsoa
WHERE NOT is_high_footfall_centre
  AND nsi_score >= (SELECT parameter_value FROM analytics.cfg_parameter WHERE parameter_name = 'fsi_value_min_nsi')
ORDER BY value_residual DESC
LIMIT 15;

-- F7. Budget sensitivity: eligible LSOAs and the top LSOA at five budgets.
SELECT b.budget,
       COUNT(*) FILTER (WHERE fx.is_eligible)                                   AS eligible_lsoas,
       ROUND(AVG(fx.fsi_score), 1)                                              AS mean_fsi,
       (ARRAY_AGG(fx.lsoa_name || ' (' || fx.local_authority || ')' ORDER BY fx.fsi_score DESC NULLS LAST))[1] AS top_lsoa,
       MAX(fx.fsi_score)                                                        AS top_fsi
FROM (VALUES (150000), (200000), (250000), (300000), (400000)) AS b (budget)
CROSS JOIN LATERAL analytics.fn_fsi(b.budget) AS fx
GROUP BY b.budget
ORDER BY b.budget;
