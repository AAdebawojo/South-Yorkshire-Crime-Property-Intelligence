# Is It Safe, and Can We Afford It? Turning Half a Million Police Records into a Neighbourhood Decision Tool

### How I combined crime, deprivation, census and house-price data for South Yorkshire's 860 neighbourhoods into a Power BI intelligence product that answers the question every home-mover actually asks

---

When I started looking at where to live in South Yorkshire, I did what most people do. I opened a property portal, filtered by price, and then searched crime maps for each area that looked promising.

It didn't work. The crime map showed dots, not context. A street near a town centre looked alarming, but was that because people live dangerously there or because thousands of shoppers pass through it each day? A cheaper area looked similar to a more expensive one, but was it really, or did the difference in price reflect something the map couldn't show? And none of it told me anything about schools, green space or whether other families lived nearby.

The data to answer these questions is public. It just lives in eight different places, in different formats, at different geographic levels, and none of it was designed to be read together. So I built something that reads it together.

## The problem: four questions that don't fit in one spreadsheet

Looking at crime, house prices and neighbourhood characteristics separately leads to bad conclusions in three predictable ways:

- **Counts mislead.** A busy area records more crime simply because more people are there. You need rates, and you need the right denominator.
- **Not all crime is equal.** A shoplifting and a robbery are both "one crime", but they are not equally serious. A neighbourhood with lots of low-harm crime can look worse than one with fewer, more serious offences.
- **Price and safety are entangled.** Safer areas tend to cost more. The useful question isn't "where is safest?" but "where is safer than I'd expect for the price?"

So the analytical problem became four questions:

1. Which neighbourhoods are safer than others, once volume, harm, anti-social behaviour and trend are all considered?
2. Is crime rising or falling, and where?
3. Which neighbourhoods offer the best balance of safety, affordability and family suitability **for a specific buyer's budget and priorities**?
4. How confident can we be in each answer?

The solution is an eight-page Power BI report built on a PostgreSQL analytical database. But the interesting part is the journey between the problem and the dashboard.

**[IMAGE 1 – Overview page: `images/dashboard/01_overview.png`]**
*Caption: The Overview page: 36 months of South Yorkshire crime summarised into five KPIs, a neighbourhood-level Safety Index map, district comparison and dynamic written insights that update with every filter.*

## Bringing eight datasets into one place

Each source answered a different part of the question:

| Source | What it contributes |
|---|---|
| **police.uk** street-level crime, ASB and outcomes (Oct 2023 – Sep 2026) | 527,597 records: what happened, where (approximately) and what happened next |
| **ONS Crime Severity Score** weights + **Home Office** offence counts | How serious each category of crime is |
| **ONS mid-2024 population** by LSOA | The denominator that turns counts into rates |
| **English Indices of Deprivation 2025** | Children's education, living environment and outdoor environment indicators |
| **Census 2021** | Share of households with dependent children; tenure |
| **HM Land Registry Price Paid** | 47,943 standard residential sales in the same 36 months |
| **ONS LSOA (2021) boundaries** | The map |

The unit that holds everything together is the **LSOA** (Lower Layer Super Output Area): a census geography of roughly 1,500 residents. South Yorkshire has 860 of them. They are small enough to describe a real neighbourhood and standard enough that every government dataset can be joined to them.

Getting police data onto LSOAs was the first real challenge. The police.uk API returns anonymised map points and policing neighbourhoods, not LSOAs. The bulk CSV downloads do carry an LSOA code, but not the outcome history the API provides. Rather than install a spatial extension, I built a coordinate crosswalk: matching the API's anonymised points to the same points in the bulk files. That linked **99.9% of located crimes** to an LSOA, with a documented nearest-point fallback for a handful of railway stations.

House prices needed a different bridge: Land Registry gives postcodes, so sales were joined through the ONS postcode-to-LSOA lookup. 47,941 of 47,943 sales matched.

## The engineering: from API calls to an analytical model

The architecture has five layers, each with one job.

**1. Ingestion (Python → PostgreSQL).** A Python loader pulls every month for every South Yorkshire policing neighbourhood from the police.uk API. The API caps each query at 10,000 crimes, so the loader queries each neighbourhood's boundary (slightly buffered so nothing on the edges is lost) and then de-duplicates the overlaps: **790,680 records fetched, 527,601 distinct crimes kept**. It's resumable and logs every request, so a failed month can be retried without reloading the rest. Separate Python loaders bring in the bulk crime CSVs, the Land Registry files and the 417 MB ONS postcode lookup.

**2. Raw layers (`police`, `police_bulk`, `external_raw`).** Data lands exactly as received and is never modified. Everything downstream can be traced back to a source row.

**3. Analytical layer (`analytics`).** This is where the work happens, in SQL views, materialised views and stored procedures:
- *Cleaning and flags:* empty strings to NULL, ASB and British Transport Police flags, four duplicate crimes resolved with a deterministic rule, 23 orphan outcome rows quarantined in an exceptions view rather than silently dropped.
- *A star schema:* two fact tables (crimes and outcome events) and dimensions for month, LSOA, neighbourhood, location, crime category and outcome status, each with an explicit "unknown" member so nothing falls out of a join.
- *Enrichment:* population, deprivation, census and price indicators attached to each LSOA.
- *The indices:* the Neighbourhood Safety Index is computed in SQL and refreshed by a stored procedure; the Family Suitability Index is computed both in SQL (for validation) and live in Power BI (for the interactive version).

**4. Presentation layer (`pbi`).** Thin views exposing only the columns the report needs. Power BI imports only from here, which keeps the model lean and the contract between database and report explicit.

**5. Semantic model (Power BI).** Import mode, a dedicated measures table organised into folders, and DAX for rates, trends, significance tests, ranks and the scenario logic. Visuals combine core Power BI, Azure Maps with the ONS LSOA boundaries, and Deneb (Vega-Lite) where a custom chart told the story better.

Every step was validated before the next one started. Row counts reconcile from source to fact table. The severity score reproduces the ONS published figure for South Yorkshire (**20.57 against 20.58**). And as an independent check, my LSOA crime rates rank almost identically to the crime domain of the government's own deprivation index (**Spearman ρ = 0.81** across 860 LSOAs), which I deliberately kept out of the indices so it could serve as a cross-check.

A note on process: I worked with an AI assistant (Claude) throughout, using it to draft SQL, DAX and chart specifications and to keep the documentation in step. The decisions about scope, method and trade-offs were mine, and every number in this article was run, checked and reconciled in my own database and report. I found it most valuable not for writing code, but for challenging assumptions and keeping a disciplined validation log.

Code and documentation: `https://github.com/AAdebawojo/South-Yorkshire-Crime-Property-Intelligence`.

## The method: two indices, built to be argued with

### Neighbourhood Safety Index (NSI): the baseline

A composite index is useful here because no single measure captures "safety". The NSI combines four components for each LSOA:

| Component | Weight | Why |
|---|---:|---|
| **Harm** (severity-weighted crime per resident) | 50% | Seriousness matters more than volume |
| **Crime rate** per 1,000 residents | 20% | How often crime happens |
| **Anti-social behaviour** rate | 20% | Quality of daily life, measured separately |
| **Trend** (last 12 vs prior 12 months) | 10% | Direction of travel |

Three statistical choices make it defensible:

- **Smoothing.** An LSOA with 1,300 residents and three burglaries can swing wildly from year to year. Rates are shrunk towards the district average (empirical Bayes), in proportion to how little evidence each LSOA has.
- **Significance, not percentages.** A "rising" trend has to be statistically significant after correcting for the extra variability real crime data shows, not just a bigger number.
- **Percentiles.** Each component becomes a percentile across South Yorkshire (100 = safest), then the weighted average is taken. Percentiles put harm, rates and trends on the same scale and stop one extreme value from dominating.

The result is banded from Very low (under 20) to Very high (80+). It is a **relative** measure, "safer than most of South Yorkshire", not an official rating or a guarantee.

**[IMAGE 2 – Safety Index page: `images/dashboard/05_safety_index.png`]**
*Caption: The Safety Index page separates the fixed baseline (navy badge) from a scenario the user controls (amber badge). Move the four weight sliders and the map, ranking and "LSOAs moving 50+ places" card update live, a built-in sensitivity test.*

### Family Suitability Index (FSI): the scenario

The FSI answers the buyer's question. It combines five components, again as percentiles:

| Component | Default weight | Source |
|---|---:|---|
| Safety (NSI) | 35% | police.uk via the NSI |
| Affordability | 20% | Land Registry vs the buyer's budget |
| Schools | 20% | IoD 2025 children's education domain |
| Family community | 10% | Census 2021, households with dependent children |
| Environment | 15% | IoD 2025 living and outdoor environment |

Affordability is the one component that depends on the user: **200 × (1 − price ÷ budget)**, capped at 100. A home at half your budget or less scores 100; one at exactly your budget scores 0; anything above budget is "not eligible", as are busy town centres. Results are grouped into clear classes: Excellent (70+), Strong (60–70), Good (50–60), Partial (40–50) and Weak (below 40).

## What the report can do

Across eight pages, the report moves from "what happened" to "what should I do":

- **Crime Trends:** monthly crime with rolling averages, a month-by-year heatmap and a seasonal index. Click any month and the KPIs recalculate for it.
- **Crime Mix & Harm:** compares each category's share of crimes with its share of harm.
- **Outcomes:** what happens after a crime is reported, by crime type and district, with a chart showing why recent months can't yet be judged.
- **Safety Index:** the baseline map and ranking, plus the weight sliders.
- **Family Finder:** budget and priority sliders, a suitability map, a safety-vs-price chart and a ranked shortlist with a data-confidence rating for every LSOA.
- **LSOA Profile:** right-click any neighbourhood anywhere in the report to drill through to its profile, then compare up to three neighbourhoods side by side.
- **Data & Method:** sources, method, quality checks and limitations, inside the report rather than in a separate document.

**[IMAGE 3 – Family Finder page: `images/dashboard/06_family_finder.png`]**
*Caption: The Family Finder. A buyer sets a budget and five priorities; every score, class, map colour and shortlist rank recalculates. Here, at £250,000 and default weights, 660 LSOAs are within budget and 136 are a strong or excellent match.*

## What the data revealed

**Crime is high but stable.** South Yorkshire recorded **449,049 crimes** (excluding ASB) in 36 months: **104.6 per 1,000 residents a year**. The latest 12 months are up just **0.6%** on the previous 12, within normal variation. Anti-social behaviour rose **3.0%**. Crime is seasonal: summer months run about **4% above** an average month and winter about **7% below**, with February the quietest month in both 2025 and 2026.

**[IMAGE 4 – Crime Trends page: `images/dashboard/02_crime_trends.png`]**
*Caption: Crime Trends: rolling averages show a broadly flat picture; the heatmap and seasonal index show a clear summer peak and February trough.*

**The volume of crime and the harm it causes are different stories.** Violence and sexual offences make up **40% of crimes but 61% of harm**. Burglary is **6% of crimes but 14.5% of harm**. Shoplifting is the reverse: **10% of crimes, under 1% of harm**. The average recorded crime carries a severity weight of **197 custody-days**. A safety measure built on counts alone would get the priorities wrong.

**[IMAGE 5 – Crime Mix & Harm page: `images/dashboard/03_crime_mix_harm.png`]**
*Caption: Share of crimes against share of harm. Coral lines mark categories that are more harmful than their volume suggests; teal lines, less.*

**District differences are real but modest.** Sheffield (Safety Index **51.5**) and Rotherham (**51.2**) sit above the county average of **49.1**; Barnsley is close to it (**48.8**); Doncaster is lowest (**43.4**), with **115.2 crimes per 1,000 residents**. The bigger variation is *within* districts: every district has both very safe and very unsafe LSOAs.

**Town centres distort everything, which is why they are flagged.** The least safe LSOA on paper, Rotherham 017B, records **829 crimes per 1,000 residents a year**, about eight times the county rate. It's a town centre: the residents are few and the visitors many. Twenty-nine such high-footfall centres are flagged throughout the report and excluded from family recommendations.

**Most crimes don't reach a charge, and the reasons differ by crime type.** **12.5%** of crimes led to a charge, summons or out-of-court resolution (crimes at least six months old). That rose from 12.4% to 13.0% in the latest year, a small but statistically significant improvement. Drug offences have the highest rate (**50.5%**), plausibly because they are usually detected by police rather than reported by victims. Vehicle crime has the lowest (**2.0%**). The pattern behind the low rates differs: for violence and sexual offences, **67%** of crimes had a suspect identified but no prosecution; for vehicle crime, **88%** closed with no suspect at all.

**[IMAGE 6 – Outcomes page: `images/dashboard/04_outcomes.png`]**
*Caption: What happens after a crime is reported. Each bar is 100% of that crime type's outcomes; the right-hand chart shows why the most recent six months are excluded from the KPIs.*

**Safety costs money, but not uniformly.** Across LSOAs, each doubling of house price is associated with about **27 more Safety Index points** (R² 0.38). That's a strong association, not a cause, and it leaves most of the variation unexplained, which is exactly where the opportunities are. **111 LSOAs** are at least 20 points safer than their price predicts and still within a £250,000 budget.

**The top match isn't the safest place, and the safest place isn't eligible.** At £250,000 with default weights, the top family match is **Barnsley 024D**: Safety Index 91.3 (rank 28 of 860), strong schools and environment scores, and a typical house price of £240,000, about **32 points safer than its price predicts**. The single safest LSOA in the county, Sheffield 023D (95.0), is over that budget. And at **£150,000**, no LSOA reaches "Strong"; the best match scores 59.8.

**The rankings are robust.** If you abandon the baseline weights entirely and weight all four safety components equally, only **66 of 860** LSOAs move by 50 places or more, and the county score barely changes (49.1 → 49.3).

**[IMAGE 7 – LSOA Profile page: `images/dashboard/07_lsoa_profile.png`]**
*Caption: Drill through to any neighbourhood for its full profile, then compare up to three side by side: here, the three top family matches at default settings.*

## Who this is for

- **Home-buyers and relocating families** can shortlist neighbourhoods on their own budget and priorities, and see why each one scores as it does.
- **First-time buyers** can find the "better than its price" areas rather than assuming cheaper means worse.
- **Estate agents and property professionals** can give context beyond price, with sources attached.
- **Investors and developers** can spot where safety, family demand and price diverge.
- **Local authorities and community safety teams** can see harm, not just volume, and track outcome rates by crime type and district.
- **Planners and researchers** can reuse a documented, reproducible LSOA-level dataset.

None of this replaces official crime statistics, a survey or professional advice. It's a structured, transparent starting point for better questions.

## Limitations, stated up front

Every analytical product has limits; the honest ones put them on the screen. This one has a dedicated page and a confidence rating on every LSOA:

- **95.2%** of crimes have a location; the rest count only in force-wide totals.
- Recorded crime reflects reporting and recording, not all crime.
- Resident-based rates overstate risk in centres, stations and retail parks.
- Scores are relative to South Yorkshire, not absolute measures of risk.
- House prices are medians of recent sales, not valuations. Where an LSOA had fewer than 10 house sales, the wider area's median is used and flagged.
- Outcomes lag; the latest six months are excluded from outcome KPIs.
- The schools component is an area deprivation indicator, not school results or catchments.

The confidence rating matters in practice. All five of the very safest LSOAs are rated **Low** confidence: so little crime happens there that the score, while right in direction, is imprecise. A tool that hid that would be more impressive and less honest.

**[IMAGE 8 – Data & Method page: `images/dashboard/08_data_method.png`]**
*Caption: Method, sources and limitations live inside the report, alongside a monthly check on how many crimes carry a location.*

## More than a dashboard

Most dashboards stop at describing the past. This one is designed to support a decision. It combines:

- **Descriptive analytics:** what happened, how much and when.
- **Diagnostic analytics:** where harm concentrates and why centres look different.
- **Comparative analytics:** LSOA against LSOA, district against district.
- **Decision support:** a ranked shortlist for a specific buyer.
- **Scenario analysis:** change the budget or the weights and see what changes, and what doesn't.

## What I learned, and what's next

Three lessons stood out. First, **the geography is the hard part**: almost every interesting result depended on getting crimes, people and prices onto the same small areas, accurately. Second, **validation is a feature**: reconciling to the ONS severity score and cross-checking against the deprivation index is what lets the indices be trusted. Third, **design for disagreement**: by exposing the weights as sliders, the report invites users to test its assumptions rather than accept them.

Possible next steps (not yet built):

- Short-term forecasting of crime trends, with uncertainty bands.
- School performance and catchment data in place of the area indicator.
- Rental prices and transport access in the Family Finder.
- Scheduled refreshes as police.uk publishes each new month.
- The same pipeline applied to other police force areas.

The broader point is simple. Public data is abundant; intelligence is not. The value comes from joining the right sources at the right level, being explicit about method and uncertainty, and putting the result in front of people in a form that helps them decide.

*Data: police.uk (Open Government Licence); ONS; MHCLG English Indices of Deprivation 2025; Census 2021. Contains HM Land Registry data © Crown copyright and database right. Licensed under the Open Government Licence v3.0. Contains OS data © Crown copyright and database right.*

---

