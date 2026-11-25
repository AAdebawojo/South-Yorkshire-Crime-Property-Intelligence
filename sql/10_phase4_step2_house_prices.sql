/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 4 - Step 2: house prices (HM Land Registry Price Paid Data)
   Run in DBeaver against: CrimeData (Alt+X), AFTER load_house_prices.py
   Part A: parameters + typed staging
   Part B: LSOA / MSOA price indicators with small-sample fallback
   Part C: Power BI views
   Part D: validation (read-only)
   Contains HM Land Registry data (c) Crown copyright and database right.
   Licensed under the Open Government Licence v3.0.
   ===================================================================== */


/* =====================================================================
   PART A - PARAMETERS + STAGING
   ===================================================================== */
INSERT INTO analytics.cfg_parameter (parameter_name, parameter_value, description) VALUES
 ('price_min_sales_lsoa', 10,
  'Minimum standard residential sales in the window for an LSOA median to be used; otherwise the MSOA median is used (D-12).'),
 ('price_min_sales_msoa', 10,
  'Minimum sales for an MSOA fallback median; below this the price indicator is left blank.')
ON CONFLICT (parameter_name) DO NOTHING;

-- A1. Postcode lookup (compact postcode -> LSOA / MSOA). If a postcode has
--     several rows, prefer a live one (no termination date).
CREATE OR REPLACE VIEW analytics.stg_postcode_lsoa AS
SELECT DISTINCT ON (replace(upper(raw.pcds), ' ', ''))
    replace(upper(raw.pcds), ' ', '')   AS postcode_compact,
    raw.lsoa21cd                        AS lsoa_code,
    raw.msoa21cd                        AS msoa_code,
    NULLIF(raw.msoa21nm, '')            AS msoa_name,
    NULLIF(raw.ladcd, '')               AS lad_code,
    (COALESCE(raw.doterm, '') <> '')    AS is_terminated
FROM external_raw.ons_postcode_lsoa AS raw
WHERE COALESCE(raw.lsoa21cd, '') <> ''
ORDER BY replace(upper(raw.pcds), ' ', ''), (COALESCE(raw.doterm, '') <> ''), raw.source_row;

-- A2. Typed sales, one row per transaction, with analysis flags
CREATE OR REPLACE VIEW analytics.stg_property_sales AS
WITH window_bounds AS (
    SELECT MIN(month) AS first_month, (MAX(month) + INTERVAL '1 month')::date AS end_exclusive
    FROM police.available_months
)
SELECT
    btrim(raw.transaction_id, '{}')                         AS transaction_id,
    raw.price::numeric                                      AS price,
    left(raw.date_of_transfer, 10)::date                    AS sale_date,
    date_trunc('month', left(raw.date_of_transfer, 10)::date)::date AS sale_month,
    upper(btrim(raw.postcode))                              AS postcode,
    replace(upper(raw.postcode), ' ', '')                   AS postcode_compact,
    raw.property_type,
    CASE raw.property_type WHEN 'D' THEN 'Detached' WHEN 'S' THEN 'Semi-detached'
         WHEN 'T' THEN 'Terraced' WHEN 'F' THEN 'Flat/maisonette' ELSE 'Other' END  AS property_type_name,
    (raw.property_type IN ('D', 'S', 'T'))                  AS is_house,
    (raw.old_new = 'Y')                                     AS is_new_build,
    CASE raw.duration WHEN 'F' THEN 'Freehold' WHEN 'L' THEN 'Leasehold' ELSE 'Unknown' END AS tenure,
    raw.ppd_category,
    initcap(raw.district)                                   AS district,
    -- analysis population: standard market sales of homes inside the crime window
    (raw.ppd_category = 'A'
     AND raw.property_type IN ('D', 'S', 'T', 'F')
     AND left(raw.date_of_transfer, 10)::date >= wb.first_month
     AND left(raw.date_of_transfer, 10)::date <  wb.end_exclusive)          AS is_in_scope
FROM external_raw.land_registry_ppd AS raw
CROSS JOIN window_bounds AS wb
WHERE raw.record_status IS DISTINCT FROM 'D';      -- deleted records (monthly-change files) never count


/* =====================================================================
   PART B - PRICE INDICATORS
   ===================================================================== */

-- B1. In-scope sales located to LSOA / MSOA
CREATE OR REPLACE VIEW analytics.vw_property_sales_located AS
SELECT s.*, pl.lsoa_code, pl.msoa_code, pl.msoa_name, pl.is_terminated AS postcode_terminated
FROM analytics.stg_property_sales AS s
LEFT JOIN analytics.stg_postcode_lsoa AS pl ON pl.postcode_compact = s.postcode_compact
WHERE s.is_in_scope;

-- B2. LSOA -> MSOA (from all South Yorkshire postcodes in the lookup)
CREATE OR REPLACE VIEW analytics.xref_lsoa_msoa AS
SELECT DISTINCT ON (pl.lsoa_code) pl.lsoa_code, pl.msoa_code, pl.msoa_name
FROM analytics.stg_postcode_lsoa AS pl
ORDER BY pl.lsoa_code, pl.is_terminated, pl.msoa_code;

-- B3. analytics.vw_lsoa_price   (T-310)  one row per dim_lsoa member
CREATE OR REPLACE VIEW analytics.vw_lsoa_price AS
WITH params AS (
    SELECT
        MAX(parameter_value) FILTER (WHERE parameter_name = 'price_min_sales_lsoa') AS min_lsoa,
        MAX(parameter_value) FILTER (WHERE parameter_name = 'price_min_sales_msoa') AS min_msoa
    FROM analytics.cfg_parameter
),
lsoa_stats AS (
    SELECT lsoa_code,
           COUNT(*)                                                                   AS sales,
           COUNT(*) FILTER (WHERE is_house)                                           AS house_sales,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)                          AS median_all,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) FILTER (WHERE is_house)  AS median_houses,
           PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price)                         AS lower_quartile_all
    FROM analytics.vw_property_sales_located
    WHERE lsoa_code IS NOT NULL
    GROUP BY lsoa_code
),
msoa_stats AS (
    SELECT msoa_code,
           COUNT(*)                                                                   AS sales,
           COUNT(*) FILTER (WHERE is_house)                                           AS house_sales,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)                          AS median_all,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) FILTER (WHERE is_house)  AS median_houses
    FROM analytics.vw_property_sales_located
    WHERE msoa_code IS NOT NULL
    GROUP BY msoa_code
)
SELECT
    dl.lsoa_key,
    xm.msoa_code,
    xm.msoa_name,
    COALESCE(ls.sales, 0)                                                     AS sales_count,
    COALESCE(ls.house_sales, 0)                                               AS house_sales_count,
    ROUND(ls.median_all::numeric, 0)                                          AS lsoa_median_price,
    ROUND(ms.median_all::numeric, 0)                                          AS msoa_median_price,
    -- price indicator: LSOA median if enough sales, else MSOA median, else blank
    ROUND(CASE WHEN COALESCE(ls.sales, 0) >= p.min_lsoa THEN ls.median_all
               WHEN COALESCE(ms.sales, 0) >= p.min_msoa THEN ms.median_all END::numeric, 0)
                                                                              AS price_indicator,
    CASE WHEN COALESCE(ls.sales, 0) >= p.min_lsoa THEN 'LSOA median'
         WHEN COALESCE(ms.sales, 0) >= p.min_msoa THEN 'MSOA fallback'
         ELSE 'Insufficient sales' END                                        AS price_method,
    ROUND(CASE WHEN COALESCE(ls.house_sales, 0) >= p.min_lsoa THEN ls.median_houses
               WHEN COALESCE(ms.house_sales, 0) >= p.min_msoa THEN ms.median_houses END::numeric, 0)
                                                                              AS house_price_indicator,
    CASE WHEN COALESCE(ls.house_sales, 0) >= p.min_lsoa THEN 'LSOA median'
         WHEN COALESCE(ms.house_sales, 0) >= p.min_msoa THEN 'MSOA fallback'
         ELSE 'Insufficient sales' END                                        AS house_price_method,
    ROUND(ls.lower_quartile_all::numeric, 0)                                  AS lsoa_lower_quartile_price
FROM analytics.dim_lsoa         AS dl
CROSS JOIN params               AS p
LEFT JOIN analytics.xref_lsoa_msoa AS xm ON xm.lsoa_code = dl.lsoa_code
LEFT JOIN lsoa_stats            AS ls ON ls.lsoa_code = dl.lsoa_code
LEFT JOIN msoa_stats            AS ms ON ms.msoa_code = xm.msoa_code
WHERE NOT dl.is_unknown_member;

COMMENT ON VIEW analytics.vw_lsoa_price IS
  'T-310: pooled median price (window = crime window) by LSOA with MSOA fallback when sales < threshold.';

-- B4. Sales fact (one row per in-scope sale), keyed to the model
CREATE OR REPLACE VIEW analytics.fact_property_sale AS
SELECT
    COALESCE(dl.lsoa_key, -1)                                                       AS lsoa_key,
    (EXTRACT(YEAR FROM s.sale_month) * 100 + EXTRACT(MONTH FROM s.sale_month))::int AS month_key,
    s.price,
    s.property_type_name,
    s.is_house,
    s.is_new_build,
    s.tenure
FROM analytics.vw_property_sales_located AS s
LEFT JOIN analytics.dim_lsoa AS dl ON dl.lsoa_code = s.lsoa_code;


/* =====================================================================
   PART C - POWER BI VIEWS
   pbi.dim_lsoa is extended (new columns appended at the end)
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
       vp.lsoa_lower_quartile_price
FROM analytics.dim_lsoa             AS dl
LEFT JOIN analytics.vw_lsoa_profile AS pr ON pr.lsoa_key = dl.lsoa_key
LEFT JOIN analytics.vw_lsoa_price   AS vp ON vp.lsoa_key = dl.lsoa_key;

CREATE OR REPLACE VIEW pbi.fact_property_sale AS
SELECT lsoa_key, month_key, price, property_type_name, is_house, is_new_build, tenure
FROM analytics.fact_property_sale;


/* =====================================================================
   PART D - VALIDATION (read-only)
   ===================================================================== */

-- H1. Raw load and scope funnel
SELECT
    (SELECT COUNT(*) FROM external_raw.land_registry_ppd)                           AS raw_sy_sales_all_years,
    (SELECT COUNT(*) FROM analytics.stg_property_sales WHERE is_in_scope)           AS in_scope_sales,
    (SELECT COUNT(*) FROM analytics.stg_property_sales
      WHERE ppd_category = 'B')                                                     AS category_b_excluded,
    (SELECT MIN(sale_date) FROM analytics.stg_property_sales WHERE is_in_scope)     AS first_sale,
    (SELECT MAX(sale_date) FROM analytics.stg_property_sales WHERE is_in_scope)     AS last_sale,
    (SELECT COUNT(*) FROM external_raw.ons_postcode_lsoa)                           AS lookup_rows_kept;

-- H2. Postcode -> LSOA match rate for in-scope sales (expect ~99%+)
SELECT
    COUNT(*)                                                         AS in_scope_sales,
    COUNT(lsoa_code)                                                 AS matched_to_lsoa,
    ROUND(100.0 * COUNT(lsoa_code) / NULLIF(COUNT(*), 0), 2)         AS pct_matched,
    COUNT(*) FILTER (WHERE postcode_compact = '')                    AS no_postcode,
    COUNT(*) FILTER (WHERE postcode_terminated)                      AS matched_via_terminated_postcode
FROM analytics.vw_property_sales_located;

-- H3. Where matched sales land: South Yorkshire LSOAs vs elsewhere
SELECT COALESCE(dl.is_south_yorkshire::text, 'LSOA not in model') AS in_model_sy, COUNT(*) AS sales
FROM analytics.vw_property_sales_located AS s
LEFT JOIN analytics.dim_lsoa AS dl ON dl.lsoa_code = s.lsoa_code
WHERE s.lsoa_code IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;

-- H4. How many South Yorkshire LSOAs get each price method
SELECT vp.price_method, COUNT(*) AS lsoas,
       MIN(vp.sales_count) AS min_sales, MAX(vp.sales_count) AS max_sales
FROM analytics.vw_lsoa_price AS vp
JOIN analytics.dim_lsoa      AS dl ON dl.lsoa_key = vp.lsoa_key
WHERE dl.is_south_yorkshire
GROUP BY vp.price_method ORDER BY lsoas DESC;

-- H5. Distribution of sales per South Yorkshire LSOA
SELECT
    CASE WHEN sales_count = 0 THEN '0' WHEN sales_count < 10 THEN '1-9'
         WHEN sales_count < 25 THEN '10-24' WHEN sales_count < 50 THEN '25-49'
         WHEN sales_count < 100 THEN '50-99' ELSE '100+' END AS sales_band,
    COUNT(*) AS lsoas
FROM analytics.vw_lsoa_price AS vp
JOIN analytics.dim_lsoa      AS dl ON dl.lsoa_key = vp.lsoa_key
WHERE dl.is_south_yorkshire
GROUP BY 1 ORDER BY MIN(sales_count);

-- H6. Price summary by local authority (pooled window; all homes and houses only)
SELECT dl.local_authority,
       COUNT(*)                                                                              AS sales,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price)::numeric, 0)              AS median_price,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.is_house))::numeric, 0)
                                                                                             AS median_house_price,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.property_type_name = 'Flat/maisonette') / COUNT(*), 1) AS pct_flats
FROM analytics.vw_property_sales_located AS s
JOIN analytics.dim_lsoa AS dl ON dl.lsoa_code = s.lsoa_code
WHERE dl.is_south_yorkshire
GROUP BY ROLLUP (dl.local_authority)
ORDER BY dl.local_authority NULLS LAST;

-- H7. Spread of LSOA price indicators (South Yorkshire)
SELECT
    COUNT(price_indicator)                                                          AS lsoas_with_price,
    MIN(price_indicator)                                                            AS min_price,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price_indicator)::numeric, 0) AS p25,
    ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY price_indicator)::numeric, 0) AS median,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price_indicator)::numeric, 0) AS p75,
    MAX(price_indicator)                                                            AS max_price
FROM analytics.vw_lsoa_price AS vp
JOIN analytics.dim_lsoa      AS dl ON dl.lsoa_key = vp.lsoa_key
WHERE dl.is_south_yorkshire;
