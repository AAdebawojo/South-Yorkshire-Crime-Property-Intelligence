# South Yorkshire Crime Intelligence & Property Suitability Analysis
## Data dictionary and semantic model specification (Phase 3)

_Version 1.5, 12 Nov 2026 (Phase 7 Family Suitability Index added). v1.4: Phase 6 Safety Index. v1.3: Phase 5 KPIs. v1.2, 11 Nov 2026 (Phase 4 complete: house prices added; v1.1 added: Population table, LSOA enrichment, neighbourhood population)._ _v1.0: Source of truth for the Power BI model. Phase 4 adds population, deprivation, price and census objects._

---

## 1. Layers

| Schema | Purpose | Used by Power BI |
|---|---|---|
| `police` | API data as loaded (never modified) | No |
| `police_bulk` | Bulk CSVs as loaded (never modified) | No |
| `analytics` | Staging, configuration, dimensions, facts (materialized views) | No |
| `pbi` | Thin views over `analytics` with only the columns the report needs | **Yes: the only schema imported** |

Power BI's PostgreSQL connector does not list materialized views, which is one reason the `pbi` layer exists. Storage mode: **Import**. About 930k fact rows across both facts; the model is expected to stay well under 100 MB.

## 2. Tables and grain

| Table | Type | Grain | Rows (validated) | Key |
|---|---|---|---:|---|
| fact_crime | Fact | One recorded crime (duplicates excluded) | 527,597 | — (no technical id imported) |
| fact_outcome | Fact | One outcome event linked to a crime | 402,633 | — |
| dim_month | Dimension | One calendar month the API holds | 36 | month_key (YYYYMM) |
| dim_lsoa | Dimension | One LSOA (2021 boundaries) + Unknown | 865 | lsoa_key |
| dim_neighbourhood | Dimension | One police neighbourhood + "No location" | 19 | neighbourhood_key |
| dim_location | Dimension | One anonymised map point + "No location" | 18,310 | location_key |
| dim_crime_category | Dimension | One police crime category + Unknown | 15 | category_key |
| dim_outcome_status | Dimension | One outcome status + Unknown | 18 | outcome_status_key |

## 3. Column dictionary

Visibility: **Hide** = technical, hidden from report authors; **Show** = available in the field list. Friendly names are the Power BI display names.

### fact_crime

| Column | Type | Friendly name | Description | Visibility |
|---|---|---|---|---|
| month_key | int | Month Key | Crime month (YYYYMM) → dim_month | Hide |
| lsoa_key | int | LSOA Key | → dim_lsoa; −1 = no location or unassigned LSOA | Hide |
| neighbourhood_key | int | Neighbourhood Key | → dim_neighbourhood; −1 = no location | Hide |
| location_key | int | Location Key | → dim_location; −1 = no location | Hide |
| category_key | int | Category Key | → dim_crime_category | Hide |
| outcome_status_key | int | Outcome Status Key | Latest status → dim_outcome_status | Hide |
| months_to_latest_outcome | int | Months to Latest Outcome | Whole months from crime to its latest status; blank for ASB | Hide (used in measures) |
| has_location | bool | Has Location | Crime has a map point | Hide (used in measures) |
| is_btp | bool | Is BTP | Recorded by British Transport Police at a station | Hide (used in measures) |

### fact_outcome

| Column | Type | Friendly name | Description | Visibility |
|---|---|---|---|---|
| outcome_month_key | int | Outcome Month Key | Month the outcome was recorded → dim_month (**active**) | Hide |
| crime_month_key | int | Crime Month Key | Month of the underlying crime → dim_month (**inactive**; use `USERELATIONSHIP`) | Hide |
| lsoa_key, neighbourhood_key, location_key, category_key | int | — | Inherited from the linked crime | Hide |
| outcome_status_key | int | Outcome Status Key | Status of this event → dim_outcome_status | Hide |
| months_crime_to_outcome | int | Months Crime to Outcome | Lag in whole months (0–35) | Hide (used in measures) |
| is_latest_event | bool | Is Latest Event | Latest event for its crime | Hide (used in measures) |

### dim_month

| Column | Type | Friendly name | Description | Sort by | Visibility |
|---|---|---|---|---|---|
| month_key | int | Month Key | YYYYMM, relationship key | — | Hide |
| month_start | date | Month Start | First day of the month; continuous chart axis | — | Show |
| month_end | date | Month End | Last day of the month | — | Hide |
| month_index | int | Month Index | 1 = Oct 2023 … 36 = Sep 2026, calendar-based; drives MoM / YoY / rolling DAX | — | Hide |
| year | int | Year | Calendar year | — | Show |
| quarter_number / quarter_label / year_quarter | int / text | Quarter No / Quarter / Year Quarter | e.g. 3 / Q3 / 2024 Q3 | year_quarter by month_key | Show |
| month_number / month_name / month_short | int / text | Month No / Month / Month Short | e.g. 1 / January / Jan | month_name and month_short by month_number | Show |
| year_month / month_label | text | Year Month / Month Label | 2024-01 / Jan 2024 | both by month_key | Show |
| financial_year / financial_year_start | text / int | Financial Year / FY Start | FY 2024/25 (Apr–Mar) | financial_year by financial_year_start | Show / Hide |
| season / season_sort / season_label | text / int / text | Season / Season Sort / Season Label | Met Office seasons; Winter spans Dec–Feb | season by season_sort; season_label by month_key | Show / Hide / Show |
| months_before_latest | int | Months Before Latest | 0 = latest month | — | Hide |
| is_latest_month, is_last_12_months, is_prior_12_months | bool | — | Rolling-window flags | — | Show (slicers/filters) |
| is_outcome_mature | bool | Outcome Mature | True when the crime month is at least 6 months before the latest month (cfg_parameter) | — | Show |

**Not marked as a date table** (decision D-05). month_start is not contiguous by day, and built-in time intelligence is not used; MoM, YoY and rolling measures use month_index. Auto date/time must be **off**.

### dim_lsoa

| Column | Type | Friendly name | Description | Visibility |
|---|---|---|---|---|
| lsoa_key | int | LSOA Key | Surrogate key; −1 = Unknown | Hide |
| lsoa_code | text | LSOA Code | ONS 2021 LSOA code, e.g. E01007321 | Show |
| lsoa_name | text | LSOA Name | e.g. "Sheffield 012A" | Show |
| local_authority | text | Local Authority | Barnsley / Doncaster / Rotherham / Sheffield (+4 out-of-county) | Show |
| is_south_yorkshire | bool | In South Yorkshire | False for the 4 out-of-county LSOAs and Unknown; filter out of rankings | Show |
| is_unknown_member | bool | Is Unknown | The −1 member | Hide |

Phase 4 adds: population (total, children 0–15), IMD 2025 deciles (overall + domains), median price and sales count, census household composition and tenure.

### dim_neighbourhood

| Column | Type | Friendly name | Description | Visibility |
|---|---|---|---|---|
| neighbourhood_key | int | Neighbourhood Key | −1 = No location | Hide |
| neighbourhood_id | text | Neighbourhood Code | Police code, e.g. KC | Hide |
| published_name | text | Published Name | Name as published by the police | Hide |
| display_name | text | Neighbourhood | Cleaned name (DQ-21) | Show |
| district | text | District | Barnsley / Doncaster / Rotherham / Sheffield | Show |
| centre_latitude / centre_longitude | decimal | Centre Latitude / Longitude | Police-published centre; data category Latitude / Longitude | Show |
| is_unknown_member | bool | Is Unknown | — | Hide |

### dim_location

| Column | Type | Friendly name | Description | Visibility |
|---|---|---|---|---|
| location_key | int | Location Key | −1 = No location | Hide |
| street_name | text | Street | "On or near …" (anonymised) or station name | Show |
| latitude / longitude | decimal | Latitude / Longitude | Anonymised snap point; data category Latitude / Longitude | Show |
| is_station_point | bool | Is Station | BTP station point | Show |
| lsoa_code, lsoa_name | text | — | For map tooltips | Show |
| lsoa_match_method | text | LSOA Match Method | exact_coordinate / nearest_point_fallback / unassigned | Hide |
| neighbourhood_name, district | text | — | For map tooltips | Show |
| is_unknown_member | bool | Is Unknown | — | Hide |

### dim_crime_category

| Column | Type | Friendly name | Description | Sort by | Visibility |
|---|---|---|---|---|---|
| category_key | int | Category Key | — | — | Hide |
| category_code | text | Category Code | Police code | — | Hide |
| category_name | text | Crime Category | 14 police categories | — | Show |
| category_group | text | Crime Group | 11 analytical groups (cfg_crime_category) | group_sort_order | Show |
| group_sort_order | int | — | — | — | Hide |
| is_unknown_member | bool | — | — | — | Hide |

### dim_outcome_status

| Column | Type | Friendly name | Description | Sort by | Visibility |
|---|---|---|---|---|---|
| outcome_status_key | int | — | — | — | Hide |
| outcome_status_name | text | Outcome Status | 17 statuses + Unknown | — | Show |
| outcome_code | text | — | Police code (misleading on its own; DQ-09) | — | Hide |
| status_source | text | Status Source | reference outcome / status-only label / derived | — | Hide |
| outcome_stage | text | Outcome Stage | Concluded / Pending / Unknown / Not applicable | stage_sort | Show |
| stage_sort | int | — | — | — | Hide |
| outcome_group | text | Outcome Group | Positive / negative grouping, defined in Phase 5 | — | Show |
| is_unknown_member | bool | — | — | — | Hide |

## 4. Relationships

All relationships: **many-to-one (fact → dimension), single filter direction (dimension filters fact), referential integrity assumed = off** (the −1 members make it true, but leaving it off is the safe default for Import mode).

| # | From (many) | To (one) | Active | Notes |
|---|---|---|---|---|
| R1 | fact_crime[month_key] | dim_month[month_key] | Yes | |
| R2 | fact_crime[lsoa_key] | dim_lsoa[lsoa_key] | Yes | |
| R3 | fact_crime[neighbourhood_key] | dim_neighbourhood[neighbourhood_key] | Yes | |
| R4 | fact_crime[location_key] | dim_location[location_key] | Yes | |
| R5 | fact_crime[category_key] | dim_crime_category[category_key] | Yes | |
| R6 | fact_crime[outcome_status_key] | dim_outcome_status[outcome_status_key] | Yes | Latest status |
| R7 | fact_outcome[outcome_month_key] | dim_month[month_key] | **Yes** | When the outcome was recorded |
| R8 | fact_outcome[crime_month_key] | dim_month[month_key] | **No** | Role-playing date; activate with `USERELATIONSHIP` |
| R9 | fact_outcome[lsoa_key] | dim_lsoa[lsoa_key] | Yes | |
| R10 | fact_outcome[neighbourhood_key] | dim_neighbourhood[neighbourhood_key] | Yes | |
| R11 | fact_outcome[location_key] | dim_location[location_key] | Yes | |
| R12 | fact_outcome[category_key] | dim_crime_category[category_key] | Yes | |
| R13 | fact_outcome[outcome_status_key] | dim_outcome_status[outcome_status_key] | Yes | Event status |

No fact-to-fact relationship, no bidirectional filters, no many-to-many. LSOA and neighbourhood are deliberately **separate** dimensions because they do not nest (e.g. Mexborough station: Rotherham North neighbourhood, Doncaster LSOA).

## 5. Hierarchies

| Table | Hierarchy | Levels |
|---|---|---|
| dim_month | Calendar | Year → Year Quarter → Month Label |
| dim_month | Financial | Financial Year → Month Label |
| dim_lsoa | LSOA Geography | Local Authority → LSOA Name |
| dim_neighbourhood | Policing Geography | District → Neighbourhood |
| dim_crime_category | Crime Type | Crime Group → Crime Category |

## 6. Model settings

- Auto date/time: **off** (File → Options → Current file → Data load).
- A dedicated **_Measures** table holds every measure, with display folders (Crime, Trend, Outcomes, Index, Data Quality).
- Implicit measures discouraged: no summarising of key or flag columns.
- Formats: counts `#,##0`; percentages `0.0%`; rates `#,##0.0`.
- Data categories: latitude / longitude columns set to Latitude / Longitude; local_authority = County; lsoa_name = Place.


---

## 7. Phase 4 additions (v1.1)

### Population (fact): grain LSOA × mid-year (2022, 2023, 2024)

| Column | Friendly name | Description | Visibility |
|---|---|---|---|
| lsoa_key | LSOA Key | → LSOA (R14, many-to-one, single direction) | Hide |
| mid_year | Mid Year | ONS mid-year (30 June) | Show |
| population_total | Population | Usual residents | Hide (use the [Population] measure) |
| age_0_15 … age_65_plus | Age 0-15 / 16-29 / 30-44 / 45-64 / 65+ | Female + male combined | Hide |

### LSOA: new attributes (folders)

| Folder | Columns |
|---|---|
| Population | Population 2024, Children 0-15 2024, % Children 0-15, % Aged 65+, Median Age 2024 |
| Deprivation (IoD 2025) | IMD Score, IMD Rank (1 = most deprived of 33,755), IMD Decile (1 = most deprived 10%), Income / Employment / Education / Health / Barriers to Housing / Living Environment / Outdoor Environment Deciles, IDACI Score and Decile, Children & Young People Education Decile, IoD Crime Domain Score and Decile (**cross-check only; never used in the indices, D-11**) |
| Census 2021 | Households 2021, % Households with Dependent Children, % Lone Parent Households, % Owner Occupied, % Social Rented, % Private Rented |
| (hidden) | Best-fit Neighbourhood Key, Best-fit Share |

### Neighbourhood: new attributes
Best-fit LSOAs; Population 2024 = sum of LSOAs whose best fit is the neighbourhood (an approximation, because LSOAs and neighbourhoods don't nest; 782 of 860 LSOAs fit 100%).

### Month: new attribute
Season Label Sort (hidden): sort key for Season Label.

### Measures added
| Measure | DAX | Notes |
|---|---|---|
| Population | Latest mid-year SUM(Population[Population]) | Responds to LSOA filters only |
| Children 0-15 | Latest mid-year SUM(Population[Age 0-15]) | |

### Relationship
| # | From | To | Active |
|---|---|---|---|
| R14 | Population[LSOA Key] (many) | LSOA[LSOA Key] (one) | Yes |


## 8. Phase 4 step 2 additions (v1.2): house prices

### Property Sale (fact): grain = one standard residential sale (Land Registry category A; detached, semi-detached, terraced, flat), Oct 2023 – Sep 2026, located to an LSOA by postcode

| Column | Friendly name | Description | Visibility |
|---|---|---|---|
| lsoa_key | LSOA Key | → LSOA (R15); −1 = postcode not matched (2 sales) | Hide |
| month_key | Month Key | Month of sale → Month (R16) | Hide |
| price | Price | Sale price (£) | Hide (use the measures) |
| property_type_name | Property Type | Detached / Semi-detached / Terraced / Flat/maisonette | Show |
| is_house | Is House | Detached, semi-detached or terraced | Show |
| is_new_build | Is New Build | | Show |
| tenure | Tenure | Freehold / Leasehold | Show |

### LSOA: House Prices folder
MSOA Name, Sales Count, House Sales Count, **Typical Price** (pooled median; LSOA median if ≥10 sales, otherwise MSOA median), Price Method, **Typical House Price** (houses only, same rule), House Price Method, Lower Quartile Price. MSOA Code is hidden.

### Measures
| Measure | DAX | Notes |
|---|---|---|
| Sales Count | COUNTROWS('Property Sale') | |
| Median Sale Price | MEDIAN('Property Sale'[Price]) | Read alongside Sales Count |
| Median House Price | [Median Sale Price] with Is House = TRUE | |
| % Flats | Flat/maisonette sales ÷ Sales Count | |

### Relationships
| # | From (many) | To (one) | Active |
|---|---|---|---|
| R15 | Property Sale[LSOA Key] | LSOA[LSOA Key] | Yes |
| R16 | Property Sale[Month Key] | Month[Month Key] | Yes |

Attribution required wherever prices are shown: *Contains HM Land Registry data © Crown copyright and database right. Licensed under the Open Government Licence v3.0.*


## 9. Phase 5 additions (v1.3): severity, outcomes and KPI measures

### New columns
| Table | Column | Description |
|---|---|---|
| Crime Category | Is ASB | TRUE for anti-social behaviour (separate Safety Index component) |
| Crime Category | Severity Weight | ONS CSS-derived weight in days of custody (cfg_crime_severity_weight, T-212); blank for ASB |
| Outcome Status | Outcome Group | 8 groups, sorted by Outcome Group Sort (hidden) |
| Outcome Status | Is Positive Outcome | Charged / summonsed or Out-of-court resolution (D-14) |

### Measures (all in _Measures; validated against SQL S3–S8)
| Folder | Measure | Definition | Validated value (all South Yorkshire, 36 months) |
|---|---|---|---|
| Crime | Crimes (excl. ASB) | Total Crimes where Is ASB = FALSE | 449,049 |
| Crime | ASB Incidents | Total Crimes where Is ASB = TRUE | 78,548 |
| Crime | % of Crimes / % of Severity | Category share within current geography/period | Violence 40.0% / 61.3% |
| Crime Rates | Months in Period | COUNTROWS(Month) | 36 |
| Crime Rates | Resident Population | South Yorkshire LSOA mid-2024 population; neighbourhood population when only Neighbourhood is filtered | 1,430,623 |
| Crime Rates | Crime Rate per 1,000 | crimes ÷ months × 12 ÷ population × 1,000 | 104.6 (Doncaster 115.2, Sheffield 95.9, Barnsley 93.7, Rotherham 89.9) |
| Crime Rates | ASB Rate per 1,000 | same, ASB | 18.3 |
| Crime Rates | Severity Days | Σ category weight × crimes | — |
| Crime Rates | Severity Score | annual severity days ÷ population (ONS CSS units) | 20.57 (ONS published 20.58) |
| Crime Rates | Avg Severity per Crime | Severity Days ÷ Crimes (excl. ASB) | 196.6 |
| Trends | Crimes Previous Month, MoM % Change | Month Index − 1 (single month) | Sep 2026: 12,173 vs 13,090, −7.0% |
| Trends | Crimes Same Month Last Year, YoY % Change | Month Index − 12 | Sep 2026: +1.7% |
| Trends | Rolling 3-Month Avg / Rolling 12-Month Avg | Blank until 3 / 12 months exist | Sep 2026: 12,950 / 12,368 |
| Trends | Crimes Last 12 Months, Crimes Prior 12 Months, Last 12 vs Prior 12 % | is_last_12 / is_prior_12 flags | 148,415 vs 147,522, +0.6% |
| Trends | ASB Last 12 vs Prior 12 % | | +3.0% |
| Trends | Trend Z-Score | (L − P) ÷ √(L + P), Poisson | +1.64 |
| Trends | Trend Classification | Rising / Falling only if \|z\| ≥ 1.96 and change ≥ 5%; < 20 crimes = Too few crimes | Stable (Rotherham Rising, z 8.8, +8.2%) |
| Seasonality | Avg Monthly Crimes (Complete Seasons) | Average month, seasons with all 3 months only (DQ-24) | Spring 12,767; Summer 12,953; Autumn 12,540; Winter 11,590 |
| Seasonality | Seasonal Index | Season average ÷ overall average | Summer 1.04, Winter 0.93 |
| Outcomes | Crimes in Mature Months | Crimes (excl. ASB), Outcome Mature = TRUE, Outcome Status filters removed | 372,085 |
| Outcomes | Positive Outcomes / **Positive Outcome Rate** | Positive ÷ mature crimes (headline) | 12.5% (charge or resolution, not conviction: DQ-27) |
| Outcomes | Outcome Group Share | Share of mature crimes per group | No suspect 82.3%; Charged 8.8%; OOC 3.8% |
| Outcomes | Unknown Outcome % / Pending Outcome % | Context for the headline | 3.6% / 0.0% |
| Outcomes | Outcome Completeness % | Concluded share, all months (by crime month shows the lag) | 86.0% overall; latest month 49.6% |
| Outcomes | Median Months to Outcome / to Positive Outcome | MEDIAN of Months to Latest Outcome, mature months | Charged 6; OOC 0; Unknown 4 |


## 10. Phase 6 additions (v1.4): Neighbourhood Safety Index

Source: analytics.fact_nsi_lsoa (materialized view, refresh with `CALL analytics.sp_refresh_nsi();`), surfaced through pbi.dim_lsoa.

### LSOA: Safety Index (NSI) folder
| Column | Description |
|---|---|
| NSI Score | 0–100, higher = safer, relative to the 860 South Yorkshire LSOAs. 0.5 × Severity + 0.2 × Crime Rate + 0.2 × ASB + 0.1 × Trend percentiles (D-15) |
| NSI Band | Very high (≥80) / High (60–80) / Moderate (40–60) / Low (20–40) / Very low safety (<20); sorted by NSI Band Sort (hidden) |
| NSI Rank / NSI Rank in District | 1 = safest of 860 / in its local authority |
| Trend | Rising / Falling / Stable / Too few crimes (over-dispersion corrected, ≥5%) |
| High-Footfall Centre | Raw crime rate > 3 × SY LSOA median (29 LSOAs); score kept, flagged (DQ-18) |
| Components\Severity / Crime Rate / ASB / Trend Percentile | 0 = least safe, 100 = safest, mid-ranks for ties |
| Inputs\Crime Rate, Severity Score, ASB Rate (Raw and Smoothed), Trend Z (Adjusted), Trend % Change, Smoothing Weight (hidden) | Annualised, mid-2024 population; smoothed = empirical Bayes towards the district |

### What-if tables (calculated, GENERATESERIES(0,100,5))
NSI Weight Severity / Crime Rate / ASB / Trend, each with a measure returning the selected value (defaults 50 / 20 / 20 / 10). Use as slicers on the sensitivity page.

### Measures (folder Safety Index)
| Measure | Definition | Validated |
|---|---|---|
| NSI | Population-weighted mean of LSOA NSI Score (SY LSOAs); for a neighbourhood, its best-fit LSOAs | South Yorkshire 49.1; Sheffield 51.5, Rotherham 51.2, Barnsley 48.8, Doncaster 43.4; neighbourhoods 24.3 (Barnsley Central) to 66.9 (Sheffield North West) |
| NSI Band (Area) | Band of [NSI] | all four districts Moderate |
| % Residents in Safer LSOAs | Residents in LSOAs with NSI ≥ 60 ÷ residents | SY 36.0%; Sheffield 39.4%, Rotherham 38.1%, Barnsley 33.7%, Doncaster 29.8% |
| LSOAs in Context | SY LSOAs in context | 860; band × district counts = N3 |
| NSI (Custom Weights) | Same, from the what-if weights (normalised) | at defaults 49.14 = [NSI] |
| NSI Rank (Custom Weights) | RANKX over SY LSOAs | defaults: same top 50; within 5 places (rounding ties) |
| Rank Change (Custom vs Default) | NSI Rank − custom rank | weights B: top-50 overlap 46, bottom-50 47 (= N5), max move 85 places |


## 11. Phase 7 additions (v1.5): Family Suitability Index

Source: analytics.fact_fsi_lsoa (refresh with `CALL analytics.sp_refresh_fsi();` after sp_refresh_nsi) and analytics.fn_fsi(budget, weights) for SQL scenarios. Budget-dependent parts (affordability, eligibility, FSI) are calculated live in DAX.

### LSOA: Family Suitability (FSI) folder
| Column | Description |
|---|---|
| Family House Price | Typical house price (houses only; all-property fallback, used by 0 LSOAs) |
| Components\Safety Percentile (FSI) | Percentile of NSI Score |
| Components\Schools Percentile | Percentile of IoD CYP education decile (schools proxy) |
| Components\Family Community Percentile | Percentile of % households with dependent children |
| Components\Environment Percentile, Environment Decile (Avg) | Mean of IoD Living and Outdoor Environment deciles, as a percentile |
| Value for Money\NSI Expected for Price | NSI predicted from ln(price): +27 NSI points per price doubling, R² 0.378 |
| Value for Money\Value for Money (NSI vs Price) | NSI − expected; positive = safer than the price suggests |

### What-if tables
FSI Budget (£100,000–£500,000 step £10,000, default £250,000) and FSI Weight Safety / Affordability / Schools / Family / Environment (0–100 step 5, defaults 35/20/20/10/15), each with a value measure.

### Measures (folder Family Suitability)
| Measure | Definition | Validated at defaults |
|---|---|---|
| Affordability Score | Single LSOA: MIN(100, 200 × (1 − price ÷ budget)); blank over budget | Doncaster 038D 72.8 (= F3) |
| FSI Status | Qualifies / High-footfall centre / Over budget / No price / Outside South Yorkshire | |
| FSI | Single LSOA: weighted score (blank if excluded). Area: population-weighted mean over qualifying LSOAs; neighbourhood = best-fit LSOAs | 660 scored, 11.4–78.3, mean 49.4 (= F1); #1 Barnsley 024D 78.3 (= F3); SY population-weighted 49.0; neighbourhoods 31.4 (Sheffield City Centre) to 54.2 (Rotherham South) |
| FSI Rank | Rank among qualifying SY LSOAs (1 = best) | top 50 by district: Doncaster 19, Rotherham 17, Sheffield 9, Barnsley 5 (= F4) |
| LSOAs Within Budget / LSOAs Over Budget | Qualifying / over-budget non-centre SY LSOAs | 660 / 171; by budget £150k–£400k: 216 / 492 / 660 / 736 / 790, top FSI 59.8 / 69.1 / 78.3 / 84.7 / 92.7 (= F7) |
| Good Value LSOAs | ≥ 20 NSI points safer than price predicts, NSI ≥ 50, not a centre, within budget | 111 at £250k (Rotherham 38, Sheffield 35, Doncaster 23, Barnsley 15) |

Note: RANKX-based measures ([FSI Rank], [NSI Rank (Custom Weights)]) evaluate each LSOA with ALLEXCEPT('LSOA', 'LSOA'[LSOA Key]) so other LSOA filters in a visual don't blank the comparison set.
