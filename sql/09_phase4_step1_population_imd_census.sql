/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 4 - Step 1: population, deprivation (IoD 2025) and Census 2021
   Run in DBeaver against: CrimeData (Alt+X), AFTER load_external_data.py
   Part A: typed staging views over external_raw
   Part B: LSOA -> neighbourhood best-fit lookup (for neighbourhood rates)
   Part C: model objects: fact_population, LSOA profile, pbi views
   Part D: validation (read-only)
   ===================================================================== */


/* =====================================================================
   PART A - TYPED STAGING VIEWS   (T-301 .. T-304)
   ===================================================================== */

-- A1. ONS mid-year population, one row per LSOA x mid-year (2022-2024)
CREATE OR REPLACE VIEW analytics.stg_population_lsoa AS
SELECT
    raw.mid_year::int                                              AS mid_year,
    raw.lsoa_code,
    raw.lsoa_name,
    raw.lad_code,
    raw.lad_name,
    raw.total::int                                                 AS population_total,
    (raw.f_0_15::int  + raw.m_0_15::int)                           AS age_0_15,
    (raw.f_16_29::int + raw.m_16_29::int)                          AS age_16_29,
    (raw.f_30_44::int + raw.m_30_44::int)                          AS age_30_44,
    (raw.f_45_64::int + raw.m_45_64::int)                          AS age_45_64,
    (raw.f_65_plus::int + raw.m_65_plus::int)                      AS age_65_plus
FROM external_raw.ons_population_lsoa AS raw;

-- A2. IoD 2025 (England): ranks 1 = most deprived; deciles 1 = most deprived 10%
CREATE OR REPLACE VIEW analytics.stg_iod2025_lsoa AS
SELECT
    raw.lsoa_code,
    raw.imd_score::numeric          AS imd_score,
    raw.imd_rank::int               AS imd_rank,
    raw.imd_decile::int             AS imd_decile,
    raw.income_decile::int          AS income_decile,
    raw.employment_decile::int      AS employment_decile,
    raw.education_decile::int       AS education_decile,
    raw.health_decile::int          AS health_decile,
    raw.crime_score::numeric        AS crime_domain_score,
    raw.crime_decile::int           AS crime_domain_decile,
    raw.barriers_decile::int        AS barriers_decile,
    raw.living_env_decile::int      AS living_env_decile,
    raw.idaci_score::numeric        AS idaci_score,
    raw.idaci_decile::int           AS idaci_decile,
    raw.cyp_decile::int             AS children_young_people_decile,
    raw.outdoors_decile::int        AS outdoors_env_decile
FROM external_raw.iod2025_lsoa AS raw;

-- A3. Census 2021 household composition + tenure, one row per LSOA
CREATE OR REPLACE VIEW analytics.stg_census_lsoa AS
SELECT
    hc.lsoa_code,
    hc.hh_total::int                                                         AS households_2021,
    (hc.hh_married_dependent_children::int + hc.hh_cohabiting_dependent_children::int
     + hc.hh_lone_parent_dependent_children::int + hc.hh_other_types_dependent_children::int)
                                                                             AS households_with_dependent_children,
    hc.hh_lone_parent_dependent_children::int                               AS lone_parent_dependent_children,
    (hc.hh_one_person_66_plus::int + hc.hh_family_all_66_plus::int)         AS households_all_66_plus,
    tn.ten_owned::int                                                        AS owner_occupied,
    tn.ten_shared_ownership::int                                             AS shared_ownership,
    tn.ten_social_rented::int                                                AS social_rented,
    tn.ten_private_rented::int                                               AS private_rented
FROM external_raw.census_ts003_lsoa AS hc
JOIN external_raw.census_ts054_lsoa AS tn ON tn.lsoa_code = hc.lsoa_code;

-- A4. Median age (mid-2024)
CREATE OR REPLACE VIEW analytics.stg_median_age_lsoa AS
SELECT raw.lsoa_code, NULLIF(raw.median_age_2024, '')::numeric AS median_age_2024
FROM external_raw.ons_median_age_lsoa AS raw;


/* =====================================================================
   PART B - LSOA -> NEIGHBOURHOOD BEST FIT   (T-305)
   LSOAs and police neighbourhoods do not nest, so each LSOA is assigned
   to the neighbourhood holding most of its map points. best_fit_share
   records how clean the fit is (1.00 = all points in one neighbourhood).
   Used only to give neighbourhoods a population denominator.
   ===================================================================== */
CREATE OR REPLACE VIEW analytics.xref_lsoa_neighbourhood AS
WITH points AS (
    SELECT sl.lsoa_code, sl.neighbourhood_id, COUNT(*) AS location_points
    FROM analytics.stg_locations AS sl
    WHERE sl.lsoa_code IS NOT NULL AND sl.neighbourhood_id IS NOT NULL
    GROUP BY sl.lsoa_code, sl.neighbourhood_id
),
ranked AS (
    SELECT p.*,
           SUM(p.location_points) OVER (PARTITION BY p.lsoa_code)                       AS lsoa_points,
           ROW_NUMBER() OVER (PARTITION BY p.lsoa_code
                              ORDER BY p.location_points DESC, p.neighbourhood_id)       AS fit_rank,
           COUNT(*) OVER (PARTITION BY p.lsoa_code)                                      AS neighbourhoods_touched
    FROM points AS p
)
SELECT
    r.lsoa_code,
    r.neighbourhood_id                                          AS best_fit_neighbourhood_id,
    ROUND(r.location_points::numeric / r.lsoa_points, 3)        AS best_fit_share,
    r.neighbourhoods_touched
FROM ranked AS r
WHERE r.fit_rank = 1;


/* =====================================================================
   PART C - MODEL OBJECTS
   ===================================================================== */

-- C1. analytics.vw_lsoa_profile   (T-306)
--     One row per dim_lsoa member with every external attribute.
--     Percentages are stored as fractions (0.25 = 25%).
CREATE OR REPLACE VIEW analytics.vw_lsoa_profile AS
SELECT
    dl.lsoa_key,
    p24.population_total                                                       AS population_2024,
    p24.age_0_15                                                               AS children_0_15_2024,
    ROUND(p24.age_0_15::numeric    / NULLIF(p24.population_total, 0), 4)       AS pct_children_0_15,
    ROUND(p24.age_65_plus::numeric / NULLIF(p24.population_total, 0), 4)       AS pct_aged_65_plus,
    ma.median_age_2024,
    iod.imd_score, iod.imd_rank, iod.imd_decile,
    iod.income_decile, iod.employment_decile, iod.education_decile, iod.health_decile,
    iod.crime_domain_score, iod.crime_domain_decile,
    iod.barriers_decile, iod.living_env_decile, iod.outdoors_env_decile,
    iod.idaci_score, iod.idaci_decile, iod.children_young_people_decile,
    cen.households_2021,
    ROUND(cen.households_with_dependent_children::numeric / NULLIF(cen.households_2021, 0), 4)
                                                                               AS pct_households_dependent_children,
    ROUND(cen.lone_parent_dependent_children::numeric / NULLIF(cen.households_2021, 0), 4)
                                                                               AS pct_lone_parent_households,
    ROUND(cen.owner_occupied::numeric  / NULLIF(cen.households_2021, 0), 4)    AS pct_owner_occupied,
    ROUND(cen.social_rented::numeric   / NULLIF(cen.households_2021, 0), 4)    AS pct_social_rented,
    ROUND(cen.private_rented::numeric  / NULLIF(cen.households_2021, 0), 4)    AS pct_private_rented,
    dn.neighbourhood_key                                                       AS best_fit_neighbourhood_key,
    xn.best_fit_share
FROM analytics.dim_lsoa                    AS dl
LEFT JOIN analytics.stg_population_lsoa    AS p24 ON p24.lsoa_code = dl.lsoa_code AND p24.mid_year = 2024
LEFT JOIN analytics.stg_median_age_lsoa    AS ma  ON ma.lsoa_code  = dl.lsoa_code
LEFT JOIN analytics.stg_iod2025_lsoa       AS iod ON iod.lsoa_code = dl.lsoa_code
LEFT JOIN analytics.stg_census_lsoa        AS cen ON cen.lsoa_code = dl.lsoa_code
LEFT JOIN analytics.xref_lsoa_neighbourhood AS xn ON xn.lsoa_code  = dl.lsoa_code
LEFT JOIN analytics.dim_neighbourhood      AS dn  ON dn.neighbourhood_id = xn.best_fit_neighbourhood_id;

COMMENT ON VIEW analytics.vw_lsoa_profile IS
  'T-306: LSOA attributes from ONS population (mid-2024), IoD 2025, Census 2021, best-fit neighbourhood.';

-- C2. analytics.fact_population   (T-307)  grain: LSOA x mid-year (2022-2024)
CREATE OR REPLACE VIEW analytics.fact_population AS
SELECT
    dl.lsoa_key,
    sp.mid_year,
    sp.population_total,
    sp.age_0_15, sp.age_16_29, sp.age_30_44, sp.age_45_64, sp.age_65_plus
FROM analytics.stg_population_lsoa AS sp
JOIN analytics.dim_lsoa            AS dl ON dl.lsoa_code = sp.lsoa_code;

COMMENT ON VIEW analytics.fact_population IS
  'T-307: resident population by LSOA and mid-year. Rates use mid-2024 by default (closest to the crime window midpoint).';

-- C3. Power BI views (pbi.dim_lsoa is extended; existing columns unchanged)
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
       pr.best_fit_neighbourhood_key, pr.best_fit_share
FROM analytics.dim_lsoa        AS dl
LEFT JOIN analytics.vw_lsoa_profile AS pr ON pr.lsoa_key = dl.lsoa_key;

CREATE OR REPLACE VIEW pbi.fact_population AS
SELECT lsoa_key, mid_year, population_total, age_0_15, age_16_29, age_30_44, age_45_64, age_65_plus
FROM analytics.fact_population;

-- neighbourhood population = sum of its best-fit LSOAs (South Yorkshire only)
CREATE OR REPLACE VIEW pbi.dim_neighbourhood AS
SELECT dn.neighbourhood_key, dn.neighbourhood_id, dn.published_name, dn.display_name, dn.district,
       dn.centre_latitude, dn.centre_longitude, dn.is_unknown_member,
       np.best_fit_lsoas, np.population_2024
FROM analytics.dim_neighbourhood AS dn
LEFT JOIN (
    SELECT pr.best_fit_neighbourhood_key AS neighbourhood_key,
           COUNT(*)                      AS best_fit_lsoas,
           SUM(pr.population_2024)       AS population_2024
    FROM analytics.vw_lsoa_profile AS pr
    JOIN analytics.dim_lsoa        AS dl ON dl.lsoa_key = pr.lsoa_key
    WHERE dl.is_south_yorkshire
    GROUP BY pr.best_fit_neighbourhood_key
) AS np ON np.neighbourhood_key = dn.neighbourhood_key;

-- DQ-23: chronological sort key for Season Label (e.g. Winter 2023/24 -> 202312)
CREATE OR REPLACE VIEW pbi.dim_month AS
SELECT dm.month_key, dm.month_start, dm.month_end, dm.month_index, dm.year, dm.quarter_number, dm.quarter_label,
       dm.year_quarter, dm.month_number, dm.month_name, dm.month_short, dm.year_month, dm.month_label,
       dm.financial_year, dm.financial_year_start, dm.season, dm.season_sort, dm.season_label,
       dm.months_before_latest, dm.is_latest_month, dm.is_last_12_months, dm.is_prior_12_months,
       dm.is_outcome_mature,
       MIN(dm.month_key) OVER (PARTITION BY dm.season_label)   AS season_label_sort
FROM analytics.dim_month AS dm;


/* =====================================================================
   PART D - VALIDATION (read-only)
   ===================================================================== */

-- E1. Match rate of every external source to the LSOAs in the model
SELECT
    dl.is_south_yorkshire,
    COUNT(*) FILTER (WHERE NOT dl.is_unknown_member)                       AS lsoas_in_model,
    COUNT(pr.population_2024)                                              AS with_population,
    COUNT(pr.imd_decile)                                                   AS with_imd,
    COUNT(pr.households_2021)                                              AS with_census,
    COUNT(pr.median_age_2024)                                              AS with_median_age,
    COUNT(pr.best_fit_neighbourhood_key)                                   AS with_best_fit_neighbourhood
FROM analytics.dim_lsoa        AS dl
LEFT JOIN analytics.vw_lsoa_profile AS pr ON pr.lsoa_key = dl.lsoa_key
WHERE NOT dl.is_unknown_member
GROUP BY dl.is_south_yorkshire;

-- E2. Population by local authority and year (South Yorkshire LSOAs)
SELECT dl.local_authority, fp.mid_year, COUNT(*) AS lsoas, SUM(fp.population_total) AS population,
       SUM(fp.age_0_15) AS children_0_15
FROM analytics.fact_population AS fp
JOIN analytics.dim_lsoa        AS dl ON dl.lsoa_key = fp.lsoa_key
WHERE dl.is_south_yorkshire
GROUP BY ROLLUP (dl.local_authority), fp.mid_year
ORDER BY fp.mid_year, dl.local_authority NULLS LAST;

-- E3. IMD 2025 decile distribution of South Yorkshire LSOAs (1 = most deprived 10% in England)
SELECT pr.imd_decile, COUNT(*) AS lsoas, SUM(pr.population_2024) AS population_2024
FROM analytics.vw_lsoa_profile AS pr
JOIN analytics.dim_lsoa        AS dl ON dl.lsoa_key = pr.lsoa_key
WHERE dl.is_south_yorkshire
GROUP BY pr.imd_decile
ORDER BY pr.imd_decile;

-- E4. Quality of the LSOA -> neighbourhood best fit
SELECT
    COUNT(*)                                                        AS sy_lsoas,
    ROUND(AVG(pr.best_fit_share), 3)                                AS avg_best_fit_share,
    MIN(pr.best_fit_share)                                          AS min_best_fit_share,
    COUNT(*) FILTER (WHERE pr.best_fit_share = 1)                   AS lsoas_fully_inside_one,
    COUNT(*) FILTER (WHERE pr.best_fit_share < 0.75)                AS lsoas_below_75pct
FROM analytics.vw_lsoa_profile AS pr
JOIN analytics.dim_lsoa        AS dl ON dl.lsoa_key = pr.lsoa_key
WHERE dl.is_south_yorkshire;

-- E5. Neighbourhood population and crude crime rate (crimes per 1,000 residents per year)
--     36 months of crime / 3 years; mid-2024 population. A first look, not yet a KPI.
SELECT pn.district, pn.display_name, pn.best_fit_lsoas, pn.population_2024,
       COUNT(fc.crime_id)                                                         AS crimes_36m,
       ROUND(COUNT(fc.crime_id) / 3.0 / NULLIF(pn.population_2024, 0) * 1000, 1)   AS crimes_per_1000_per_year
FROM pbi.dim_neighbourhood     AS pn
LEFT JOIN analytics.fact_crime AS fc ON fc.neighbourhood_key = pn.neighbourhood_key
WHERE NOT pn.is_unknown_member
GROUP BY pn.district, pn.display_name, pn.best_fit_lsoas, pn.population_2024
ORDER BY crimes_per_1000_per_year DESC;

-- E6. Independent cross-check: our recorded-crime rate vs the IoD 2025 crime domain
--     (different source, different period). Expect a clear positive correlation.
WITH lsoa_rates AS (
    SELECT dl.lsoa_key,
           COUNT(fc.crime_id) / 3.0 / NULLIF(pr.population_2024, 0) * 1000 AS crime_rate,
           pr.crime_domain_score
    FROM analytics.dim_lsoa        AS dl
    JOIN analytics.vw_lsoa_profile AS pr ON pr.lsoa_key = dl.lsoa_key
    LEFT JOIN analytics.fact_crime AS fc ON fc.lsoa_key = dl.lsoa_key
    WHERE dl.is_south_yorkshire
    GROUP BY dl.lsoa_key, pr.population_2024, pr.crime_domain_score
)
SELECT COUNT(*)                                                    AS lsoas,
       ROUND(corr(crime_rate, crime_domain_score)::numeric, 3)      AS pearson_r,
       ROUND(corr(rk_rate, rk_domain)::numeric, 3)                  AS spearman_rho
FROM (
    SELECT crime_rate, crime_domain_score,
           RANK() OVER (ORDER BY crime_rate)         AS rk_rate,
           RANK() OVER (ORDER BY crime_domain_score) AS rk_domain
    FROM lsoa_rates
) AS ranked;

-- E7. Season label sort check (DQ-23): should list seasons in date order
SELECT DISTINCT season_label, season_label_sort FROM pbi.dim_month ORDER BY season_label_sort;
