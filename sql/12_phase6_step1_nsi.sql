/* =====================================================================
   PHASE 6 - STEP 1 : NEIGHBOURHOOD SAFETY INDEX (NSI)   (T-215, D-15)
   Database : CrimeData   (run in DBeaver, connected as the owner)

   Decisions (user, 12 Nov 2026)
     Weights      A  harm-led: severity 50 / crime rate 20 / ASB rate 20 / trend 10
     Scaling      percentile rank within the 860 South Yorkshire LSOAs
     Small areas  empirical Bayes smoothing towards the district rate
     Centres      keep the score, flag high-footfall LSOAs

   Part A : parameters in analytics.cfg_parameter (editable)
   Part B : analytics.vw_nsi_lsoa_input   (view, one row per SY LSOA)
   Part C : analytics.fact_nsi_lsoa       (materialized view, the index)
            analytics.vw_nsi_sensitivity  (view, weight scenarios B / C,
                                           unsmoothed A)
            analytics.sp_refresh_nsi()    (procedure)
   Part D : pbi.dim_lsoa extended with the NSI columns (appended)
   Part E : validation N1-N8 (read-only)

   Method notes
   - Rates are annualised over the months in dim_month and use the
     mid-2024 population. Crimes with no location / out-of-county LSOA
     cannot be placed in an LSOA and are not in the LSOA index.
   - Smoothing: Marshall (1991) global empirical Bayes, prior = district
     (local authority) rate. Shrinkage weight w = s2 / (s2 + k*m/e):
       e  = exposure in 1,000 person-years
       m  = district rate,  s2 = between-LSOA variance (method of moments)
       k  = 1 for counts; for severity k = sum(n*w^2)/sum(n*w)
            (compound Poisson: one crime carries its category weight).
     An LSOA with many crimes keeps almost its own rate; a small one is
     pulled towards its district.
   - Trend: z = (L - P)/sqrt(L + P), last 12 vs prior 12 months,
     divided by sqrt(phi), phi = Pearson over-dispersion across LSOAs
     (>= 1). Only a significant change (|z_adj| >= 1.96) counts; a
     non-significant change is treated as 0 (stable).
   - Percentile (0 = least safe, 100 = safest) uses mid-ranks for ties.
   - After editing a weight:  CALL analytics.sp_refresh_nsi();
   ===================================================================== */


/* =====================================================================
   PART A - PARAMETERS
   ===================================================================== */
INSERT INTO analytics.cfg_parameter (parameter_name, parameter_value, description) VALUES
    ('nsi_weight_severity',      0.50, 'NSI weight: smoothed severity score (ONS CSS units). D-15 option A.'),
    ('nsi_weight_crime_rate',    0.20, 'NSI weight: smoothed crime rate per 1,000 (excl. ASB).'),
    ('nsi_weight_asb_rate',      0.20, 'NSI weight: smoothed ASB rate per 1,000.'),
    ('nsi_weight_trend',         0.10, 'NSI weight: significant change, last 12 vs prior 12 months.'),
    ('nsi_centre_rate_multiple', 3,    'Flag an LSOA as a high-footfall centre when its raw crime rate exceeds this multiple of the South Yorkshire LSOA median (DQ-18).'),
    ('nsi_trend_min_change',     0.05, 'Rising / Falling needs a significant change of at least this size.')
ON CONFLICT (parameter_name) DO NOTHING;


/* =====================================================================
   PART B - INPUTS PER LSOA
   ===================================================================== */
CREATE OR REPLACE VIEW analytics.vw_nsi_lsoa_input AS
WITH win AS (
    SELECT COUNT(*)::numeric / 12 AS years FROM analytics.dim_month
),
crime AS (
    SELECT fc.lsoa_key,
           COUNT(*) FILTER (WHERE dcc.category_code <> 'anti-social-behaviour')                      AS crimes,
           COUNT(*) FILTER (WHERE dcc.category_code =  'anti-social-behaviour')                      AS asb_incidents,
           COALESCE(SUM(sw.severity_weight), 0)                                                       AS severity_days,
           COALESCE(SUM(sw.severity_weight * sw.severity_weight), 0)                                  AS severity_days_sq,
           COUNT(*) FILTER (WHERE dcc.category_code <> 'anti-social-behaviour' AND dm.is_last_12_months)  AS crimes_last_12,
           COUNT(*) FILTER (WHERE dcc.category_code <> 'anti-social-behaviour' AND dm.is_prior_12_months) AS crimes_prior_12
    FROM analytics.fact_crime                      AS fc
    JOIN analytics.dim_crime_category              AS dcc ON dcc.category_key  = fc.category_key
    JOIN analytics.dim_month                       AS dm  ON dm.month_key      = fc.month_key
    LEFT JOIN analytics.cfg_crime_severity_weight  AS sw  ON sw.category_code  = dcc.category_code
    GROUP BY fc.lsoa_key
)
SELECT dl.lsoa_key,
       dl.lsoa_code,
       dl.local_authority,
       pr.population_2024,
       win.years,
       pr.population_2024 * win.years / 1000.0       AS exposure_k_py,      -- 1,000 person-years
       COALESCE(c.crimes, 0)                         AS crimes,
       COALESCE(c.asb_incidents, 0)                  AS asb_incidents,
       COALESCE(c.severity_days, 0)                  AS severity_days,
       COALESCE(c.severity_days_sq, 0)               AS severity_days_sq,
       COALESCE(c.crimes_last_12, 0)                 AS crimes_last_12,
       COALESCE(c.crimes_prior_12, 0)                AS crimes_prior_12
FROM analytics.dim_lsoa              AS dl
JOIN analytics.vw_lsoa_profile       AS pr ON pr.lsoa_key = dl.lsoa_key
CROSS JOIN win
LEFT JOIN crime                      AS c  ON c.lsoa_key  = dl.lsoa_key
WHERE dl.is_south_yorkshire
  AND NOT dl.is_unknown_member
  AND pr.population_2024 > 0;

COMMENT ON VIEW analytics.vw_nsi_lsoa_input IS
  'T-215: NSI inputs, one row per South Yorkshire LSOA (counts over the full window, mid-2024 population).';


/* =====================================================================
   PART C - THE INDEX
   ===================================================================== */
DROP MATERIALIZED VIEW IF EXISTS analytics.fact_nsi_lsoa CASCADE;   -- CASCADE drops the dependent pbi.dim_lsoa / sensitivity views; both are recreated below

CREATE MATERIALIZED VIEW analytics.fact_nsi_lsoa AS
WITH p AS (
    SELECT MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_weight_severity')      AS w_sev,
           MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_weight_crime_rate')    AS w_cr,
           MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_weight_asb_rate')      AS w_asb,
           MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_weight_trend')         AS w_tr,
           MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_centre_rate_multiple') AS centre_multiple,
           MAX(parameter_value) FILTER (WHERE parameter_name = 'nsi_trend_min_change')     AS trend_min_change
    FROM analytics.cfg_parameter
),
raw AS (
    SELECT i.*,
           i.crimes        / i.exposure_k_py  AS r_cr,     -- per 1,000 residents per year
           i.asb_incidents / i.exposure_k_py  AS r_asb,
           i.severity_days / i.exposure_k_py  AS r_sev,    -- severity days per 1,000 per year
           CASE WHEN i.crimes_last_12 + i.crimes_prior_12 > 0
                THEN (i.crimes_last_12 - i.crimes_prior_12) / SQRT(i.crimes_last_12 + i.crimes_prior_12)
           END                                AS trend_z
    FROM analytics.vw_nsi_lsoa_input AS i
),
district AS (   -- prior mean m, mean exposure, severity variance factor k
    SELECT local_authority,
           COUNT(*)                                      AS n_lsoa,
           SUM(crimes)        / SUM(exposure_k_py)       AS m_cr,
           SUM(asb_incidents) / SUM(exposure_k_py)       AS m_asb,
           SUM(severity_days) / SUM(exposure_k_py)       AS m_sev,
           SUM(exposure_k_py) / COUNT(*)                 AS e_bar,
           SUM(exposure_k_py)                            AS e_sum,
           SUM(severity_days_sq) / NULLIF(SUM(severity_days), 0) AS k_sev
    FROM raw
    GROUP BY local_authority
),
district_var AS (   -- between-LSOA variance s2 (method of moments, floored at 0)
    SELECT d.*,
           GREATEST(SUM(r.exposure_k_py * (r.r_cr  - d.m_cr)  ^ 2) / d.e_sum - d.m_cr  / d.e_bar,               0) AS s2_cr,
           GREATEST(SUM(r.exposure_k_py * (r.r_asb - d.m_asb) ^ 2) / d.e_sum - d.m_asb / d.e_bar,               0) AS s2_asb,
           GREATEST(SUM(r.exposure_k_py * (r.r_sev - d.m_sev) ^ 2) / d.e_sum - d.k_sev * d.m_sev / d.e_bar,     0) AS s2_sev
    FROM district AS d
    JOIN raw      AS r ON r.local_authority = d.local_authority
    GROUP BY d.local_authority, d.n_lsoa, d.m_cr, d.m_asb, d.m_sev, d.e_bar, d.e_sum, d.k_sev
),
force_phi AS (   -- over-dispersion of the trend statistic
    SELECT GREATEST(SUM(trend_z ^ 2) / NULLIF(COUNT(trend_z) - 1, 0), 1) AS phi
    FROM raw
),
smooth AS (
    SELECT r.*,
           dv.m_cr, dv.m_asb, dv.m_sev,
           NULLIF(dv.s2_cr, 0)  / (dv.s2_cr  + dv.m_cr                / r.exposure_k_py) AS shrink_w_cr,
           NULLIF(dv.s2_asb, 0) / (dv.s2_asb + dv.m_asb               / r.exposure_k_py) AS shrink_w_asb,
           NULLIF(dv.s2_sev, 0) / (dv.s2_sev + dv.k_sev * dv.m_sev    / r.exposure_k_py) AS shrink_w_sev,
           fp.phi,
           r.trend_z / SQRT(fp.phi)                                                     AS trend_z_adj,
           (r.crimes_last_12 - r.crimes_prior_12)::numeric / NULLIF(r.crimes_prior_12, 0) AS trend_pct_change
    FROM raw                AS r
    JOIN district_var       AS dv ON dv.local_authority = r.local_authority
    CROSS JOIN force_phi    AS fp
),
metrics AS (
    SELECT s.*,
           s.m_cr  + COALESCE(s.shrink_w_cr,  0) * (s.r_cr  - s.m_cr)   AS crime_rate_smoothed,
           s.m_asb + COALESCE(s.shrink_w_asb, 0) * (s.r_asb - s.m_asb)  AS asb_rate_smoothed,
           s.m_sev + COALESCE(s.shrink_w_sev, 0) * (s.r_sev - s.m_sev)  AS sev_rate_smoothed,
           -- trend metric: positive = worsening; non-significant or tiny base -> 0
           CASE WHEN s.crimes_last_12 + s.crimes_prior_12 < 20 THEN 0
                WHEN ABS(s.trend_z_adj) >= 1.96 THEN COALESCE(s.trend_pct_change, 0)
                ELSE 0 END                                             AS trend_metric,
           med.sy_median_rate
    FROM smooth AS s
    CROSS JOIN (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r_cr) AS sy_median_rate FROM raw) AS med
),
ranked AS (   -- safety percentiles: 0 = highest value (least safe), 100 = lowest; mid-rank for ties
    SELECT m.*,
           COUNT(*) OVER () AS n_all,
           100.0 * (RANK() OVER (ORDER BY m.sev_rate_smoothed   DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.sev_rate_smoothed)   - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_severity,
           100.0 * (RANK() OVER (ORDER BY m.crime_rate_smoothed DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.crime_rate_smoothed) - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_crime_rate,
           100.0 * (RANK() OVER (ORDER BY m.asb_rate_smoothed   DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.asb_rate_smoothed)   - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_asb_rate,
           100.0 * (RANK() OVER (ORDER BY m.trend_metric        DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.trend_metric)        - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_trend,
           -- unsmoothed versions, for the sensitivity test only
           100.0 * (RANK() OVER (ORDER BY m.r_sev DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.r_sev) - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_severity_raw,
           100.0 * (RANK() OVER (ORDER BY m.r_cr  DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.r_cr)  - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_crime_rate_raw,
           100.0 * (RANK() OVER (ORDER BY m.r_asb DESC) - 1 + (COUNT(*) OVER (PARTITION BY m.r_asb) - 1) / 2.0) / (COUNT(*) OVER () - 1) AS pct_asb_rate_raw
    FROM metrics AS m
),
scored AS (
    SELECT rk.*,
           ROUND((p.w_sev * rk.pct_severity + p.w_cr * rk.pct_crime_rate
                + p.w_asb * rk.pct_asb_rate + p.w_tr * rk.pct_trend)
                 / NULLIF(p.w_sev + p.w_cr + p.w_asb + p.w_tr, 0), 1)          AS nsi_score,
           (rk.r_cr > p.centre_multiple * rk.sy_median_rate)                    AS is_high_footfall_centre,
           CASE WHEN rk.crimes_last_12 + rk.crimes_prior_12 < 20             THEN 'Too few crimes'
                WHEN rk.trend_z_adj >=  1.96 AND rk.trend_pct_change >=  p.trend_min_change THEN 'Rising'
                WHEN rk.trend_z_adj <= -1.96 AND rk.trend_pct_change <= -p.trend_min_change THEN 'Falling'
                ELSE 'Stable' END                                               AS trend_class
    FROM ranked AS rk
    CROSS JOIN p
)
SELECT s.lsoa_key,
       s.lsoa_code,
       s.local_authority,
       s.population_2024,
       s.crimes, s.asb_incidents, s.severity_days,
       s.crimes_last_12, s.crimes_prior_12,
       ROUND(s.r_cr::numeric, 1)                         AS crime_rate_raw,
       ROUND(s.crime_rate_smoothed::numeric, 1)          AS crime_rate_smoothed,
       ROUND((s.r_sev / 1000)::numeric, 2)               AS severity_score_raw,        -- per resident (ONS CSS units)
       ROUND((s.sev_rate_smoothed / 1000)::numeric, 2)   AS severity_score_smoothed,
       ROUND(s.r_asb::numeric, 1)                        AS asb_rate_raw,
       ROUND(s.asb_rate_smoothed::numeric, 1)            AS asb_rate_smoothed,
       ROUND(s.shrink_w_cr::numeric, 3)                  AS shrink_weight_crime,       -- 1 = own rate kept, 0 = district rate
       ROUND(s.shrink_w_sev::numeric, 3)                 AS shrink_weight_severity,
       ROUND(s.trend_z_adj::numeric, 2)                  AS trend_z_adj,
       ROUND(s.trend_pct_change::numeric, 4)             AS trend_pct_change,
       s.trend_class,
       ROUND(s.pct_severity::numeric, 1)                 AS pct_severity,
       ROUND(s.pct_crime_rate::numeric, 1)               AS pct_crime_rate,
       ROUND(s.pct_asb_rate::numeric, 1)                 AS pct_asb_rate,
       ROUND(s.pct_trend::numeric, 1)                    AS pct_trend,
       ROUND(s.pct_severity_raw::numeric, 1)             AS pct_severity_raw,
       ROUND(s.pct_crime_rate_raw::numeric, 1)           AS pct_crime_rate_raw,
       ROUND(s.pct_asb_rate_raw::numeric, 1)             AS pct_asb_rate_raw,
       s.nsi_score,
       CASE WHEN s.nsi_score >= 80 THEN 'Very high safety'
            WHEN s.nsi_score >= 60 THEN 'High safety'
            WHEN s.nsi_score >= 40 THEN 'Moderate safety'
            WHEN s.nsi_score >= 20 THEN 'Low safety'
            ELSE 'Very low safety' END                   AS nsi_band,
       CASE WHEN s.nsi_score >= 80 THEN 1 WHEN s.nsi_score >= 60 THEN 2
            WHEN s.nsi_score >= 40 THEN 3 WHEN s.nsi_score >= 20 THEN 4 ELSE 5 END AS nsi_band_sort,
       RANK() OVER (ORDER BY s.nsi_score DESC)                                    AS nsi_rank,          -- 1 = safest of 860
       RANK() OVER (PARTITION BY s.local_authority ORDER BY s.nsi_score DESC)     AS nsi_rank_in_la,
       s.is_high_footfall_centre,
       ROUND(s.phi::numeric, 2)                          AS trend_overdispersion_phi
FROM scored AS s
WITH DATA;

CREATE UNIQUE INDEX IF NOT EXISTS ux_fact_nsi_lsoa ON analytics.fact_nsi_lsoa (lsoa_key);

COMMENT ON MATERIALIZED VIEW analytics.fact_nsi_lsoa IS
  'T-215 / D-15: Neighbourhood Safety Index per South Yorkshire LSOA (0-100, higher = safer). Refresh: CALL analytics.sp_refresh_nsi();';


-- Sensitivity scenarios (D-15): A = chosen, B = balanced, C = harm only, A_raw = A without smoothing
CREATE OR REPLACE VIEW analytics.vw_nsi_sensitivity AS
SELECT n.lsoa_key, n.lsoa_code, n.local_authority, n.is_high_footfall_centre,
       n.nsi_score                                                                                   AS nsi_a,
       ROUND(0.35 * n.pct_severity + 0.25 * n.pct_crime_rate + 0.25 * n.pct_asb_rate + 0.15 * n.pct_trend, 1) AS nsi_b,
       ROUND(0.70 * n.pct_severity + 0.30 * n.pct_asb_rate, 1)                                        AS nsi_c,
       ROUND(0.50 * n.pct_severity_raw + 0.20 * n.pct_crime_rate_raw + 0.20 * n.pct_asb_rate_raw + 0.10 * n.pct_trend, 1) AS nsi_a_raw
FROM analytics.fact_nsi_lsoa AS n;


CREATE OR REPLACE PROCEDURE analytics.sp_refresh_nsi()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.fact_nsi_lsoa;
END;
$$;

COMMENT ON PROCEDURE analytics.sp_refresh_nsi() IS
  'Rebuild the NSI after sp_refresh_model() or after editing an nsi_* parameter in cfg_parameter.';


/* =====================================================================
   PART D - POWER BI: pbi.dim_lsoa (existing columns unchanged, NSI appended)
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
       nsi.is_high_footfall_centre
FROM analytics.dim_lsoa             AS dl
LEFT JOIN analytics.vw_lsoa_profile AS pr  ON pr.lsoa_key  = dl.lsoa_key
LEFT JOIN analytics.vw_lsoa_price   AS vp  ON vp.lsoa_key  = dl.lsoa_key
LEFT JOIN analytics.fact_nsi_lsoa   AS nsi ON nsi.lsoa_key = dl.lsoa_key;


/* =====================================================================
   PART E - VALIDATION (read-only)
   ===================================================================== */

-- N1. Completeness. Expect 860 LSOAs, 0 NULL scores, weights sum 1.00,
--     scores 0-100, crimes + ASB = 501,963 (located in SY LSOAs, as S4).
SELECT COUNT(*)                                           AS lsoas,
       COUNT(*) FILTER (WHERE nsi_score IS NULL)          AS null_scores,
       MIN(nsi_score) AS min_nsi, MAX(nsi_score) AS max_nsi,
       ROUND(AVG(nsi_score), 1)                           AS mean_nsi,
       SUM(crimes) + SUM(asb_incidents)                   AS crimes_plus_asb,
       (SELECT SUM(parameter_value) FROM analytics.cfg_parameter
         WHERE parameter_name LIKE 'nsi_weight_%')        AS weight_sum,
       MAX(trend_overdispersion_phi)                      AS trend_phi
FROM analytics.fact_nsi_lsoa;

-- N2. Smoothing by district: prior rate, how much LSOAs move.
--     Expect district rates = S4; shrink weight near 1 for typical LSOAs, lower for small ones.
SELECT local_authority,
       COUNT(*)                                                         AS lsoas,
       ROUND(SUM(crimes) / SUM(population_2024 * 3.0) * 1000, 1)         AS district_rate,
       ROUND(AVG(shrink_weight_crime), 3)                                AS avg_shrink_w,
       MIN(shrink_weight_crime)                                          AS min_shrink_w,
       ROUND(AVG(ABS(crime_rate_smoothed - crime_rate_raw)), 1)          AS avg_abs_rate_change,
       MAX(ABS(crime_rate_smoothed - crime_rate_raw))                    AS max_abs_rate_change
FROM analytics.fact_nsi_lsoa
GROUP BY local_authority
ORDER BY local_authority;

-- N3. Bands by district (population-weighted share helps the narrative).
SELECT nsi_band_sort, nsi_band, local_authority,
       COUNT(*)                                                          AS lsoas,
       SUM(population_2024)                                              AS residents,
       COUNT(*) FILTER (WHERE is_high_footfall_centre)                   AS centres
FROM analytics.fact_nsi_lsoa
GROUP BY nsi_band_sort, nsi_band, local_authority
ORDER BY nsi_band_sort, local_authority;

-- N4. Trend classes. With the over-dispersion correction expect far fewer than
--     the 215 "significant" LSOAs from the uncorrected test.
SELECT trend_class, COUNT(*) AS lsoas,
       ROUND(AVG(trend_pct_change) * 100, 1) AS avg_pct_change
FROM analytics.fact_nsi_lsoa
GROUP BY trend_class
ORDER BY lsoas DESC;

-- N5. Sensitivity: Spearman rank correlation of scenario A with B, C and A-unsmoothed,
--     and overlap of the 50 safest / 50 least safe LSOAs. Expect rho > 0.9 for B and A_raw.
WITH r AS (
    SELECT lsoa_key,
           RANK() OVER (ORDER BY nsi_a DESC) AS rk_a, RANK() OVER (ORDER BY nsi_b DESC) AS rk_b,
           RANK() OVER (ORDER BY nsi_c DESC) AS rk_c, RANK() OVER (ORDER BY nsi_a_raw DESC) AS rk_raw,
           RANK() OVER (ORDER BY nsi_a ASC)  AS lk_a, RANK() OVER (ORDER BY nsi_b ASC)  AS lk_b,
           RANK() OVER (ORDER BY nsi_c ASC)  AS lk_c, RANK() OVER (ORDER BY nsi_a_raw ASC)  AS lk_raw
    FROM analytics.vw_nsi_sensitivity
)
SELECT 'B balanced' AS scenario, ROUND(corr(rk_a, rk_b)::numeric, 3) AS spearman_vs_a,
       COUNT(*) FILTER (WHERE rk_a <= 50 AND rk_b <= 50) AS top50_overlap,
       COUNT(*) FILTER (WHERE lk_a <= 50 AND lk_b <= 50) AS bottom50_overlap FROM r
UNION ALL
SELECT 'C harm only', ROUND(corr(rk_a, rk_c)::numeric, 3),
       COUNT(*) FILTER (WHERE rk_a <= 50 AND rk_c <= 50),
       COUNT(*) FILTER (WHERE lk_a <= 50 AND lk_c <= 50) FROM r
UNION ALL
SELECT 'A unsmoothed', ROUND(corr(rk_a, rk_raw)::numeric, 3),
       COUNT(*) FILTER (WHERE rk_a <= 50 AND rk_raw <= 50),
       COUNT(*) FILTER (WHERE lk_a <= 50 AND lk_raw <= 50) FROM r;

-- N6. External validation: NSI vs the independent IoD 2025 crime domain (higher = more crime).
--     Expect a strong NEGATIVE Spearman (E6 raw rate gave +0.806).
WITH x AS (
    SELECT RANK() OVER (ORDER BY n.nsi_score)           AS rk_nsi,
           RANK() OVER (ORDER BY pr.crime_domain_score) AS rk_iod,
           RANK() OVER (ORDER BY n.crime_rate_raw)      AS rk_raw_rate
    FROM analytics.fact_nsi_lsoa  AS n
    JOIN analytics.vw_lsoa_profile AS pr ON pr.lsoa_key = n.lsoa_key
)
SELECT ROUND(corr(rk_nsi, rk_iod)::numeric, 3)      AS spearman_nsi_vs_iod_crime,
       ROUND(corr(rk_raw_rate, rk_iod)::numeric, 3) AS spearman_raw_rate_vs_iod_crime
FROM x;

-- N7. Safest and least safe 10 LSOAs (sense check; centres should be in the bottom).
(SELECT 'Safest' AS list, nsi_rank, lsoa_code, local_authority, nsi_score, crime_rate_raw, severity_score_smoothed,
        asb_rate_smoothed, trend_class, is_high_footfall_centre
 FROM analytics.fact_nsi_lsoa ORDER BY nsi_score DESC, lsoa_code LIMIT 10)
UNION ALL
(SELECT 'Least safe', nsi_rank, lsoa_code, local_authority, nsi_score, crime_rate_raw, severity_score_smoothed,
        asb_rate_smoothed, trend_class, is_high_footfall_centre
 FROM analytics.fact_nsi_lsoa ORDER BY nsi_score ASC, lsoa_code LIMIT 10);

-- N8. Preview for Phase 7: typical house price and IMD by NSI band.
SELECT n.nsi_band_sort, n.nsi_band, COUNT(*) AS lsoas,
       ROUND(AVG(pr.imd_decile), 1)                                                       AS avg_imd_decile,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vp.house_price_indicator)              AS median_house_price
FROM analytics.fact_nsi_lsoa       AS n
JOIN analytics.vw_lsoa_profile     AS pr ON pr.lsoa_key = n.lsoa_key
LEFT JOIN analytics.vw_lsoa_price  AS vp ON vp.lsoa_key = n.lsoa_key
GROUP BY n.nsi_band_sort, n.nsi_band
ORDER BY n.nsi_band_sort;
