/* =====================================================================
   South Yorkshire Crime Intelligence & Property Suitability Analysis
   PHASE 3 - Step 3: Power BI presentation layer (schema "pbi")
   Run in DBeaver against: CrimeData   (Alt+X)

   Why: Power BI's PostgreSQL connector does not list materialized views,
   so the facts are exposed through ordinary views. The pbi schema is
   also the contract with Power BI: only the columns the report needs,
   no technical ids (crime_id, outcome_row_id), explicit column lists.
   Power BI connects to pbi ONLY.
   ===================================================================== */

CREATE SCHEMA IF NOT EXISTS pbi;
COMMENT ON SCHEMA pbi IS 'Presentation layer: the only schema Power BI imports. Thin views over analytics.';

-- ---------------------------------------------------------------- dimensions
CREATE OR REPLACE VIEW pbi.dim_month AS
SELECT month_key, month_start, month_end, month_index, year, quarter_number, quarter_label,
       year_quarter, month_number, month_name, month_short, year_month, month_label,
       financial_year, financial_year_start, season, season_sort, season_label,
       months_before_latest, is_latest_month, is_last_12_months, is_prior_12_months,
       is_outcome_mature
FROM analytics.dim_month;

CREATE OR REPLACE VIEW pbi.dim_lsoa AS
SELECT lsoa_key, lsoa_code, lsoa_name, local_authority, is_south_yorkshire, is_unknown_member
FROM analytics.dim_lsoa;

-- boundary_wkt is deliberately left out: some polygons exceed Power BI's
-- practical text length; mapping geometry is handled in Phase 9.
CREATE OR REPLACE VIEW pbi.dim_neighbourhood AS
SELECT neighbourhood_key, neighbourhood_id, published_name, display_name, district,
       centre_latitude, centre_longitude, is_unknown_member
FROM analytics.dim_neighbourhood;

CREATE OR REPLACE VIEW pbi.dim_location AS
SELECT location_key, street_name, latitude, longitude, is_station_point,
       lsoa_code, lsoa_name, lsoa_match_method, neighbourhood_name, district, is_unknown_member
FROM analytics.dim_location;

CREATE OR REPLACE VIEW pbi.dim_crime_category AS
SELECT category_key, category_code, category_name, category_group, group_sort_order, is_unknown_member
FROM analytics.dim_crime_category;

CREATE OR REPLACE VIEW pbi.dim_outcome_status AS
SELECT outcome_status_key, outcome_status_name, outcome_code, status_source, outcome_stage,
       stage_sort, outcome_group, is_unknown_member
FROM analytics.dim_outcome_status;

-- ---------------------------------------------------------------- facts
CREATE OR REPLACE VIEW pbi.fact_crime AS
SELECT month_key, lsoa_key, neighbourhood_key, location_key, category_key, outcome_status_key,
       months_to_latest_outcome, has_location, is_btp
FROM analytics.fact_crime;

CREATE OR REPLACE VIEW pbi.fact_outcome AS
SELECT outcome_month_key, crime_month_key, lsoa_key, neighbourhood_key, location_key,
       category_key, outcome_status_key, months_crime_to_outcome, is_latest_event
FROM analytics.fact_outcome;


/* ---------------------------------------------------------------------
   Validation: each pbi view must return the same rows as its source.
   --------------------------------------------------------------------- */
SELECT 'dim_month' AS view_name, (SELECT COUNT(*) FROM pbi.dim_month) AS pbi_rows, (SELECT COUNT(*) FROM analytics.dim_month) AS source_rows
UNION ALL SELECT 'dim_lsoa',           (SELECT COUNT(*) FROM pbi.dim_lsoa),           (SELECT COUNT(*) FROM analytics.dim_lsoa)
UNION ALL SELECT 'dim_neighbourhood',  (SELECT COUNT(*) FROM pbi.dim_neighbourhood),  (SELECT COUNT(*) FROM analytics.dim_neighbourhood)
UNION ALL SELECT 'dim_location',       (SELECT COUNT(*) FROM pbi.dim_location),       (SELECT COUNT(*) FROM analytics.dim_location)
UNION ALL SELECT 'dim_crime_category', (SELECT COUNT(*) FROM pbi.dim_crime_category), (SELECT COUNT(*) FROM analytics.dim_crime_category)
UNION ALL SELECT 'dim_outcome_status', (SELECT COUNT(*) FROM pbi.dim_outcome_status), (SELECT COUNT(*) FROM analytics.dim_outcome_status)
UNION ALL SELECT 'fact_crime',         (SELECT COUNT(*) FROM pbi.fact_crime),         (SELECT COUNT(*) FROM analytics.fact_crime)
UNION ALL SELECT 'fact_outcome',       (SELECT COUNT(*) FROM pbi.fact_outcome),       (SELECT COUNT(*) FROM analytics.fact_outcome);
