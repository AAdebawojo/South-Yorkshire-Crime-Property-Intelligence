# South Yorkshire Crime & Property Intelligence: Report architecture and design system

_Version 1.0, 12 Nov 2026. Applies to "South Yorkshire Crime Case Study.pbix". Companion files: `SY_Crime_Intelligence_Theme.json`, `deneb/*.json`, `Report_Build_Guide.md`._

---

## 1. Architecture

**Canvas:** 16:9, 1280 × 720 px, page view "Fit to page".

### Sections and pages
| Section | # | Page | Question it answers | Primary measures | Map / key visual |
|---|---|---|---|---|---|
| Crime Intelligence | 1 | **Overview** | How safe is South Yorkshire, where, and is it changing? | Crime Rate per 1,000, Severity Score, ASB Rate, Positive Outcome Rate, NSI, Insight 1–3 | Azure map (baseline NSI), Deneb district lollipop, Deneb trend strip |
| | 2 | **Crime Trends** | Is crime rising or falling, and when does it peak? | MoM / YoY %, Rolling 3 / 12, Seasonal Index, Trend Classification | Deneb trend with rolling average, Deneb month × year heatmap |
| | 3 | **Crime Mix & Harm** | What kinds of crime, and how harmful? | % of Crimes, % of Severity, Avg Severity per Crime | Deneb volume-vs-harm dumbbell |
| | 4 | **Outcomes** | What happens after a crime is reported? | Positive Outcome Rate, Outcome Group Share, Outcome Completeness %, Median Months to Outcome | Deneb completeness curve with maturity line |
| Property Intelligence | 5 | **Safety Index** | Which LSOAs are safest, and how robust is the ranking? | NSI Score / Rank / Band (baseline), NSI Scenario + Rank Shift (sliders) | Azure map, ranking table, Deneb component strip |
| | 6 | **Family Finder** ★ flagship | Where should a family with my budget and priorities look? | FSI, FSI Rank, FSI Class, Affordability, Good Value | Azure map (scenario FSI), shortlist, Deneb safety-vs-price scatter |
| | 7 | **LSOA Profile & Compare** (drill-through) | What is this LSOA like, and how does it compare with up to two others? | All LSOA columns and measures | Profile cards, Deneb comparison chart |
| Methodology | 8 | **Data & Method** | Can I trust this? | DQ checks, sources, method notes | Data-quality scorecard |
| (hidden) | – | **TT LSOA** | Report-page tooltip for any LSOA visual | NSI, FSI, price, confidence | Tooltip page 320 × 240 |

### Navigation system (built once on Page 1, copied to every page)
- **Left rail** (x 0–176, full height, navy `#14263D`): report title, three section labels (`CRIME INTELLIGENCE`, `PROPERTY INTELLIGENCE`, `METHODOLOGY`), each followed by a **Page navigator** visual restricted to that section's pages (Format › Pages: switch the other pages off). Selected page is teal.
- **Reset filters** button at the bottom of the rail → page bookmark `Reset – <Page>` (Data ✓, Display ✓, Current page ✓, All visuals). One bookmark per page.
- **Drill-through:** Page 7 has drill-through field `LSOA[LSOA Code]` (Keep all filters: On). Right-click any LSOA on pages 1, 5 and 6 → *Drill through › LSOA Profile*. Pages 5 and 6 also have a **View profile** button (Action: Drill through, destination LSOA Profile; it activates when one LSOA is selected). Page 7 has a **Back** button.
- **Synced slicers:** `District` (LSOA[Local Authority]) synced across pages 1–5. FSI budget and weight sliders live on page 6 only (page 7 reads their values but does not show them).
- **Interactions:** slicers filter everything; maps and Deneb visuals cross-filter; KPI cards never filter.

### Baseline vs scenario (requirement 2)
| Type | Definition | Badge | Examples |
|---|---|---|---|
| **Baseline** | Fixed, computed in SQL from approved methods (D-15, D-16). Same for every user. | Navy pill `BASELINE` | NSI Score, NSI Rank, NSI Band, all crime and outcome KPIs, Value for Money |
| **Scenario** | Recomputed live from the user's sliders (weights, budget). | Amber pill `SCENARIO` | NSI Scenario and its rank shift; FSI, FSI Rank, FSI Class, Affordability, Good Value within budget |

Rules: a scenario value is never shown without its baseline counterpart on the same page; Page 5 shows "Rank shift vs baseline"; Page 6 states the active budget and weights in its header.

### Confidence indicators (requirement 3)
- **Report level:** footer `[Data Confidence Note]` on every page (geolocation share, outcome maturity cut-off, population vintage, footfall caveat).
- **KPI level:** subtitles state the rule (e.g. "crimes ≥ 6 months old", "within normal variation").
- **LSOA level:** `[LSOA Data Confidence]` (built at Page 5): **Low** if high-footfall centre, < 100 crimes in 36 months, or house price from the MSOA fallback; **Medium** if 100–199 crimes, 10–19 house sales, or trend "Too few crimes"; otherwise **High**. Shown as a column, a tooltip line and a map outline.

### FSI suitability classes (Page 6)
| Class | Rule | Colour |
|---|---|---|
| Excellent match | FSI ≥ 70 | `#168A86` |
| Strong match | 60–70 | `#7DB8A6` |
| Good match | 50–60 | `#A9B4C2` |
| Partial match | 40–50 | `#E4A33B` |
| Weak match | < 40 | `#D56B63` |
| Not eligible | Over budget / busy centre / no price | `#C9D1DB` (hatched in Deneb) |

---

## 2. Design system

### Colour tokens
| Token | Hex | Role | Contrast on white | Use for |
|---|---|---|---|---|
| Navy | `#14263D` | Primary ink, nav rail, headers, Baseline badge | 15.3 : 1 | All primary text, axes titles, table headers |
| Slate | `#536579` | Secondary ink | 6.0 : 1 | Labels, subtitles, axis labels, neutral marks, Stable |
| Off-white | `#F7F9FC` | Page background | – | Canvas, alternate table rows |
| White | `#FFFFFF` | Surfaces | – | Cards, visuals |
| Teal | `#168A86` | **Safer / better / positive** | 4.2 : 1 | Marks and fills; large text only |
| Teal dark | `#0F6E6B` | Teal as text | 6.1 : 1 | Small "good" text |
| Amber | `#E4A33B` | **Caution / moderate / scenario** | 2.2 : 1 | Fills with a navy outline or label; Scenario badge (navy text) |
| Amber dark | `#9A6A12` | Amber as text | 4.7 : 1 | Small "caution" text |
| Muted coral | `#D56B63` | **Less safe / worse / rising** | 3.4 : 1 | Marks and fills |
| Coral dark | `#B4524A` | Coral as text | 5.0 : 1 | Small "warning" text |
| Border | `#D9E0E8` | Card borders, dividers | – | |
| Gridline | `#E3E8EF` | Gridlines | – | |
| Neutral mark | `#A9B4C2` | De-emphasised data | – | Monthly bars, "Good match" |
| Not available | `#C9D1DB` | No data / not eligible | – | |

### Semantic scales (identical on every page)
- **Safety band (NSI, 5 steps):** Very low `#D56B63` · Low `#E08A6F` · Moderate `#E4A33B` · High `#7DB8A6` · Very high `#168A86`. Colour is always paired with the band name or score.
- **Direction:** Rising (worse) coral, Falling (better) teal, Stable slate; arrows ▲ ▼ ▶ carry the meaning without colour.
- **Outcomes:** Charged / summonsed teal, Out-of-court teal light, No suspect slate, Not in public interest `#A9B4C2`, Transferred `#2E4A6B`, Pending amber, Unknown `#C9D1DB`.
- **Selection:** unselected marks 25% opacity; the selected mark keeps a navy 1 px outline.

### Typography (Segoe UI)
| Element | Font | Size | Colour |
|---|---|---|---|
| Page title | Segoe UI Semibold | 20 | Navy |
| Page subtitle (period, area) | Segoe UI | 10 | Slate |
| Visual title | Segoe UI Semibold | 12 | Navy |
| KPI value | Segoe UI Semibold | 26 | Navy |
| KPI label / reference label | Segoe UI | 10 / 9 | Slate |
| Body / narrative | Segoe UI | 11 | Navy |
| Axis and data labels | Segoe UI | 9 | Slate / Navy |
| Footer | Segoe UI | 8 | Slate |

### Layout grid (1280 × 720)
- Nav rail x 0–176. Content area x 192–1264 (1,072 px), 12 columns of 80 px with 12 px gutters.
- Rows: header y 12–64 · KPI row y 76–166 · main y 178–560 · strip y 572–682 · footer y 688–712.
- Spacing 12 px between visuals; card radius 8; 1 px border `#D9E0E8`; no drop shadows; padding 10–12.
- Maximum 8 data visuals per page (requirement 5); one hero visual per page.

### Components
| Component | Spec |
|---|---|
| Page header | Title text box (20 pt) + subtitle text box with dynamic values `[Selected Area Label]` · `[Report Period Label]`; slicers right-aligned in the header row |
| KPI card | Card (new); value 26 pt; label 10 pt; reference label = context measure 9 pt slate; optional accent bar coloured by a formatting measure |
| Insight panel | Text box with dynamic values (one paragraph per insight), 11 pt, 6 px left teal rule (rectangle 4 × panel height) |
| Badge | Rounded rectangle 64 × 18, text 8 pt bold: `BASELINE` navy fill / white text; `SCENARIO` amber fill / navy text |
| Info button | Button, "Information" icon, slate; tooltip text explains the method in ≤ 40 words |
| Footer | Text box with dynamic value `[Data Confidence Note]`, 8 pt slate |

### Number formats
Counts `#,##0` · rates `0.0` · severity `0.0` (KPI) / `0.00` (tables) · percentages `0.0%` · prices `£#,##0` · changes `+0.0%;-0.0%` · ranks `0`.

### Accessibility
Text ≥ 9 pt; text colours only Navy, Slate or the *dark* semantic variants (≥ 4.5 : 1); colour never the only cue (labels, arrows, band names); alt text on every visual (states what it shows and the current key value); tab order follows reading order; KPI cards carry full-sentence reference labels for screen readers.

### Deneb conventions
- Deneb (certified custom visual), Vega-Lite 5 specs; paste each spec into *Edit › Specification*; Config left empty (styling is in the spec).
- **Rename every field in the Deneb field well to the name listed at the top of the spec** (right-click › Rename for this visual). This avoids special characters such as "." and "%" in field names.
- Settings: *Cross-filtering* on (uses `__selected__`), *Tooltips* on, *Render mode* SVG.
- Colours come from formatting measures (e.g. `[NSI Area Colour]`) so Deneb and core visuals always match.

---

## 3. Geography: LSOA boundaries for Azure Maps

### Dataset
**Lower layer Super Output Areas (December 2021) Boundaries EW BGC (V5)**, ONS Open Geography Portal, Open Government Licence v3.0. BGC = generalised to 20 m, clipped to the coastline.
- **Vintage:** December 2021 LSOAs (Census 2021 geography), key `LSOA21CD`. Every source in the model uses the same vintage: police.uk CSV LSOA codes, ONS SAPE mid-2024, IoD 2025, Census 2021 and the ONS postcode lookup. Verified so far: all 860 model LSOAs carry 2021 codes (`E010xxxxx`, including the 2021 splits `E0103xxxx`).
- **Why BGC, not BSC (200 m):** many Sheffield, Rotherham and Doncaster centre LSOAs are under 0.3 km²; 200 m generalisation visibly distorts them. BGC keeps them recognisable; after cutting to South Yorkshire the file is small enough for the visual.
- **Attribution (Page 8 and map footers):** *Source: Office for National Statistics licensed under the Open Government Licence v.3.0. Contains OS data © Crown copyright and database right 2025.*

### Azure Maps capability check
| Requirement | Status | Evidence / plan |
|---|---|---|
| Upload GeoJSON as a reference layer | Documented | Supported formats include GeoJSON; only the first 30,000 features render (we have 860) |
| Bind polygons to model data | Documented | Data-bound reference layer: put the ID column (`LSOA Code`) in **Location**; the visual matches it to the file property with most matches |
| Filled-area colouring by data | Documented (gradient); field-value colour **to test** | Conditional formatting for polygons is documented; colouring by a text measure (`[NSI Band Colour]`) is tested in T3 |
| Responds to slicers and sliders | **To test** (expected, data-bound) | T4 (district slicer), T5 on Page 6 (budget slider) |
| Click polygon to cross-filter | **To test** | T6 |
| Formatting survives save / publish | Known community reports of reference-layer colours not persisting in the Service | T7 after save, reopen and (if used) publish |

**Prototype acceptance tests** (run on Page 1 before building anything else):
T1 860 polygons render · T2 Unmapped objects = 0 · T3 fill by `[NSI Band Colour]` (field value) or, failing that, gradient on `NSI Score` · T4 District slicer filters the map · T5 a measure-driven colour changes when a slicer changes · T6 clicking an LSOA cross-filters the other visuals · T7 colours persist after save, close and reopen.

**Fallbacks (in order):**
1. **Shape Map** (core visual, preview: *Options › Preview features › Shape map visual*) with `sy_lsoa_boundaries.topojson` (object `lsoa`, key `LSOA21CD`): colour by legend field `NSI Band` with the band colours, full cross-filtering. Limitations: preview, no base map.
2. **Deneb geoshape** with the TopoJSON pasted into the spec: full control, tooltips and cross-filtering, but heavier to edit.

Tenant note: Azure Maps must be allowed in Power BI (admin setting "Users can use the Azure Maps visual"); only LSOA codes and tooltip values are sent to the map service, no personal data.

### Steps (done 12 Nov 2026)
1. The old BGC (V5), BFC (V10) download and REST links now return "permissions" / "Token Required" errors (retired by ONS). The current file was downloaded from the ONS LSOA page › **Explore BGC 2021 LSOA Boundaries** › Download › GeoJSON (`2021_LSOA_Boundary_….geojson`, 93.5 MB, EPSG:4326, 35,672 features; properties named `CODE` / `NAME`).
2. `prepare_lsoa_boundaries.py` kept the 860 South Yorkshire LSOAs: **860 / 860 model codes matched, 0 missing, 0 extra**, 0 invalid geometries, extent lon −1.823 to −0.865, lat 53.302 to 53.661. Coverage simplification (4 m) 44,183 → 43,603 vertices.
3. Output in `report\`: `sy_lsoa_boundaries.geojson` (954 KB; properties `LSOA21CD`, `LSOA21NM`) and `sy_lsoa_boundaries.topojson` (602 KB; object `lsoa`), plus a preview image.
4. Next: build the Page 1 map (Report_Build_Guide §P1-6) and run T1–T7.
