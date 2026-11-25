# Report build guide

_Version 2.0, 12 Nov 2026. Field-by-field instructions, one section per page. Build in order and validate each page before starting the next. Design rules: `Report_Design_System_and_Architecture.md`. Target images: `report\mockups\`._

---

## Conventions used in this guide

- **Positions and sizes** are in pixels on a **1280 × 720** canvas: `X, Y, W, H`. Set them in **Format › General › Properties › Size / Position**.
- **Fonts are in points; boxes are in pixels.** 1 pt ≈ 1.33 px, so 12 pt text is about 16 px tall. As a rule of thumb, allow **about 0.75 × font size (pt) × number of characters** in pixels for normal text (≈ 0.85 × for capitals and Semibold), plus the padding.
- **Padding** means **Format › General › Properties › Padding** (four values: top, bottom, left, right) unless the step says otherwise. Text boxes, shapes, buttons and navigators use **0**; the theme sets this, but a value you have typed earlier overrides the theme, so check it.
- **"Clean" objects** (shapes, text boxes, buttons, navigators): Format › General › Effects: **Background off, Visual border off, Shadow off**; General › Header icons: **Visual header off**. The updated theme does this by default.
- **Data visuals** (cards, charts, maps, Deneb) keep the theme's card style: white background, 1 px border `#D9E0E8`, radius 8, padding 10 top/bottom and 12 left/right.
- **Layer order:** View › Selection pane. Background shapes go at the **bottom** of the list, text and controls above them.
- After every few steps: **Ctrl+S**.

---

## P0. One-off set-up

| # | Step | Detail |
|---|---|---|
| 1 | Theme | View › Themes › Browse for themes › `report\SY_Crime_Intelligence_Theme.json`. Re-import it whenever I send an updated file; it overwrites the old one. |
| 2 | Canvas | For **each** page: Format page › Canvas settings › Type **16:9**, which gives 1280 × 720. View › Page view › **Fit to page**. Keep 1280 × 720; do not use 1920 × 1080, because Power BI would show it at about two-thirds size and every position in this guide would be wrong. |
| 3 | Pages | Eight pages in this order: `Overview`, `Crime Trends`, `Crime Mix & Harm`, `Outcomes`, `Safety Index`, `Family Finder`, `LSOA Profile`, `Data & Method`. ✔ Done |
| 4 | Deneb | Visualizations pane › **…** › Get more visuals › search "Deneb" › **Deneb: Declarative Visualization in Power BI** (Daniel Marsh-Patrick, certified) › Add. ✔ Done |
| 5 | Azure Maps | On by default; no setting needed. Icon: map with a pin, tooltip "Azure Maps". Leave "Use Map and Filled Map visuals" unticked. |
| 6 | Auto date/time | File › Options › Current file › Data load: Auto date/time **off** (confirm). |
| 7 | Page view helpers | View: **Gridlines on** and **Snap to grid off** while building (snap fights exact positions). |

---

## P1. Overview

Target: `mockups\P1_Overview.jpg`.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail (group) | 0 | 0 | 176 | 720 | Shape, text boxes, 3 page navigators, button |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 640 | 22 | Text box with dynamic values |
| 4 | District slicer | 1104 | 8 | 160 | 58 | Slicer (dropdown) |
| 5 | KPI cards × 5 | see P1-4 | 76 | 206 | 90 | Card (new) |
| 6 | Safety map | 192 | 178 | 520 | 382 | Azure Maps |
| 7 | Insight panel | 724 | 178 | 540 | 182 | Shape + rule + text box |
| 8 | District safety | 724 | 372 | 540 | 188 | Deneb |
| 9 | Monthly trend | 192 | 572 | 1072 | 110 | Deneb |
| 10 | Footer | 192 | 690 | 1072 | 22 | Text box with dynamic value |

---

### P1-1 Nav rail

Build the rail once on this page. After Page 1 is validated, copy the whole group to every other page.

**1. Background rectangle.** Insert › Shapes › Rectangle.
- **0, 0, 176, 720**; padding 0.
- Style › Fill `#14263D`, transparency 0; Border off; rounded corners 0.
- Clean object (see Conventions). In the Selection pane, move it to the **bottom**.

**2. Report title.** Text box at **12, 16, 160, 56**; padding 0; clean object.
- Line 1: `SY Crime & Property`, Segoe UI Semibold **11 pt**, white `#FFFFFF`.
- Press Enter. Line 2: `Intelligence`, Segoe UI **9 pt**, `#A9B4C2`.
- Check: line 1 must not wrap (≈ 140 px of text in 160 px). If it does, padding is not 0.

**3. Section labels.** Three text boxes, each **W 156, H 20**, padding 0, clean object. Segoe UI Semibold **8 pt**, `#A9B4C2`, typed in capitals.

| Label | X | Y |
|---|---|---|
| CRIME INTELLIGENCE | 16 | 80 |
| PROPERTY INTELLIGENCE | 16 | 280 |
| METHODOLOGY | 16 | 446 |

If "PROPERTY INTELLIGENCE" wraps, use 7.5 pt; do not widen the box.

**4. Page navigators.** Insert › Buttons › Navigator › **Page navigator**, three times.

| Navigator | Pages shown (Visual › Pages: switch the others off) | X | Y | W | H |
|---|---|---|---|---|---|
| A | Overview, Crime Trends, Crime Mix & Harm, Outcomes | 8 | 104 | 160 | 150 |
| B | Safety Index, Family Finder, LSOA Profile | 8 | 304 | 160 | 108 |
| C | Data & Method | 8 | 470 | 160 | 32 |

For each navigator:
- **Padding:**
  - **Container** (General › Properties › Padding): **0**.
  - **Gap between buttons** (Visual › Grid layout › Padding): **6 px**.
  - **Text indent** (Visual › Style › Text › Padding): **Left 14, Right 8, Top 0, Bottom 0**.
- **Layout:** Visual › Grid layout: Orientation **Vertical**.
- **Style.** Set each state in turn using "Apply settings to":

| State | Text | Fill |
|---|---|---|
| **Default** | Segoe UI 10 pt, `#D9E0E8`, align Left | Off |
| **On hover** | `#FFFFFF` | `#2E4A6B` |
| **Selected** | Segoe UI Semibold 10 pt, `#FFFFFF` | Teal `#168A86` |

  Repeat the text padding for the **Selected** and **On hover** states, otherwise the selected text shifts sideways. Shape › rounded corners **6**; Border **off**; clean object.
- **Check:** each button is 32–33 px tall: (150 − 3 × 6) / 4 = 33 for A, (108 − 2 × 6) / 3 = 32 for B, 32 for C.

**5. Reset button.** Insert › Buttons › **Reset**.
- **16, 660, 144, 36**; padding 0; clean object.
- **Style (Default):**
  - Text **on**: `Reset filters`, Segoe UI Semibold 10 pt, white, centred.
  - Icon **on**: shape Reset, line colour white, weight 1.5, **Icon placement: Left of text**, icon size **14**.
  - Fill **on** `#2E4A6B`; Border **off**; rounded corners **6**.
- **On hover:** Fill `#3B5A80`.
- The action is set in P1-3.

**6. Group the rail.** Select all rail objects (rectangle, title, three labels, three navigators, Reset button) › right-click › **Group** › rename the group `Nav rail`. In the Selection pane the group's first child must be the rectangle, at the bottom.

---

### P1-2 Page header

**1. Title.** Text box at **192, 8, 640, 36**; padding 0; clean object. Text `Overview`, Segoe UI Semibold **20 pt**, `#14263D`.

**2. Subtitle.** Text box at **192, 42, 640, 22**; padding 0; clean object.
- Click **+ Value** › type `Selected Area Label` › Enter.
- Type a space, a middle dot (`·`) and a space.
- **+ Value** › `Report Period Label`.
- Format the whole line: Segoe UI **10 pt**, `#536579`.
- It should read: `South Yorkshire · Oct 2023 – Sep 2026 · 36 months · data.police.uk`.

**3. District slicer.** Slicer at **1104, 8, 160, 58**.
- **Field:** `LSOA[Local Authority]`.
- **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**. This hides the 4 out-of-county authorities and Unknown.
- **Slicer settings:** Style **Dropdown**; Selection: Multi-select with Ctrl **on**, "Select all" **on**.
- **Header:** on, text `District`, Segoe UI Semibold 8 pt, `#536579`.
- **Values:** Segoe UI 9 pt, `#14263D`; dropdown border `#D9E0E8`, radius 4.
- **General:** padding **4 top, 4 bottom, 8 left, 8 right**; background white; border `#D9E0E8`, radius 6; visual header off.
- If the dropdown box is still clipped, turn the header off and use Height 36 at Y 16.

**4. Sync.** View › **Sync slicers** with this slicer selected:
- Add it to group `District`.
- Tick **sync and visible** for Overview, Crime Trends, Crime Mix & Harm, Outcomes and Safety Index.
- The copies appear on those pages when you open them.

---

### P1-3 Reset bookmark

1. Clear the District slicer (all selected).
2. View › **Bookmarks** › Add. Rename it `Reset – Overview`.
3. Right-click the bookmark and set: **Data** ✓, **Display** ✓, **Current page** ✓, **All visuals** ✓.
4. Select the rail's Reset button › Format › **Action** on › Type **Bookmark** › Bookmark `Reset – Overview`.

> **Important:** a bookmark stores every filter on the page, including visual-level filters such as `In South Yorkshire = True`. Create or **update** it (right-click › Update) only when the page is finished and its visual-level filters are in place. If you change any visual's filters later, update the bookmark again; otherwise Reset restores the old filters (out-of-county authorities reappear and the map zooms out to the Atlantic).
5. Ctrl+click the button to test it.

Repeat for every page once it is built. Each copy of the rail's Reset button points to its own page's bookmark.

---

### P1-4 KPI cards

Insert › **Card (new)**, five times. Each card is **W 206, H 90, Y 76**.

Labels and reference labels are kept short so each fits **one line** in a 206-px card. The full definitions go in the alt text and on the Data & Method page.

| Card | X | Value | Label (one line) | Reference label (one line) | Accent bar colour (fx › Field value) |
|---|---|---|---|---|---|
| 1 | 192 | `[Crime Rate per 1,000]` | Crime rate per 1,000 / yr | `[Crime Rate Change Label]` → "▲ +0.6% vs prior 12m · Stable" | `[Trend Colour]` |
| 2 | 409 | `[Severity Score]` | Severity score / resident / yr | `[Severity Context Label]` → "197 custody-days per crime" | none |
| 3 | 625 | `[ASB Rate per 1,000]` | ASB per 1,000 / yr | `[ASB Change Label]` → "▲ +3.0% vs prior 12m" | none |
| 4 | 842 | `[Positive Outcome Rate]` | Positive outcome rate | `[Outcome Context Label]` → "3.6% status unknown" | none |
| 5 | 1058 | `[NSI]` | Safety Index (0–100) | `[Safety Index Context Label]` → "Moderate · 36% in safer LSOAs" | `[NSI Area Colour]` |

Formatting for every card:
- **General › Properties › Padding:** 0. The card's own padding is set next.
- **Visual › Cards:**
  - Background white; Border `#D9E0E8`, radius **8**.
  - Padding **8 top, 6 bottom, 14 left, 10 right**.
  - **Accent bar:** on for cards 1 and 5 only, position **Left**, width **4**. Colour fx › Format style **Field value** › the measure in the table.
- **Visual › Callout value:** Segoe UI Semibold **22 pt**, `#14263D`, horizontal alignment Left.
- **Visual › Label:** on, position **Above value**, Segoe UI **9 pt**, `#536579`. Type the label text from the table; if your version has no label text box, rename the field in the field well instead.
- **Visual › Reference labels:**
  - Add › Data = the reference measure.
  - **Title off**.
  - Value Segoe UI **8 pt**, `#536579`.
  - Layout **Below**, divider off.
- **Visual › Layout:** vertical alignment **Top**.
- **General:** Title off; Visual header off; Alt text e.g. "Crime rate per 1,000 residents a year, excluding anti-social behaviour, with change versus the prior 12 months".

Check: label, value and reference label each on **one line**, nothing clipped. If anything still clips, reduce the callout to 20 pt.

**Card 5:** add the `BASELINE` badge.
- Rounded rectangle at **1188, 84, 60, 16**; padding 0; fill `#14263D`; rounded corners 8; clean object.
- On top of it, a text box at **1188, 84, 60, 16**; padding 0; `BASELINE`, Segoe UI Semibold **7 pt**, white, centred.
- Group the two as `Badge – KPI5`.

---

### P1-5 Insight panel

**1. Panel background.** Rectangle at **724, 178, 540, 182**; padding 0.
- Fill white; Border **on** `#D9E0E8`, width 1; rounded corners **8**.
- Clean object except the border.

**2. Accent rule.** Rectangle at **724, 186, 4, 166**; padding 0. Fill teal `#168A86`; Border off; rounded corners 2; clean object.

**3. Text.** Text box at **740, 186, 516, 166**; padding **0**; Background off; clean object.

| Line | Content | Format |
|---|---|---|
| 1 | `Key insights` | Segoe UI Semibold 11 pt, `#14263D` |
| 2 | **+ Value** › `Insight 1 Headline` | Segoe UI 9.5 pt, `#14263D` |
| 3 | **+ Value** › `Insight 2 Places` | Segoe UI 9.5 pt, `#14263D` |
| 4 | **+ Value** › `Insight 3 Trend and Outcomes` | Segoe UI 9.5 pt, `#14263D` |

Paragraph spacing after: 6 pt.

**4. Group** the three objects as `Insights`, with the background at the bottom.

**Check:** with no filter, each insight fits in two lines. If the text overflows when a district is selected, drop lines 2–4 to 9 pt.

---

### P1-6 Safety map (Azure Maps)

Boundary file: `report\sy_lsoa_boundaries.geojson`. It has 860 LSOAs, all matched to the model; the code property is `LSOA21CD`.

1. Insert **Azure Maps** at **192, 178, 520, 382**. Keep the theme card style: padding 10 top/bottom, 12 left/right.
2. **Fields:**
   - **Location:** `LSOA[LSOA Code]`.
   - **Tooltips:** `LSOA[LSOA Name]`, `LSOA[Local Authority]`, `LSOA[NSI Score]`, `LSOA[NSI Band]`, `LSOA[Crime Rate (Raw)]`, `LSOA[Trend]`, `LSOA[High-Footfall Centre]`.
3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Format › Reference layer:** Type **Upload file** › `report\sy_lsoa_boundaries.geojson`. The visual matches `LSOA Code` to `LSOA21CD`.
5. **Reference layer › Polygons:**
   - Fill colour fx › Format style **Field value** › `[NSI Band Colour]`; transparency **10%**.
   - Border colour white, width **0.5**.
   - **Unmapped objects:** on, `#C9D1DB`.
   - If *Field value* isn't offered, use Format style **Gradient** on `NSI Score`: minimum `#D56B63`, centre 50 `#E4A33B`, maximum `#168A86`.
6. **Bubble layer:** off. If it can't be switched off, set size 0 and transparency 100%.
7. **Map settings:** Style **Grayscale (light)**; Auto zoom **on**; Zoom buttons **on**; Style picker **off**; Navigation controls **off**.
8. **Title:** `Neighbourhood Safety Index by LSOA`. Subtitle on: `860 LSOAs · darker teal = safer · click an LSOA to filter`.
9. **BASELINE badge:** like card 5, at **632, 188, 60, 16**.
10. **Legend.** Text box at **200, 534, 300, 20**; padding 0; background white at 10% transparency. Content: `■ Very low  ■ Low  ■ Moderate  ■ High  ■ Very high`, Segoe UI 8 pt, `#14263D`. Colour each ■ with its band hex: `#D56B63`, `#E08A6F`, `#E4A33B`, `#7DB8A6`, `#168A86`.
11. **Run tests T1–T7** (architecture doc §3) and report the results:
    - **T1:** 860 polygons appear.
    - **T2:** 0 unmapped objects.
    - **T3:** the fill uses `[NSI Band Colour]` (field value).
    - **T4:** the District slicer filters the map.
    - **T5:** the colours change when a slicer changes.
    - **T6:** clicking an LSOA cross-filters the other visuals.
    - **T7:** the colours survive save, close and reopen.

    If T3 or T6 fails, tell me before going further; we'll switch to the Shape Map fallback with `report\sy_lsoa_boundaries.topojson`.

---

### P1-7 District safety (Deneb)

1. Insert Deneb at **724, 372, 540, 188**. Keep the theme card style; padding 10 / 12.
2. **Fields.** Add them in this order, then right-click each one in the field well › **Rename for this visual** to the name in the right-hand column:

| Field | Rename to |
|---|---|
| `LSOA[Local Authority]` | `District` |
| `[NSI]` | `NSI` |
| `[NSI South Yorkshire]` | `SY NSI` |
| `[Crime Rate per 1,000]` | `Crime Rate` |
| `[Severity Score]` | `Severity` |
| `[% Residents in Safer LSOAs]` | `Safer Residents` |
| `[NSI Area Colour]` | `Band Colour` |

3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Spec:** Deneb › **Edit** › Create using **Vega-Lite** › Empty. Open `report\deneb\P1_district_safety_lollipop.json` in Notepad, copy all of it, and paste it over the Specification. Leave **Config** empty › **Apply** › **Back to report**.
5. **Deneb editor › Project setup** (gear tab next to Config): Tooltips **on**; Context menu **on**; Cross-filtering **on** (Simple); Cross-highlighting **off**. These are not in the Format pane in current Deneb versions.
6. **Title:** `Safety Index by district vs South Yorkshire`. Subtitle: `dashed line = South Yorkshire average`.
7. **BASELINE badge** at **1188, 382, 60, 16**.

---

### P1-8 Monthly trend (Deneb)

1. Insert Deneb at **192, 572, 1072, 110**. Padding **6 top, 6 bottom, 12 left, 12 right**; the strip is short.
2. **Fields:**

| Field | Rename to | Note |
|---|---|---|
| `Month[Month Start]` | `Month` | Field well dropdown › choose **Month Start**, not *Date Hierarchy* |
| `[Crimes (excl. ASB)]` | `Crimes` | |
| `[Rolling 12-Month Avg]` | `Rolling 12` | |

3. **Spec:** paste `report\deneb\P1_monthly_trend_strip.json`. Tooltips on; Cross-filtering **off**.
4. **Title:** `Monthly crimes (excl. ASB) and 12-month rolling average`. Subtitle off.

---

### P1-9 Footer

Text box at **192, 690, 1072, 22**; padding 0; clean object. **+ Value** › `Data Confidence Note`. Format Segoe UI **8 pt**, `#536579`.

---

### P1-10 Interactions and tidy-up

1. **Interactions.** Select each visual › Format ribbon › **Edit interactions**:
   - **Map:** filters the KPI cards, the insights text, the District Deneb and the trend.
   - **District Deneb:** filters the map, the cards, the insights and the trend.
   - **District slicer:** filters everything (default).
   - **KPI cards, trend strip:** filter nothing.
2. **Tab order:** View › Selection › **Tab order**: rail, slicer, cards 1–5, map, insights, district chart, trend, footer.
3. **Lock:** View › **Lock objects** once the layout is right, to avoid nudging things while testing.
4. **Save:** Ctrl+S.

---

### P1 validation

Send me a screenshot of the page in each state.

| # | State | Expected |
|---|---|---|
| V1 | No selection, Filters pane empty | Cards: **104.6** · **20.57** · **18.3** · **12.5%** · **49.1**. Card 1 reference "▲ +0.6% vs prior 12m · Stable" with a slate accent bar. Card 2 "197 custody-days per crime". Card 4 "3.6% status unknown". Card 5 "Moderate · 36% in safer LSOAs", amber accent bar. |
| V2 | No selection | Insight 1: "South Yorkshire recorded 449,049 crimes (excluding ASB): 104.6 per 1,000 residents a year. Harm-weighted severity is 20.6 custody-days per resident a year." Insight 2: "Sheffield is the safest district (Safety Index 51.5); Doncaster is the least safe (43.4, 115.2 crimes per 1,000)…". Insight 3: "Crime is stable: +0.6% … within normal variation; ASB +3.0%. 12.5% of crimes led to a charge or out-of-court resolution (3.6% have no recorded status)." |
| V3 | No selection | District Deneb: Sheffield 51.5 (+2.3 vs SY), Rotherham 51.2 (+2.1), Barnsley 48.8 (−0.3), Doncaster 43.4 (−5.8); dashed line at 49.1. |
| V4 | No selection | Trend strip: last point Sep 2026 = **12,173**; rolling line starts Sep 2024 and ends at about **12,368**. |
| V5 | District = Doncaster | Cards 115.2 · 22.39 · 19.6 · 11.0% · 43.4. Insight 1 "…17% above the South Yorkshire average"; Insight 2 "Doncaster ranks 4 of 4 districts on the Safety Index (43.4 vs 49.1 …)". |
| V6 | District = Rotherham | Card 1 "▲ +8.2% vs prior 12 months · Rising" with a coral accent bar; Insight 3 "Crime is rising: +8.2% … (statistically significant)". |
| V7 | Map | T1–T7 results; Sheffield City Centre and Doncaster/Barnsley/Rotherham town-centre LSOAs coral (Very low). |
| V8 | Reset button | Clears the slicer and any cross-filter; page returns to V1. |
| V9 | Footer | "Data confidence: 95.2% of crimes geolocated … outcome KPIs use crimes up to Mar 2026 …" |

---

## Copying the rail to other pages (after P1 passes)

1. Select the `Nav rail` group › Ctrl+C › open the next page › Ctrl+V. It keeps the same position.
2. On each new page, create that page's `Reset – <Page>` bookmark (P1-3) and point that page's Reset button at it.
3. The page navigators highlight the current page automatically.

---

## P2. Crime Trends

Target: `mockups\P2_Crime_Trends.jpg`. Question: *Is crime rising or falling, and when does it peak?*

**How the page works.** The KPI cards describe a **focus month**: the latest month (Sep 2026) unless you click a month in the trend chart or the heatmap. The "last 12 vs prior 12" card and the seasonal chart always use the whole series. The District and Crime group slicers filter everything. All counts exclude ASB.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 720 | 22 | Text box, dynamic |
| 4 | Crime group slicer | 936 | 8 | 160 | 58 | Slicer (dropdown) |
| 5 | District slicer | 1104 | 8 | 160 | 58 | Synced copy from Overview |
| 6 | KPI cards × 4 | see P2-3 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 7 | Trend chart | 192 | 178 | 1072 | 250 | Deneb |
| 8 | Seasonality heatmap | 192 | 440 | 640 | 242 | Deneb |
| 9 | Seasonal index | 844 | 440 | 420 | 242 | Deneb |
| 10 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P2-1 Rail, slicers and footer

1. **Rail:** Overview › select the `Nav rail` group › Ctrl+C › Crime Trends › Ctrl+V (same position). The navigator highlights Crime Trends automatically.
2. **District slicer:** it appears automatically because it was synced in P1-2 (View › Sync slicers: "Crime Trends" ticked under both columns). If it is not visible, tick the eye column for Crime Trends. Check its position: 1104, 8, 160, 58.
3. **Footer:** copy the footer text box from Overview (Ctrl+C / Ctrl+V).
4. **Crime group slicer** at **936, 8, 160, 58**. Format it the same as the District slicer (P1-2 step 3).
   - Field: `Crime Category[Crime Group]`.
   - Visual-level filter: `Crime Category[Crime Group]` › Basic filtering › **Select all**, then **untick "Anti-social behaviour" and "Unknown"**.
   - Header text `Crime group`.
   - Sync it: View › Sync slicers › group `Crime group` › sync and visible on **Crime Trends** and **Outcomes**.

### P2-2 Header

1. **Title:** text box at **192, 8, 640, 36**, padding 0, clean. `Crime Trends`, Segoe UI Semibold 20 pt, **navy `#14263D`**. Select the text and set the colour explicitly; the text box default is grey.
2. **Subtitle:** text box at **192, 42, 720, 22**, padding 0, clean. **+ Value** › `Trends Subtitle`. Segoe UI 10 pt, `#536579`.
   - It reads: `South Yorkshire · All crime (excl. ASB) · focus month: Sep 2026 (click a month to change)`.

### P2-3 KPI cards

Use the Page 1 layout: a **Card (new)** showing label and value only (reference labels **off**), plus a **subtitle text box** grouped with it. Card settings as in P1-4: callout Segoe UI Semibold **22 pt**, label 9 pt slate, Cards padding **8 / 6 / 14 / 10**, accent bar **Left, width 4** where listed.

| Card | Card X | Value (Data) | Label | Accent bar (fx › Field value) | Subtitle text box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[MoM % (Focus)]` | Month-on-month | `[Change Colour (MoM)]` | 206 | `MoM Context Label` |
| 2 | 463 | `[YoY % (Focus)]` | Year-on-year | `[Change Colour (YoY)]` | 477 | `YoY Context Label` |
| 3 | 734 | `[Last 12 vs Prior 12 %]` | Last 12 vs prior 12 months | `[Trend Colour]` | 748 | `Trend Context Label` |
| 4 | 1004 | `[Peak Season]` | Seasonal peak | none | 1018 | `Peak Season Label` |

- **Cards:** all at **Y 76, W 260, H 90**.
- **Subtitle text boxes:** all at **Y 142, W 232, H 18**. Padding 0, clean object, Segoe UI 8 pt, `#536579`.
- In the Selection pane put each text box **above** its card, then group each pair (`KPI P2-1` … `KPI P2-4`).
- **Accent colours:** coral = higher than the comparison (worse), teal = lower (better), slate = stable.
- **Cards 1 and 2, blank months:** the first month has no month-on-month value and the first 12 months have no year-on-year value. Set Visual › Callout value › **Blank value / Show blank as** to `n/a` so the card doesn't show 0%. The subtitle then explains why ("Needs 12 earlier months").

### P2-4 Trend chart (Deneb)

1. Insert Deneb at **192, 178, 1072, 250**. Theme card style; padding **10 / 10 / 12 / 12**.
2. **Fields** (rename for this visual):

| Field | Rename to | Note |
|---|---|---|
| `Month[Month Start]` | `Month` | Choose **Month Start**, not the date hierarchy |
| `[Crimes (excl. ASB)]` | `Crimes` | |
| `[Rolling 3-Month Avg]` | `Rolling 3` | |
| `[Rolling 12-Month Avg]` | `Rolling 12` | |

3. **Spec:** paste `report\deneb\P2_trend_rolling.json`.
4. **Project setup:** Tooltips on; Context menu on; **Cross-filtering on (Simple)**; Cross-highlighting off.
5. **Title:** `Monthly crimes with 3- and 12-month rolling averages`.
6. **Subtitle:** `grey = monthly · teal = 3-month average · navy = 12-month average · click a month to focus the cards`. Segoe UI 8.5 pt, `#536579`.
7. **Info button:** Insert › Buttons › Information, at **1236, 186, 20, 20**, slate. Action › Tooltip: `Rolling averages smooth month-to-month noise. The 12-month average starts in Sep 2024, the first month with 12 months of history.`

### P2-5 Seasonality heatmap (Deneb)

1. Insert Deneb at **192, 440, 640, 242**. Padding 10 / 10 / 12 / 12.
2. **Fields:**

| Field | Rename to |
|---|---|
| `Month[Year]` | `Year` |
| `Month[Month No]` | `Month No` |
| `Month[Month Short]` | `Month` |
| `[Crimes (excl. ASB)]` | `Crimes` |

3. **Spec:** paste `report\deneb\P2_season_heatmap.json`. Project setup: Tooltips on; **Cross-filtering on (Simple)**.
4. **Title:** `Crimes by month and year`.
5. **Subtitle:** `teal = quieter months · coral = busier · click a cell to focus the cards`.

### P2-6 Seasonal index (Deneb)

1. Insert Deneb at **844, 440, 420, 242**. Padding 10 / 10 / 12 / 12.
2. **Fields:**

| Field | Rename to |
|---|---|
| `Month[Season]` | `Season` |
| `Month[Season Sort]` | `Season Sort` |
| `[Seasonal Index]` | `Index` |
| `[Avg Monthly Crimes (Complete Seasons)]` | `Avg Monthly` |

3. **Spec:** paste `report\deneb\P2_seasonal_index.json`. Project setup: Tooltips on; **Cross-filtering off**.
4. **Title:** `Seasonal index (1.00 = average month)`.
5. **Subtitle:** `complete seasons only · coral ≥ 3% above · teal ≥ 3% below`.

### P2-7 Interactions

Format ribbon › **Edit interactions**:

| Source | KPI cards | Subtitle text boxes | Trend chart | Heatmap | Seasonal index |
|---|---|---|---|---|---|
| Trend chart | **Filter** | **Filter** | – | **None** | **None** |
| Heatmap | **Filter** | **Filter** | **None** | – | **None** |
| Seasonal index | None | None | None | None | – |
| Slicers | Filter | Filter | Filter | Filter | Filter |

The trend chart and the heatmap must **not** filter each other, otherwise clicking a month would collapse the other chart to a single point.

### P2-8 Reset bookmark (last step)

With both slicers cleared and nothing selected: View › Bookmarks › Add `Reset – Crime Trends` (Data, Display, Current page, All visuals). Point this page's rail Reset button at it.

### P2 validation

| # | State | Expected |
|---|---|---|
| V1 | No selection | Cards: **−7.0%** (teal bar) · **+1.7%** (coral bar) · **+0.6%** (slate bar) · **Summer**. Subtitles: "12,173 vs 13,090 in Aug 2026" · "vs 11,966 in Sep 2025" · "z = +1.64 · Stable (not significant)" · "+4% above an average month · Winter -7%". |
| V2 | No selection | Trend chart: last point Sep 2026 = 12,173 (teal); 12-month line starts Sep 2024 and ends ≈ 12,368; 3-month line ends ≈ 12,950. Lowest points Feb 2025 (10,811) and Feb 2026 (10,849). |
| V3 | No selection | Heatmap: Oct 2023 13.2k … Sep 2026 12.2k; highest cell Jul 2026 13.6k; Feb 2025 and Feb 2026 10.8k (teal). Empty cells Jan–Sep 2023 and Oct–Dec 2026. |
| V4 | No selection | Seasonal index: Spring 1.03 (12,767/month; 1.025 rounds up), Summer 1.04 (12,953), Autumn 1.01 (12,540), Winter 0.93 (11,590). Summer coral, Winter teal. |
| V5 | Click Jan 2025 in the trend chart | Subtitle "focus month: Jan 2025"; card 1 **−1.8%** "11,376 vs 11,584 in Dec 2024"; card 2 **−10.1%** "vs 12,648 in Jan 2024"; card 3 unchanged (+0.6%); heatmap unchanged. |
| V6 | District = Rotherham, Crime group = Burglary | Card 1 **+10.9%**, card 2 **+47.0%**, card 3 **+7.2%** "z = +1.79 · Stable (not significant)", card 4 **Winter** "+6% above an average month · Summer -5%". |
| V7 | Reset filters | Back to V1. |

---

---

## P3. Crime Mix & Harm

Target: `mockups\P3_Crime_Mix_and_Harm.jpg`. Question: *What kinds of crime happen, and which cause the most harm?* Harm = ONS Crime Severity Score weights (custody-days per offence, T-212). All figures exclude ASB.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 900 | 22 | Text box, dynamic |
| 4 | District slicer | 1104 | 8 | 160 | 58 | Synced copy |
| 5 | KPI cards × 4 | 192 / 463 / 734 / 1004 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 6 | Volume vs harm | 192 | 178 | 640 | 504 | Deneb |
| 7 | Crime rate by group | 844 | 178 | 420 | 282 | Bar chart (core) |
| 8 | Harm by district × group | 844 | 472 | 420 | 210 | Matrix (core) |
| 9 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P3-1 Rail, slicer, footer, header

1. Paste the `Nav rail` group and the footer from Overview.
2. **District slicer:** View › Sync slicers › tick Crime Mix & Harm (sync and visible). Check its position: 1104, 8, 160, 58.
3. **Title:** text box at **192, 8, 640, 36**, padding 0, clean. `Crime Mix & Harm`, Segoe UI Semibold 20 pt, **navy `#14263D`**.
4. **Subtitle:** text box at **192, 42, 900, 22**, padding 0, clean. **+ Value** › `Crime Mix Subtitle`. Segoe UI 10 pt, `#536579`.

### P3-2 KPI cards

Same layout as Page 2: a Card (new) with label and value only, plus a subtitle text box grouped above it.
- **Cards:** Y 76, W 260, H 90; callout 22 pt; Cards padding 8 / 6 / 14 / 10.
- **Subtitle boxes:** Y 142, W 232, H 18; 8 pt slate; padding 0.

| Card | Card X | Value | Label | Accent bar | Subtitle box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[Avg Severity per Crime]` | Average harm per crime | none | 206 | `Avg Severity Context Label` |
| 2 | 463 | `[Top Harm Shift]` | Largest share of harm | coral `#D56B63` (fixed colour) | 477 | `Top Harm Label` |
| 3 | 734 | `[High Volume Low Harm Category]` | Common but low harm | teal `#168A86` (fixed colour) | 748 | `High Volume Low Harm Label` |
| 4 | 1004 | `[Highest Harm Category]` | Most harmful per offence | none | 1018 | `Highest Harm Label` |

- **Card 1 format:** Callout value › Display units **None**, decimal places **0**, so it shows 197.
- **Card 2** shows text (e.g. "40% → 61%"). Callout 22 pt fits.
- **Card 2 subtitle** reads "Violence & sexual: % of crimes → % of harm" (the measure shortens long category names so it fits one line in 232 px).

### P3-3 Volume vs harm (Deneb)

1. Insert Deneb at **192, 178, 640, 504**. Theme card style; padding 10 / 10 / 12 / 12.
2. **Fields** (rename for this visual):

| Field | Rename to |
|---|---|
| `Crime Category[Crime Category]` | `Category` |
| `[% of Crimes]` | `Crime Share` |
| `[% of Severity]` | `Harm Share` |
| `[Crimes (excl. ASB)]` | `Crimes` |
| `[Avg Severity per Crime]` | `Weight` |

3. **Visual-level filter:** `Crime Category[Is ASB]` is **False**.
4. **Spec:** paste `report\deneb\P3_volume_vs_harm.json`. Project setup: Tooltips on; Context menu on; **Cross-filtering on (Simple)**.
5. **Title:** `Share of crimes vs share of harm, by category`.
6. **Subtitle:** `● grey = share of crimes  ● coral = share of harm  ·  coral line = more harmful than its volume suggests · teal = less`.
7. **Help tooltip** (General › Header icons › Help tooltip): `Harm weights each offence by the ONS Crime Severity Score: the average custody-days a court gives that offence. Robbery = 994, shoplifting = 13. The weights reproduce the published ONS score for South Yorkshire (20.57 vs 20.58).`

### P3-4 Crime rate by group (core bar chart)

1. Insert **Clustered bar chart** at **844, 178, 420, 282**.
2. **Fields:**
   - Y-axis: `Crime Category[Crime Group]`
   - X-axis: `[Crime Rate per 1,000]`
   - Tooltips: `[Crimes (excl. ASB)]`, `[% of Crimes]`
3. **Visual-level filter:** `Crime Category[Is ASB]` is **False**; `Crime Category[Is Unknown]` is **False**.
4. **Sort:** … › Sort axis › `Crime Rate per 1,000`, **descending**.
5. **Bars:** Colour fx › Format style **Field value** › `Rate Bar Colour`. The highest group is navy, the rest slate.
6. **Data labels:** on, 8 pt, `#14263D`, format `0.0`.
7. **X-axis:** off. **Y-axis:** labels 8.5 pt `#14263D`, no title. Gridlines off.
8. **Fit all groups without a scroll bar:** Y-axis › Layout › **Minimum category width 16 px** (default 20 px forces a scroll bar once there are more than about 9 groups). Bars › Layout › Space between categories **35%**. Visual padding 8/8/12/8.
9. **Title:** `Crime rate per 1,000 residents a year, by crime group`, 11 pt.

### P3-5 Harm by district and crime group (core matrix)

1. Insert **Matrix** at **844, 472, 420, 210**.
2. **Fields:**
   - Rows: `LSOA[Local Authority]`
   - Columns: `Crime Category[Crime Group]`
   - Values: `[Severity Score]`
3. **Visual-level filters:**
   - `LSOA[In South Yorkshire]` is **True**.
   - `Crime Category[Crime Group]` › **Top N** › Show items **Top 6** › By value `[Severity Days]`. This keeps Violence, Burglary, Robbery, Drugs, Theft and Vehicle crime.
4. **Format:**
   - Values: 9 pt, decimal places **1**.
   - Column headers: 8 pt, word wrap on.
   - Row and column subtotals **off**.
   - Grid: horizontal only.
5. **Cell elements** › Background colour **on** › fx › Format style **Gradient** › based on `Severity Score`:
   - Minimum: Lowest value, white `#FFFFFF`.
   - Maximum: Highest value, coral `#D56B63`.
   - Font colour stays navy.
6. **Title:** `Harm by district and crime group`. Subtitle: `severity score (custody-days per resident a year) · darker = more harm`.

### P3-6 Interactions and reset

1. **Edit interactions:**
   - The **Deneb chart** filters the bar chart and the matrix.
   - The **bar chart** filters the matrix (highlighting is fine) but **not** the Deneb chart, which keeps the full mix in view.
   - The **matrix** filters nothing.
   - KPI cards are filtered by the slicer only. Set Deneb → cards to **None**, so the cards always describe the whole mix.
2. **Reset bookmark** (last step): `Reset – Crime Mix & Harm` (Data, Display, Current page, All visuals). Point this page's rail Reset button at it.

### P3 validation

| # | State | Expected |
|---|---|---|
| V1 | No selection | Cards: **197** "custody-days per crime (ONS weights)" · **40% → 61%** "Violence & sexual: % of crimes → % of harm" · **Shoplifting** "10.1% of crimes · 0.7% of harm" · **Robbery** "994 custody-days per offence (ONS weight)". |
| V2 | No selection | Deneb (13 categories, sorted by share of crimes): Violence 40.0% → 61.3% (+21.3 pts), Shoplifting 10.1% → 0.7% (−9.5), Criminal damage 9.8% → 1.6% (−8.2), Public order 8.8% → 0.8% (−8.1), Burglary 6.0% → 14.5% (+8.5), Robbery 1.4% → 7.2% (+5.8). |
| V3 | No selection | Bar chart: Violence and sexual offences **41.8** (navy), Theft 18.7, Criminal damage and arson 10.3, Public order offences 9.3, Vehicle crime 7.7, Burglary 6.2, Other crime 3.9, Drug offences 3.7, Robbery 1.5, Possession of weapons 1.5. |
| V4 | No selection | Matrix (district × Violence / Burglary / Robbery / Drugs / Theft / Vehicle): Barnsley 11.6 / 2.8 / 1.1 / 0.7 / 0.6 / 0.5 · Doncaster 13.9 / 3.1 / 1.6 / 1.1 / 0.8 / 0.7 · Rotherham 11.7 / 2.4 / 1.2 / 0.7 / 0.6 / 0.5 · Sheffield 10.9 / 2.7 / 1.4 / 1.1 / 0.7 / 0.5. Doncaster's violence cell darkest. |
| V5 | District = Doncaster | Card 1 **194**; card 2 **40% → 62%**; card 3 Shoplifting; card 4 Robbery. |
| V6 | Click Burglary in the Deneb chart | Other categories fade; the bar chart shows Burglary only (6.2); the matrix shows the Burglary column only. |
| V7 | Reset filters | Back to V1. |

---

## P4. Outcomes

Target: `mockups\P4_Outcomes.jpg` (where they differ, this guide wins). Question: *What happens after a crime is reported?*

**How the page works.** Every crime counts once, with its **latest** status. Only crime months at least 6 months old (Oct 2023 – Mar 2026) count in the KPIs, because recent crimes have not had time to reach an outcome (D-07). The right-hand chart shows why. A **positive outcome** means charged/summonsed or an out-of-court resolution; it is not a conviction rate (D-14, DQ-27). All figures exclude ASB.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 736 | 22 | Text box, dynamic |
| 4 | Crime group slicer | 936 | 8 | 160 | 58 | Synced copy from Crime Trends |
| 5 | District slicer | 1104 | 8 | 160 | 58 | Synced copy |
| 6 | KPI cards × 4 | 192 / 463 / 734 / 1004 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 7 | Outcome mix by crime group | 192 | 178 | 640 | 504 | Deneb |
| 8 | Outcome status by crime month | 844 | 178 | 420 | 248 | Deneb |
| 9 | Outcomes by district | 844 | 438 | 420 | 244 | Table (core) |
| 10 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P4-1 Rail, slicers, footer, header

1. Paste the `Nav rail` group and the footer from Overview.
2. **Slicers:** View › Sync slicers. Select the District slicer and tick **Outcomes** (sync and visible). Select the Crime group slicer (on Crime Trends) and check **Outcomes** is ticked in both columns. Check positions: Crime group 936, 8, 160, 58; District 1104, 8, 160, 58.
3. **Title:** text box at **192, 8, 640, 36**, padding 0, clean. `Outcomes`, Segoe UI Semibold 20 pt, select the text and set **navy `#14263D`**.
4. **Subtitle:** text box at **192, 42, 736, 22**, padding 0, clean. **+ Value** › `Outcomes Subtitle`. Segoe UI 10 pt, `#536579`.
   - It reads: `South Yorkshire · All crime (excl. ASB) · crimes Oct 2023 – Mar 2026 (6-month maturity rule)`.

### P4-2 KPI cards

Same layout as Pages 2 and 3: a Card (new) with label and value only (reference labels off), plus a subtitle text box grouped above it.
- **Cards:** Y 76, W 260, H 90; callout Segoe UI Semibold 22 pt; label 9 pt slate; Cards padding 8 / 6 / 14 / 10; accent bar Left, width 4 where listed.
- **Subtitle boxes:** Y 142, W 232, H 18; Segoe UI 8 pt `#536579`; padding 0; clean.

| Card | Card X | Value | Label | Accent bar | Subtitle box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[Positive Outcome Rate]` | Positive outcome rate | none | 206 | `Positive Outcome Label` |
| 2 | 463 | `[Charged Share]` | Charged or summonsed | teal `#168A86` (fixed) | 477 | `Charged Context Label` |
| 3 | 734 | `[Unable to Prosecute Share]` | Suspect found, not prosecuted | slate `#536579` (fixed) | 748 | `Unable to Prosecute Label` |
| 4 | 1004 | `[Positive Rate Change (pts)]` | Change vs prior 12 months | fx › Field value › `[Outcome Change Colour]` | 1018 | `Outcome Change Label` |

- **Card 4** compares the latest 12 mature crime months (Apr 2025 – Mar 2026) with the 12 before, using a two-proportion z-test. Teal = significant improvement, coral = significant fall, slate = no significant change. The value is already formatted as `+0.6 pts`.
- **Alt text, card 1:** "Share of crimes from Oct 2023 to Mar 2026 that led to a charge, summons or out-of-court resolution. Not a conviction rate."

### P4-3 Outcome mix by crime group (Deneb)

1. Insert Deneb at **192, 178, 640, 504**. Theme card style; padding 10 / 10 / 12 / 12.
2. **Fields** (add in this order, then rename for this visual):

| Field | Rename to |
|---|---|
| `Crime Category[Crime Group]` | `Group` |
| `[Positive Outcome Rate]` | `Positive Rate` |
| `[Charged Share]` | `Charged` |
| `[Out-of-court Share]` | `Out of court` |
| `[Other Closed Share]` | `Other closed` |
| `[Unable to Prosecute Share]` | `Not prosecuted` |
| `[No Suspect Share]` | `No suspect` |
| `[Unknown Outcome %]` | `Unknown` |

3. **Visual-level filters:** `Crime Category[Is ASB]` is **False**; `Crime Category[Is Unknown]` is **False**.
4. **Spec:** paste `report\deneb\P4_outcome_mix.json`. Project setup: Tooltips on; Context menu on; **Cross-filtering on (Simple)**; Cross-highlighting off.
5. **Title:** `What happened to each crime, by crime group`.
6. **Subtitle:** `latest status · sorted by positive outcome rate (shown after each group) · click a group to filter the page`. Segoe UI 8.5 pt, `#536579`.
7. **Help tooltip** (General › Header icons › Help tooltip): `"Suspect identified, not prosecuted" is the police.uk status "Unable to prosecute suspect": a suspect was identified but the case could not go further, often because of evidential difficulties or because the victim did not support action. "Not in public interest / transferred" covers formal or further action not in the public interest and cases passed to another organisation.`

Each bar is 100% of that group's crimes. The stack runs from positive outcomes (teal, left) to unresolved (slate and grey, right).

### P4-4 Outcome status by crime month (Deneb)

1. Insert Deneb at **844, 178, 420, 248**. Padding 10 / 10 / 12 / 12.
2. **Fields:**

| Field | Rename to | Note |
|---|---|---|
| `Month[Month Start]` | `Month` | Choose **Month Start**, not the date hierarchy |
| `[Concluded % (Crime Month)]` | `Concluded` | |
| `[Positive % (Crime Month)]` | `Positive` | |
| `[Open % (Crime Month)]` | `Open` | |
| `[Mature Flag]` | `Mature` | |

3. **Spec:** paste `report\deneb\P4_outcome_lag.json`. Project setup: Tooltips on; **Cross-filtering off**.
4. **Title:** `Outcome status by month the crime happened`.
5. **Subtitle:** `shaded months are too recent to count in the KPIs`.
6. **Help tooltip** (General › Header icons › Help tooltip): `Still open = under investigation or charged and awaiting a court outcome. Outcomes take months to be recorded, so the KPIs only use crimes at least 6 months old.`

### P4-5 Outcomes by district (core table)

1. Insert **Table** at **844, 438, 420, 244**.
2. **Columns** (rename for this visual in the field well):

| Field | Rename to |
|---|---|
| `LSOA[Local Authority]` | `District` |
| `[Positive Outcome Rate]` | `Positive` |
| `[Charged Share]` | `Charged` |
| `[Out-of-court Share]` | `Out of court` |
| `[Unable to Prosecute Share]` | `Not prosecuted` |
| `[Unknown Outcome %]` | `Unknown` |

3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Sort:** click the `Positive` header so it sorts **descending**.
5. **Format:**
   - Values 9.5 pt navy; column headers 8.5 pt Semibold, word wrap on; Style preset **Minimal**; grid horizontal only, `#E3E8EF`.
   - **Totals off.** The district figures only include crimes with a location, so a total row would not match card 1.
   - **Cell elements** › series `Positive` › **Data bars** on: positive bar teal `#168A86`, bar only off, minimum 0, maximum **0.4** (Custom), so the bars stay in the left third of the cell and the comparable scale holds.
   - **Specific column** › series `Positive` › Alignment **Right**, so the value sits clear of the bar. Widen the column to about 90 px by dragging its header edge.
6. **Title:** `Outcomes by district`. Subtitle: `share of crimes (Oct 2023 – Mar 2026) · located crimes only`.

### P4-6 Interactions and reset

1. **Edit interactions:**
   - **Outcome mix (Deneb)** filters the KPI cards, the subtitle text boxes, the crime-month chart and the table.
   - **Table** filters the cards, the subtitle text boxes and both Deneb charts (click a district).
   - **Crime-month chart** filters nothing.
2. **Reset bookmark** (last step, once all visual-level filters are in place): `Reset – Outcomes` (Data, Display, Current page, All visuals), with both slicers cleared. Point this page's rail Reset button at it.

### P4 validation

| # | State | Expected |
|---|---|---|
| V1 | No selection | Cards: **12.5%** "46,676 crimes · 3.6% status unknown" · **8.8%** "+ 3.8% resolved out of court" · **42.5%** "+ 39.9% closed with no suspect" · **+0.6 pts** "13.0% vs 12.4% · significant", teal accent bar. |
| V2 | No selection | Outcome mix, top to bottom: Drug offences 50.5%, Possession of weapons 28.4%, Theft 19.5%, Robbery 13.2%, Public order offences 11.0%, Other crime 10.9%, Violence and sexual offences 10.2%, Criminal damage and arson 7.4%, Burglary 5.2%, Vehicle crime 2.0%. Violence: dark-slate "suspect identified, not prosecuted" segment ≈ **67%**. Vehicle crime: light-grey "no suspect" segment ≈ **88%**. |
| V3 | No selection | Crime-month chart: Concluded line about 86–90% from Oct 2023 to Mar 2026, then falls to about **50%** in Sep 2026; Still open line rises to about **50%** in Sep 2026; Charged or resolved line about 11–14%; amber shading over Apr–Sep 2026. |
| V4 | No selection | Table: Barnsley 13.4% / 9.9% / 3.5% / 46.5% / 2.9% · Sheffield 13.2% / 8.8% / 4.3% / 39.3% / 3.6% · Rotherham 11.5% / 8.2% / 3.3% / 45.9% / 4.0% · Doncaster 11.0% / 8.2% / 2.9% / 43.2% / 3.7%. |
| V5 | District = Doncaster | Cards **11.0%** "10,153 crimes · 3.7% status unknown" · **8.2%** "+ 2.9% resolved out of court" · **43.2%** "+ 40.2% closed with no suspect" · **+0.6 pts** "11.5% vs 10.9% · significant". |
| V6 | Click Violence and sexual offences in the outcome mix | Other bars fade; cards **10.2%** "15,062 crimes · 5.0% status unknown" · **6.7%** "+ 3.5% resolved out of court" · **66.9%** "+ 16.1% closed with no suspect" · **−0.3 pts** "10.0% vs 10.3% · not significant", slate accent bar. Subtitle shows "Violence and sexual offences". |
| V7 | Crime group slicer = Burglary (clear V6 first) | Cards **5.2%** "1,199 crimes · 1.8% status unknown" · **4.8%** · **11.4%** "+ 81.5% closed with no suspect" · **+0.3 pts** "5.6% vs 5.3% · not significant". |
| V8 | Reset filters | Back to V1. |

---

## P5. Safety Index

Target: `mockups\P5_Safety_Index.jpg` (where they differ, this guide wins). Question: *Which neighbourhoods are safest, and how much does that depend on the weights?*

**How the page works.** Two versions of the Safety Index sit side by side and are always labelled:
- **Baseline** (navy `BASELINE` badge): the fixed index, weights 50 / 20 / 20 / 10 (severity / crime rate / ASB / trend). It is the same everywhere in the report.
- **Scenario** (amber `SCENARIO` badge): recomputed live from the four weight sliders. The map and the scenario rank follow the sliders; at the default weights they match the baseline.

Each LSOA also gets a **confidence** rating: **Low** = busy town or city centre (rates inflated by visitors) or fewer than 100 crimes in 36 months; **Medium** = 100–199 crimes; **High** = 200+. Several of the very safest LSOAs are Low confidence simply because so few crimes happen there: the score is right in direction but less precise.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 900 | 22 | Text box, dynamic |
| 4 | District slicer | 1104 | 8 | 160 | 58 | Synced copy |
| 5 | KPI cards × 4 | 192 / 463 / 734 / 1004 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 6 | Safety map (scenario) | 192 | 178 | 420 | 300 | Azure Maps |
| 7 | Distribution strip (baseline) | 192 | 490 | 420 | 192 | Deneb |
| 8 | Scenario weights panel | 624 | 178 | 640 | 112 | Shape + text + 4 slicers |
| 9 | LSOA ranking | 624 | 302 | 640 | 380 | Table (core) |
| 10 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P5-1 Rail, slicer, footer, header

1. Paste the `Nav rail` group and the footer from Overview.
2. **District slicer:** View › Sync slicers › tick **Safety Index** (sync and visible). Check its position: 1104, 8, 160, 58.
3. **Title:** text box at **192, 8, 640, 36**, padding 0, clean. `Safety Index`, Segoe UI Semibold 20 pt, select the text and set **navy `#14263D`**.
4. **Subtitle:** text box at **192, 42, 900, 22**, padding 0, clean. **+ Value** › `Safety Index Subtitle`. Segoe UI 10 pt, `#536579`.
   - It reads: `South Yorkshire · baseline = fixed weights 50 / 20 / 20 / 10 · scenario = your weights · 860 LSOAs`.

### P5-2 KPI cards

Same layout as Pages 2–4 (Card (new) with label and value, plus a subtitle text box grouped above it; cards Y 76, W 260, H 90; callout 22 pt; subtitle boxes Y 142, W 232, H 18, 8 pt slate).

| Card | Card X | Value | Label | Accent bar | Subtitle box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[NSI]` | Safety Index · baseline | fx › Field value › `[NSI Area Colour]` | 206 | `Safety Index Context Label` |
| 2 | 463 | `[NSI (Custom Weights)]` | Safety Index · your weights | amber `#E4A33B` (fixed) | 477 | `Scenario Change Label` |
| 3 | 734 | `[LSOAs Moved 50+ Places]` | LSOAs moving 50+ places | amber `#E4A33B` (fixed) | 748 | `Rank Stability Label` |
| 4 | 1004 | `[Low Confidence LSOAs]` | Low-confidence LSOAs | coral `#D56B63` (fixed) | 1018 | `Low Confidence Label` |

- Callout format for cards 1 and 2: decimal places **1**. Cards 3 and 4: **0**.
- **Badges** (same build as P1-4 card 5; rounded rectangle + text box, 60 × 16, padding 0, rounded corners 8):
  - Card 1: `BASELINE`, fill navy `#14263D`, white 7 pt Semibold, at **388, 84**.
  - Card 2: `SCENARIO`, fill amber `#E4A33B`, navy 7 pt Semibold, at **659, 84**.
- **Card 3** shows how robust the ranking is: the number of LSOAs whose rank under your weights is 50 or more places from the baseline rank (out of 860). At the default weights it is 0.

### P5-3 Scenario weights panel

1. **Panel:** rectangle at **624, 178, 640, 112**, padding 0; fill white; border `#D9E0E8` 1 px; rounded corners 8; clean otherwise.
2. **Heading:** text box at **636, 184, 160, 20**, padding 0, clean. `Scenario weights`, Segoe UI Semibold 11 pt, navy.
3. **Live weights:** text box at **800, 186, 380, 18**, padding 0, clean. Type `normalised: ` then **+ Value** › `Scenario Weights Label`. Segoe UI 8.5 pt, `#536579`.
4. **Badge:** `SCENARIO` (amber, as in P5-2) at **1192, 186**.
5. **Four sliders.** Insert › Slicer, four times; each **Y 204, W 150, H 82**:

| Slicer | X | Field | Header text | Default |
|---|---|---|---|---|
| A | 632 | `NSI Weight Severity[Severity Weight %]` | Severity (harm) | 50 |
| B | 788 | `NSI Weight Crime Rate[Crime Rate Weight %]` | Crime rate | 20 |
| C | 944 | `NSI Weight ASB[ASB Weight %]` | Anti-social behaviour | 20 |
| D | 1100 | `NSI Weight Trend[Trend Weight %]` | Trend | 10 |

   For each:
   - **Slicer settings › Options › Style: Single value.** This gives a slider with one handle. (Single value only appears for columns flagged as what-if parameters; the ten weight/budget columns carry that flag since 22 Nov. If it is missing, remove the field from the slicer and add it again, or save, close and reopen the file.)
   - Drag the handle (or type in the box) to the **Default** value in the table.
   - **Header:** on, Segoe UI Semibold 8 pt `#536579`. **Values** (input box): 9 pt navy. **Slider:** colour teal `#168A86`.
   - **General:** padding **0**; background **off**; border **off**; visual header off. A slicer that is too short for its header, number box and slider shows only a grey funnel icon; 82 px fits all three.
   - Do **not** sync these sliders to other pages.
6. **Group** panel, heading, live weights, badge and sliders as `Scenario weights`.
7. **Help tooltip** on the heading text box isn't available, so add an **Information button** (Insert › Buttons › Information) at **1236, 264, 20, 20**, slate. Action › Tooltip: `Weights are re-scaled to add up to 100%, so only their ratios matter. Set one to 0 to drop that component. The baseline Safety Index never changes; only the map, card 2, card 3 and the scenario rank respond.`

### P5-4 Safety map, scenario (Azure Maps)

Build it like the Overview map (P1-6); the differences are listed here.

1. Copy the Overview map, paste it here and set **192, 178, 420, 300**. Or build it fresh with P1-6 steps 1–7.
2. **Tooltips** (replace the list; all are measures): `[LSOA]`, `[District]`, `[Safety Index (baseline)]`, `[Scenario Safety Index]`, `[Safety Rank]`, `[Confidence]`, `[Busy Centre]`.
3. **Reference layer › Polygons › Fill colour** fx › Field value › **`[Scenario Band Colour]`** (not `NSI Band Colour`).
4. **Title:** `Safety Index by LSOA · your weights`. Subtitle: `same as baseline at default weights · click an LSOA to filter`.
5. **Badge:** `SCENARIO` (amber) at **540, 188**.
6. Delete the legend text box if you copied one; add the same legend (P1-6 step 10) at **200, 452, 300, 20**.

### P5-5 Distribution strip, baseline (Deneb)

1. Insert Deneb at **192, 490, 420, 192**. Padding 8 / 8 / 12 / 12.
2. **Fields** (add in this order; rename for this visual):

| Field | Rename to |
|---|---|
| `LSOA[LSOA Code]` | `Code` |
| `LSOA[LSOA Name]` | `LSOA` |
| `LSOA[Local Authority]` | `District` |
| `LSOA[NSI Score]` | `NSI` |
| `LSOA[NSI Band]` | `Band` |
| `LSOA[NSI Rank]` | `Rank` |
| `[Safety Confidence]` | `Confidence` |

   `NSI Score` and `NSI Rank` are columns: in the field well set each to **Don't summarize** if Power BI offers a summary. Having `LSOA Code` in the well keeps one row per LSOA.
3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Spec:** paste `report\deneb\P5_nsi_strip.json`. Project setup: Tooltips on; Context menu on; **Cross-filtering on (Simple)**; Cross-highlighting off.
5. **Title:** `Every LSOA's Safety Index, by district`. Subtitle: `one dot per LSOA · hollow = low confidence · navy tick = district median`.
6. **Badge:** `BASELINE` (navy) at **540, 498**.

### P5-6 LSOA ranking (core table)

1. Insert **Table** at **624, 302, 640, 380**.
2. **Columns** (in this order; rename for this visual):

| Field | Rename to | Width (drag) |
|---|---|---|
| `LSOA[LSOA Name]` | `LSOA` | 130 |
| `LSOA[Local Authority]` | `District` | 80 |
| `LSOA[NSI Score]` | `Baseline` | 62 |
| `LSOA[NSI Band]` | `Band` | 104 |
| `LSOA[NSI Rank]` | `Rank` | 48 |
| `[NSI Rank (Custom Weights)]` | `Your rank` | 62 |
| `[Rank Change (Custom vs Default)]` | `Move` | 50 |
| `[Safety Confidence]` | `Confidence` | 74 |
| `LSOA[LSOA Code]` | `Code` | 74 |

   Set `NSI Score` and `NSI Rank` to **Don't summarize**.
3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Sort:** click `Your rank` so it sorts **ascending** (1 = safest).
5. **Format:**
   - Style preset **Minimal**; values 9 pt navy; column headers 8.5 pt Semibold, word wrap on; grid horizontal only `#E3E8EF`; totals **off**.
   - **Cell elements** › `Band` › **Background colour** fx › Field value › `[NSI Band Colour]`; **Font colour** fx › Field value › `[NSI Band Text Colour]`.
   - **Cell elements** › `Move` › **Font colour** fx › Field value › `[Rank Change Colour]` (teal = safer under your weights, coral = less safe).
   - **Cell elements** › `Confidence` › **Font colour** fx › Field value › `[Safety Confidence Colour]`.
   - **Specific column** › `Baseline`: decimal places 1.
6. **Tooltips:** tables have no Tooltips well, so the reason for each rating is shown on the **map** tooltip (`[Confidence]`) instead. Hovering a table cell shows its value only.
7. **Title:** `LSOA ranking · baseline vs your weights`. Subtitle: `sorted by your rank · Move = places gained (+) or lost (−) against the baseline rank`.
8. **Drill-through** to the LSOA Profile page is added in P7: right-clicking a row will then offer *Drill through › LSOA Profile*.

### P5-7 Interactions and reset

1. **Edit interactions:**
   - **Map**, **strip** and **table** filter each other and the four cards (default **Filter**). Clicking an LSOA anywhere shows it everywhere.
   - **Sliders** affect everything (default).
2. **Reset bookmark** (last step): set the sliders back to **50 / 20 / 20 / 10**, clear the District slicer and any selection, then add `Reset – Safety Index` (Data, Display, Current page, All visuals). Point this page's rail Reset button at it. Because the bookmark stores the slider values, Reset also restores the default weights.

### P5 validation

| # | State | Expected |
|---|---|---|
| V1 | No selection, default weights | Cards: **49.1** "Moderate · 36% in safer LSOAs" (amber bar) · **49.1** "same as baseline · weights 50 / 20 / 20 / 10" · **0** "of 860 · largest move 5 places" · **61** "29 busy centres · 32 with < 100 crimes". |
| V2 | Default weights | Table top 5: Sheffield 023D 95.0 Very high · rank 1 · your rank 1 · Low; Sheffield 041A 95.0 · 1 · 2 · −1 · Low; Rotherham 025C 94.7 · 3 · 3 · Low; Sheffield 071D 94.3 · 4 · 4 · Low; Sheffield 066C 94.2 · 5 · 5 · Low. (Small moves of 1–5 places at the default weights come from ties and rounding in the stored baseline score.) |
| V3 | No selection | Strip: rows in order Rotherham, Sheffield, Barnsley, Doncaster; navy median ticks at about **54.1, 52.9, 47.5, 42.1**; hollow dots mostly at the far right (safe, few crimes) and among the coral city-centre LSOAs on the left. |
| V4 | Sliders 25 / 25 / 25 / 25 | Card 2 **49.3** "+0.2 vs baseline · weights 25 / 25 / 25 / 25"; card 3 **66** "of 860 · largest move 192 places"; table top row **Sheffield 055A** (baseline rank 39, your rank 1, Move **+38**, Medium); the map colours shift slightly. Card 1 and the strip do **not** change. |
| V5 | District = Doncaster, default weights | Cards **43.4** "Moderate · 30% in safer LSOAs" · **43.4** · **0** "of 199 · largest move 4 places" · **9** "8 busy centres · 1 with < 100 crimes". Strip shows Doncaster only. |
| V6 | Click a dot in the strip | Map zooms to / highlights that LSOA; table shows that row only; cards show that LSOA's scores. |
| V7 | Reset filters | Sliders back to 50 / 20 / 20 / 10, district cleared; back to V1. |

---

## P6. Family Finder (flagship)

Target: `mockups\P6_Family_Finder.jpg` (where they differ, this guide wins). Question: *Where should a family with my budget and priorities look?*

**How the page works.** The buyer sets a **budget** and **five weights** on the left. Every number on the page is then recalculated for those inputs: the Family Suitability Index (FSI, 0–100), each LSOA's class, the rank, the map colours and the shortlist. Safety itself (the baseline Safety Index) does not change; only how much it counts.

**Suitability classes** (shown in the map legend, the table and the info button):

| Class | FSI | Colour |
|---|---|---|
| Excellent | 70 or more | teal `#168A86` |
| Strong | 60 – 70 | light teal `#7DB8A6` |
| Good | 50 – 60 | light slate `#A9B4C2` |
| Partial | 40 – 50 | amber `#E4A33B` |
| Weak | below 40 | coral `#D56B63` |
| Not eligible | over budget, busy town/city centre, or no price | grey `#C9D1DB` |

**Data confidence** for each LSOA: **Low** = busy centre, fewer than 100 crimes in 36 months, or house price borrowed from the wider MSOA (fewer than 10 house sales); **Medium** = 100–199 crimes or 10–19 house sales; **High** otherwise.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 900 | 22 | Text box, dynamic |
| 4 | District slicer | 1104 | 8 | 160 | 58 | Synced copy |
| 5 | KPI cards × 4 | 192 / 463 / 734 / 1004 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 6 | Your preferences panel | 192 | 178 | 300 | 504 | Shape + text + 6 slicers |
| 7 | Family fit map | 504 | 178 | 372 | 300 | Azure Maps |
| 8 | Safety vs price | 888 | 178 | 376 | 300 | Deneb |
| 9 | Shortlist | 504 | 490 | 760 | 192 | Table (core) |
| 10 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P6-1 Rail, slicer, footer, header

1. Paste the `Nav rail` group and the footer from Overview.
2. **District slicer:** View › Sync slicers › tick **Family Finder** (sync and visible). Check its position: 1104, 8, 160, 58.
3. **Title:** text box at **192, 8, 640, 36**, padding 0, clean. `Family Finder`, Segoe UI Semibold 20 pt, select the text and set **navy `#14263D`**.
4. **Subtitle:** text box at **192, 42, 900, 22**, padding 0, clean. **+ Value** › `Family Finder Subtitle`. Segoe UI 10 pt, `#536579`.
   - It reads: `South Yorkshire · budget £250,000 · weights 35 / 20 / 20 / 10 / 15 · scores change with your inputs`.

### P6-2 KPI cards

Same layout as Pages 2–5 (cards Y 76, W 260, H 90, callout 22 pt; subtitle boxes Y 142, W 232, H 18, 8 pt slate).

| Card | Card X | Value | Label | Accent bar | Subtitle box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[LSOAs Within Budget]` | LSOAs within budget | none | 206 | `Within Budget Label` |
| 2 | 463 | `[Strong Matches]` | Strong or excellent matches | teal `#168A86` (fixed) | 477 | `Strong Matches Label` |
| 3 | 734 | `[Top Match]` | Top match for your inputs | teal `#168A86` (fixed) | 748 | `Top Match Label` |
| 4 | 1004 | `[Good Value LSOAs]` | Good-value LSOAs in budget | light teal `#7DB8A6` (fixed) | 1018 | `Good Value Label` |

- Cards 1, 2 and 4: decimal places 0. Card 3 shows text (e.g. "Barnsley 024D").
- These cards always describe the whole area for your inputs: clicking an LSOA on the map, chart or table does **not** change them (set in P6-7).

### P6-3 Your preferences panel

1. **Panel:** rectangle at **192, 178, 300, 504**, padding 0; fill white; border `#D9E0E8` 1 px; rounded corners 8; clean otherwise.
2. **Heading:** text box at **204, 186, 200, 20**, padding 0, clean. `Your preferences`, Segoe UI Semibold 11 pt, navy.
3. **Badge:** `SCENARIO` (amber, as on Page 5) at **420, 188**.
4. **Budget slider:** Insert › Slicer at **200, 210, 284, 76**.
   - Field: `FSI Budget[Budget]`. Slicer settings › Style **Single value**. Set it to **£250,000** (range £100,000–£500,000 in steps of £10,000).
   - Header on, text `Budget (typical family house price)`, Segoe UI Semibold 8.5 pt navy. Values 10 pt navy. Slider colour navy `#14263D`.
   - General: padding 0; background off; border off; visual header off.
5. **Weights heading:** text box at **204, 288, 280, 18**, padding 0, clean. `What matters to your family`, Segoe UI Semibold 9 pt, `#536579`.
6. **Five weight sliders, stacked.** Insert › Slicer, five times; each **X 200, W 284, H 74**; style **Single value**; header on (Semibold 8 pt slate); values (number box) 9 pt navy; slider teal `#168A86`; General › padding 0; Effects › Background off, Visual border off. Type each default into the number box and press Enter.

| Slider | Y | Field | Header text | Default |
|---|---|---|---|---|
| A | 306 | `FSI Weight Safety[Safety Weight %]` | Safety | 35 |
| B | 380 | `FSI Weight Affordability[Affordability Weight %]` | Affordability | 20 |
| C | 454 | `FSI Weight Schools[Schools Weight %]` | Schools | 20 |
| D | 528 | `FSI Weight Family[Family Weight %]` | Family community | 10 |
| E | 602 | `FSI Weight Environment[Environment Weight %]` | Green environment | 15 |

7. **No separate live-weights text box:** the page subtitle already shows the normalised weights (`weights 35 / 20 / 20 / 10 / 15`).
8. **Information button** (Insert › Buttons › Information) at **460, 186, 20, 20**, slate. Action › Tooltip:
   `Each LSOA scores 0–100 on five things, each as a percentile across South Yorkshire: safety (Safety Index), affordability (100 when the typical family house costs half your budget or less, 0 at your budget), schools (IoD children's education), family community (share of households with dependent children) and environment (IoD living and outdoor environment). The FSI is their weighted average; weights are re-scaled to 100%. LSOAs over budget and busy town/city centres are not eligible. Classes: Excellent 70+, Strong 60–70, Good 50–60, Partial 40–50, Weak below 40.`
9. **Group** everything as `Your preferences`, with the panel rectangle at the bottom. Do **not** sync these sliders to other pages.

### P6-4 Family fit map (Azure Maps)

1. Copy the Safety Index map, paste it here and set **504, 178, 372, 300**.
2. **Tooltips** (replace; all measures): `[LSOA]`, `[District]`, `[Family Fit]`, `[Family House Price]`, `[Safety Index (baseline)]`, `[Data Confidence (Family)]`.
3. **Reference layer › Polygons › Fill colour** fx › Field value › **`[FSI Class Colour]`**.
4. **Title:** `Family fit by LSOA`. Subtitle: `for your budget and weights · grey = not eligible · click an LSOA`.
5. Remove the copied `SCENARIO` badge (the panel already carries it).
6. **Legend:** text box at **512, 452, 356, 20**; padding 0; background white 10% transparency. `■ Excellent  ■ Strong  ■ Good  ■ Partial  ■ Weak  ■ Not eligible`, Segoe UI 8 pt navy; colour each ■ with the class colour from the table above.

### P6-5 Safety vs price (Deneb)

1. Insert Deneb at **888, 178, 376, 300**. Padding 10 / 10 / 12 / 12.
2. **Fields** (add in this order; rename for this visual):

| Field | Rename to | Note |
|---|---|---|
| `LSOA[LSOA Code]` | `Code` | keeps one row per LSOA |
| `LSOA[LSOA Name]` | `LSOA` | |
| `LSOA[Local Authority]` | `District` | |
| `LSOA[Family House Price]` | `Price` | Don't summarize |
| `LSOA[NSI Score]` | `NSI` | Don't summarize |
| `LSOA[NSI Expected for Price]` | `Expected` | Don't summarize |
| `[FSI]` | `FSI` | |
| `[FSI Class]` | `Class` | |
| `[Budget Value]` | `Budget` | |

3. **Visual-level filter:** `LSOA[In South Yorkshire]` is **True**.
4. **Spec:** paste `report\deneb\P6_safety_vs_price.json`. Project setup: Tooltips on; Context menu on; **Cross-filtering on (Simple)**; Cross-highlighting off.
5. **Title:** `Safety vs house price`. Subtitle: `dashed = safety expected for price · above it = better value` (the budget line is labelled in the chart).
6. **Help tooltip:** `The dashed line is the Safety Index you would expect for an LSOA's typical family house price (fitted across South Yorkshire: each doubling of price buys about 27 points of safety). LSOAs 20+ points above the line, with a Safety Index of 50+, are counted as good value.`

### P6-6 Shortlist (core table)

1. Insert **Table** at **504, 490, 760, 192**.
2. **Columns** (in this order; rename for this visual):

| Field | Rename to | Width |
|---|---|---|
| `LSOA[LSOA Name]` | `LSOA` | 104 |
| `LSOA[Local Authority]` | `District` | 74 |
| `[FSI Class]` | `Fit` | 68 |
| `[FSI]` | `FSI` | 44 |
| `[FSI Rank]` | `Rank` | 42 |
| `LSOA[Family House Price]` | `Price` | 70 |
| `[Safety Score]` | `Safety` | 50 |
| `[Schools Score]` | `Schools` | 52 |
| `[Family Score]` | `Family` | 50 |
| `[Environment Score]` | `Environ.` | 54 |
| `[Value vs Price]` | `Value` | 48 |
| `[Family Confidence]` | `Confidence` | 70 |
| `LSOA[LSOA Code]` | `Code` | 74 |

   The five score columns are **measures** (folder `Report › Shortlist`): data bars on un-summarised columns can crash Power BI's formatting dialog. Set `LSOA[Family House Price]` to **Don't summarize**.
3. **Visual-level filters:** `LSOA[In South Yorkshire]` is **True**; `[FSI]` **is not blank** (shows eligible LSOAs only).
4. **Sort:** click `Rank` so it sorts **ascending**.
5. **Format:**
   - Style preset **Minimal**; values 9 pt navy; headers 8.5 pt Semibold, word wrap on; grid horizontal only; totals off.
   - `Price`: format `£#,##0` (Specific column › Display units None, decimals 0; the column's own format already shows £).
   - `Safety`, `Schools`, `Family`, `Environ.`: decimals 0. **Cell elements** › Data bars on each, positive colour `#7DB8A6`, minimum 0, maximum **Custom 150** (bars stop at two-thirds of the cell so the numbers stay readable); Specific column › alignment **Right**.
   - `Value`: **Font colour** fx › Field value › `[Value Colour]` (teal at +20 or more, coral at −20 or less).
   - `Fit`: **Background** fx › Field value › `[FSI Class Colour]`; **Font colour** fx › Field value › `[FSI Class Text Colour]`.
   - `Confidence`: **Font colour** fx › Field value › `[Family Confidence Colour]`.
6. **Tooltips:** tables have no Tooltips well. The confidence reason is on the **map** tooltip (`[Data Confidence (Family)]`), and each LSOA's affordability score is in the LSOA Profile component chart.
7. **Title:** `Your shortlist`. Subtitle: `ranked for your inputs · scores 0–100 (100 = best in SY) · Value = safety vs price`.

### P6-7 Interactions and reset

1. **Edit interactions:**
   - **Map**, **Deneb chart** and **table** filter each other.
   - Map, Deneb and table → **KPI cards and their subtitle boxes: None**, so the cards always summarise the area for your inputs.
   - **Sliders and District slicer** affect everything (default).
2. **Reset bookmark** (last step): budget **£250,000**, weights **35 / 20 / 20 / 10 / 15**, District cleared, nothing selected; add `Reset – Family Finder` (Data, Display, Current page, All visuals) and point this page's rail Reset button at it.

### P6 validation

| # | State | Expected |
|---|---|---|
| V1 | Default inputs (£250,000; 35/20/20/10/15) | Cards **660** "171 over budget · 29 busy centres excluded" · **136** "20 Excellent (70+) · 116 Strong (60–70)" · **Barnsley 024D** "FSI 78.3 · £240,000 · Barnsley" · **111**. |
| V2 | Default inputs | Shortlist top 5: Barnsley 024D 78.3 Excellent · 1 · £240,000 · High; Rotherham 012E 75.8 · 2 · £227,500 · Medium; Doncaster 038D 75.5 · 3 · £159,000 · High; Doncaster 007B 74.1 · 4 · £190,000 · Medium; Doncaster 014E 74.0 · 5 · £195,500 · High. |
| V3 | Budget £150,000 | Cards **216** "615 over budget · 29 busy centres excluded" · **0** "0 Excellent · 0 Strong" · **Sheffield 018D** "FSI 59.8 · £82,250 · Sheffield" · **19**. The budget line in the chart moves left; most of the map turns grey. |
| V4 | Budget £250,000; weights 60 / 10 / 20 / 0 / 10 | Card 2 **181** "91 Excellent (70+) · 90 Strong (60–70)"; card 3 **Rotherham 007E** "FSI 90.0 · £230,000 · Rotherham". |
| V5 | Default inputs; District = Doncaster | Cards **170** "21 over budget · 8 busy centres excluded" · **45** "7 Excellent · 38 Strong" · **Doncaster 038D** "FSI 75.5 · £159,000 · Doncaster" · **23**. |
| V6 | Click a dot in the chart | Map highlights that LSOA; the table shows that row; the cards do not change. |
| V7 | Reset filters | Inputs back to £250,000 and 35/20/20/10/15; back to V1. |

---

## P7. LSOA Profile & Compare

Target: `mockups\P7_LSOA_Profile.jpg` (where they differ, this guide wins). Question: *What is this neighbourhood really like, and how does it compare with my other options?*

**How the page works.**
- **Top half (profile):** one LSOA in focus. You get here by right-clicking an LSOA on the Safety Index or Family Finder page › **Drill through › LSOA Profile**, or by choosing it in the **LSOA** box on this page.
- **Bottom half (compare):** pick 2–3 LSOAs from the list to see them side by side. The comparison uses its own list (table `Compare LSOA`), so it is independent of the LSOA in focus.
- **Family fit** on this page uses the buyer's budget and weights from Family Finder (the sliders are synced in hidden form, P7-1 step 4).

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title (dynamic) | 192 | 8 | 720 | 36 | Text box |
| 3 | Page subtitle (dynamic) | 192 | 42 | 736 | 22 | Text box |
| 4 | LSOA picker | 936 | 8 | 160 | 58 | Slicer (dropdown, search) |
| 5 | Back button | 1104 | 16 | 160 | 36 | Button |
| 6 | KPI cards × 4 | 192 / 463 / 734 / 1004 | 76 | 260 | 90 | Card (new) + subtitle text box |
| 7 | Component profile | 192 | 178 | 420 | 250 | Deneb |
| 8 | Crimes by quarter | 624 | 178 | 316 | 250 | Column chart (core) |
| 9 | Crime mix | 952 | 178 | 312 | 250 | Bar chart (core) |
| 10 | Compare picker | 192 | 440 | 240 | 242 | Slicer (list, search) |
| 11 | Comparison | 444 | 440 | 820 | 242 | Matrix (core) |
| 12 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P7-1 Page set-up: drill-through, rail, header, sync

1. Paste the `Nav rail` group and the footer from Overview.
2. **Drill-through.** Select the empty canvas (no visual selected) › Visualizations › Build › **Drill through** well: drag `LSOA[LSOA Code]` in. Cross-report **Off**. **Keep all filters Off**. Power BI adds a Back button automatically; delete it (you make a styled one in step 6).
3. **Do not** sync the District slicer to this page.
4. **Sync the Family Finder inputs (hidden).** Go to Family Finder, select each of the six sliders in turn (budget + five weights) › View › **Sync slicers** › tick **LSOA Profile** in the **sync** column only (leave the eye/visible column unticked). Now Family fit here follows the buyer's inputs.
5. **Title:** text box at **192, 8, 720, 36**, padding 0, clean. **+ Value** › `Profile Title`. Segoe UI Semibold 20 pt, navy `#14263D`.
6. **Subtitle:** text box at **192, 42, 736, 22**, padding 0, clean. **+ Value** › `Profile Subtitle`. Segoe UI **9 pt**, `#536579`.
7. **LSOA picker:** Slicer at **936, 8, 160, 58**. Field `LSOA[LSOA Name]`. Style **Dropdown**; Selection: **Single select on**; Search: in the slicer's **…** menu › **Search** on. Visual-level filter `LSOA[In South Yorkshire]` is True. Header text `LSOA`. Format like the District slicer (P1-2 step 3).
8. **Back button:** Insert › Buttons › **Back** at **1104, 16, 160, 36**; padding 0; clean. Text on `‹ Back`, Segoe UI Semibold 10 pt white; icon off; fill `#2E4A6B`, hover `#3B5A80`; rounded corners 6. Action: Type **Back**.

### P7-2 KPI cards

Same layout as Pages 2–6 (cards Y 76, W 260, H 90, callout 22 pt; subtitle boxes Y 142, W 232, H 18, 8 pt slate).

| Card | Card X | Value | Label | Accent bar | Subtitle box X | Subtitle (+ Value) |
|---|---|---|---|---|---|---|
| 1 | 192 | `[Safety Index (baseline)]` | Safety Index · baseline | fx › Field value › `[NSI Band Colour]` | 206 | `Profile Safety Label` |
| 2 | 463 | `[FSI Class]` | Family fit · your inputs | fx › Field value › `[FSI Class Colour]` | 477 | `Profile Fit Label` |
| 3 | 734 | `[Family House Price]` | Typical family house price | none | 748 | `Profile Price Label` |
| 4 | 1004 | `[Crimes per 1,000 (LSOA)]` | Crimes per 1,000 a year | none | 1018 | `Profile Crime Label` |

- Card 1: decimals 1; add the navy `BASELINE` badge at **388, 84**. Card 2: add the amber `SCENARIO` badge at **659, 84**. Card 3: display units None (shows £240,000). Card 4: decimals 1.
- With no LSOA chosen the cards are blank and the title asks you to pick one. That is intended.

### P7-3 Component profile (Deneb)

1. Insert Deneb at **192, 178, 420, 250**. Padding 10 / 10 / 12 / 12.
2. **Fields** (add in this order; rename for this visual; set every column to **Don't summarize**):

| Field | Rename to |
|---|---|
| `LSOA[LSOA Code]` | `Code` |
| `LSOA[LSOA Name]` | `LSOA` |
| `LSOA[Severity Percentile]` | `Severity` |
| `LSOA[Crime Rate Percentile]` | `Crime rate` |
| `LSOA[ASB Percentile]` | `ASB` |
| `LSOA[Trend Percentile]` | `Trend` |
| `LSOA[Schools Percentile]` | `Schools` |
| `LSOA[Family Community Percentile]` | `Family` |
| `LSOA[Environment Percentile]` | `Environment` |
| `[Affordability Score]` | `Affordability` |

3. In the field well, right-click `Code` › **Show items with no data**. Without it, an LSOA whose only measure (Affordability) is blank, e.g. one over budget, drops out and the chart goes empty.
4. **Spec:** paste `report\deneb\P7_profile_components.json`. Project setup: Tooltips on; **Cross-filtering off**.
4. **Title:** `How this LSOA scores`. Subtitle: `0–100 vs all of South Yorkshire · 100 = best · amber line = middle (50)`.

With one LSOA in focus the bars are its scores. With no LSOA chosen they show the **average** of the LSOAs in view (hover a bar: "average of 860 LSOAs"), so every bar sits near 50.

### P7-4 Crimes by quarter (core column chart)

1. Insert **Clustered column chart** at **624, 178, 316, 250**.
2. X-axis `Month[Year Quarter]`; Y-axis `[Crimes (excl. ASB)]`. Sort axis by `Year Quarter` ascending.
3. Columns colour slate `#536579`; data labels on, 8 pt; Y-axis off; gridlines off; X-axis labels 8 pt.
4. **Title:** `Crimes per quarter (excl. ASB)`. Subtitle: `Oct 2023 – Sep 2026 · small numbers move a lot`.

### P7-5 Crime mix (core bar chart)

1. Insert **Clustered bar chart** at **952, 178, 312, 250**.
2. Y-axis `Crime Category[Crime Group]`; X-axis `[% of Crimes]`; tooltips `[Crimes (excl. ASB)]`.
3. Visual-level filter: `Crime Category[Is ASB]` is False. Sort by `% of Crimes` descending. Apply the P3-4 step 8 fix (Y-axis › Layout › Minimum category width 16).
4. Bars colour fx › Field value › `[Rate Bar Colour]` (largest navy, others slate). Data labels on, 8 pt, `0%`. X-axis off.
5. **Title:** `What kind of crime`. Subtitle: `share of this LSOA's crimes`.

### P7-6 Compare picker (slicer)

1. Insert **Slicer** at **192, 440, 240, 242**.
2. Field `Compare LSOA[Compare LSOA]`. Style **Vertical list**; Selection: **Single select off**, Multi-select with Ctrl **off** (so a plain click adds or removes an LSOA); "Select all" off; **…** › Search **on**.
3. Header on, text `Compare (pick 2–3)`, Semibold 9 pt navy. Values 9 pt navy. Padding 8.
4. Pre-select **Barnsley 024D**, **Rotherham 012E** and **Doncaster 038D** (type in the search box, tick each). These are the top three at the default Family Finder inputs.

### P7-7 Comparison (core matrix)

1. Insert **Matrix** at **444, 440, 820, 242**.
2. **Rows:** `Compare Metric[Metric]` (it is sorted by Metric Sort). **Columns:** `Compare LSOA[Compare LSOA]`. **Values:** `[Compare Value]`.
3. **Format:**
   - Style preset **Minimal**; row headers 9 pt navy, width about 210; column headers 9.5 pt Semibold; values 9 pt, **alignment Centre**; grid horizontal only.
   - Row subtotals **off**; column subtotals **off**; Row headers › **+/- icons off**.
   - **Sort:** the rows must follow Metric Sort (District first, Data confidence last). If they come out reversed, click the `Metric` header until the arrow points **up**, or … › Sort axis › Metric › Sort ascending.
   - Grid › **Row padding 2** so more rows fit without scrolling.
   - **Cell elements** › `Compare Value` › **Background colour** fx › Field value › `[Compare Cell Colour]`; **Font colour** fx › Field value › `[Compare Text Colour]`.
4. **Title:** `Side-by-side comparison`. **Subtitle:** on › fx › Format style **Field value** › `[Compare Note]`.
5. If a column shows only "(Blank)", the picker has no selection: tick 2–3 LSOAs.

### P7-8 Interactions and reset

1. **Edit interactions:** LSOA picker filters the cards, the three charts and the text boxes (default); set picker → matrix and picker → compare slicer to **None**. Compare slicer → everything except the matrix: **None**.
2. **Reset bookmark** (last step): LSOA picker cleared; compare picker = Barnsley 024D, Rotherham 012E, Doncaster 038D; add `Reset – LSOA Profile` (Data, Display, Current page, All visuals); point the rail Reset button at it.
3. **Drill-through from other pages.** Drill through is offered only on visuals that contain the drill-through field `LSOA[LSOA Code]`. The maps (Location) and the Deneb charts (Code) already have it; the **Safety Index** and **Family Finder** tables need a `Code` column (last column, added in P5-6 and P6-6). Then right-click an LSOA › **Drill through › LSOA Profile**. Optional: add a small text box under each table: `Right-click an LSOA › Drill through › LSOA Profile`, 8 pt slate.

### P7 validation

Use default Family Finder inputs (£250,000; 35/20/20/10/15) unless stated.

| # | State | Expected |
|---|---|---|
| V1 | LSOA picker = Barnsley 024D | Title "Barnsley 024D · Barnsley"; subtitle "MSOA Barnsley 024 · population 2,915 · data confidence: High (218 crimes · 135 house sales: robust)". Cards **91.3** "Very high safety · rank 28 of 860" · **Excellent** "FSI 78.3 · rank 1 of 660" · **£240,000** "135 house sales · value +32 vs price" · **24.9** "SY 98.7 · trend Stable". |
| V2 | Same | Components: Harm 96 (95.5), Crime rate 95, ASB 97, Trend 50, Schools 96, Family community 93, Environment 97, Affordability 8. Quarters: highest 2024 Q1 (27), lowest 2026 Q2 (10). Crime mix: Violence and sexual offences 49% (navy), then Vehicle crime 13%, Theft 11%. |
| V3 | LSOA picker = Sheffield 023D | Cards **95.0** "Very high safety · rank 1 of 860" · **Not eligible** "over budget at £250,000" (grey bar) · **£338,500** "40 house sales · value +22 vs price" · **8.1**; subtitle ends "data confidence: Low (32 crimes in 36 months)"; Affordability bar shows "over budget". |
| V4 | Compare = Barnsley 024D, Doncaster 038D, Rotherham 012E | Subtitle "Comparing 3 LSOAs · Family fit uses your Family Finder inputs". Safety Index row 91.3 · Very high (teal) / 64.7 · High (light teal) / 85.2 · Very high (teal); Safety rank 28 / 276 / 78; Crimes per 1,000 24.9 / 70.0 / 33.6; Family fit 78.3 · Excellent · rank 1 / 75.5 · Excellent · rank 3 / 75.8 · Excellent · rank 2; prices £240,000 / £159,000 / £227,500; Value +32 / +21 / +28; Data confidence High / High / Medium. |
| V5 | Family Finder budget £150,000, then open LSOA Profile with Barnsley 024D | Card 2 **Not eligible** "over budget at £150,000"; matrix Family fit row reads "Not eligible – over budget" for all three (their prices are £240,000, £227,500 and £159,000). Set the budget back to £250,000 afterwards. |
| V6 | Family Finder table › right-click Rotherham 012E › Drill through › LSOA Profile | Page opens on Rotherham 012E; ‹ Back returns to Family Finder. |
| V7 | Reset filters | Picker cleared (title "LSOA Profile · pick an LSOA"); comparison shows the three default LSOAs. |

---

## P8. Data & Method

Target: `mockups\P8_Data_and_Method.jpg` (where they differ, this guide wins). Question: *Where do the numbers come from, and how far can I trust them?*

This page is mostly text. Paste the text exactly as given; it has been checked against the model. No slicers; nothing on this page is filtered.

### Layout

| # | Object | X | Y | W | H | Type |
|---|---|---|---|---|---|---|
| 1 | Nav rail | 0 | 0 | 176 | 720 | Copy from Overview |
| 2 | Page title | 192 | 8 | 640 | 36 | Text box |
| 3 | Page subtitle | 192 | 42 | 900 | 22 | Text box |
| 4 | KPI cards × 5 | 192 / 409 / 625 / 842 / 1058 | 76 | 206 | 90 | Card (new) + subtitle text box |
| 5 | Safety Index panel | 192 | 178 | 352 | 300 | Shape + text box |
| 6 | Family Suitability panel | 556 | 178 | 352 | 300 | Shape + text box |
| 7 | Outcomes & confidence panel | 920 | 178 | 344 | 300 | Shape + text box |
| 8 | Sources panel | 192 | 490 | 352 | 192 | Shape + text box |
| 9 | Limitations panel | 556 | 490 | 352 | 192 | Shape + text box |
| 10 | Geolocation by month | 920 | 490 | 344 | 192 | Line chart (core) |
| 11 | Footer | 192 | 690 | 1072 | 22 | Copy from Overview |

### P8-1 Rail, header, footer

1. Paste the `Nav rail` group and the footer from Overview.
2. **Title:** `Data & Method`, text box at 192, 8, 640, 36; Segoe UI Semibold 20 pt navy.
3. **Subtitle:** text box at 192, 42, 900, 22; Segoe UI 10 pt slate: `How the numbers are built · sources, methods, quality checks and limits · all figures for Oct 2023 – Sep 2026`.

### P8-2 KPI cards

Five Card (new) visuals, **W 206, H 90, Y 76** (as on Overview). Subtitles are plain text boxes at Y 142, W 178, H 18, 8 pt slate, X = card X + 14.

| Card | X | Value | Label | Subtitle (type it) |
|---|---|---|---|---|
| 1 | 192 | `[Total Crimes]` | Records loaded | `449,049 crimes + 78,548 ASB` |
| 2 | 409 | `[% Crimes with Location]` | Crimes with a location | `25,599 with no LSOA` |
| 3 | 625 | `[LSOAs in Context]` | Neighbourhoods (LSOAs) | `1,430,623 residents, mid-2024` |
| 4 | 842 | `[Months in Period]` | Months of data | `Oct 2023 – Sep 2026` |
| 5 | 1058 | `[Sales Count]` | House sales | `44,289 houses · Land Registry` |

Formats: card 1 and 5 display units None (527,597; 47,943); card 2 one decimal (95.2%).

### P8-3 Text panels

Each panel is two objects: a **white rounded rectangle** (the card) and a **text box** sitting inside it, 12 px in from the left and right and 10 px in from the top and bottom.

| Panel | Rectangle X, Y, W, H | Text box X, Y, W, H |
|---|---|---|
| 5 · Safety Index | 192, 178, 352, 300 | 204, 188, 328, 280 |
| 6 · Family Suitability | 556, 178, 352, 300 | 568, 188, 328, 280 |
| 7 · Outcomes & confidence | 920, 178, 344, 300 | 932, 188, 320, 280 |
| 8 · Sources | 192, 490, 352, 192 | 204, 500, 328, 172 |
| 9 · Limitations | 556, 490, 352, 192 | 568, 500, 328, 172 |

**Build panel 5 first, then copy it for the others:**
1. **Rectangle:** Insert › Shapes › Rectangle. Size/position from the table. Style › Fill **white**; Border **on**, `#D9E0E8`, width 1; Rounded corners **8**. General › Padding 0, Shadow off.
2. **Text box:** Insert › Text box. Size/position from the table. General › Padding **0**; Effects › Background **off**, Visual border **off**.
3. **Text:** copy the block for that panel (below, between the ``` lines) and paste it into the text box. Each line already starts with `•`.
4. **Format the text:** select all (Ctrl+A) and set Segoe UI **8.5 pt**, colour `#14263D`. Then select only the **first line** (the heading) and set Segoe UI **Semibold 11 pt**.
5. **Group:** in the Selection pane select the rectangle and the text box › right-click › Group; name it `Panel – Safety Index`. The rectangle must be below the text box in the group.
6. **Copy for the next panel:** select the group › Ctrl+C › Ctrl+V; set the rectangle and text box to the next row of the table; replace the text.

If the text overflows the card, reduce the body to **8 pt** (leave the heading at 11 pt).

**Panel 5 · Safety Index (NSI) · baseline**
```
Neighbourhood Safety Index (NSI) · baseline
• One score per LSOA (860), from 36 months of police.uk data. Weights: harm 50%, crime rate 20%, anti-social behaviour 20%, trend 10%.
• Harm weights each crime by the ONS Crime Severity Score (typical custody-days for that offence). Our force total, 20.57, matches the ONS published 20.58.
• Small-area rates are smoothed towards the district rate (empirical Bayes), so LSOAs with few crimes are not ranked on noise.
• Trend: last 12 vs prior 12 months, tested for significance with an over-dispersion correction (φ = 3.82).
• Each part becomes a percentile (100 = safest); the NSI is their weighted average. Bands: 80+ Very high · 60–80 High · 40–60 Moderate · 20–40 Low · under 20 Very low.
• 29 busy town and city centres (rate over 3× the county median) are flagged: visitors inflate their rates.
```

**Panel 6 · Family Suitability (FSI) · your inputs**
```
Family Suitability Index (FSI) · your inputs
• Five parts, each a percentile across South Yorkshire: safety (NSI), affordability, schools (IoD 2025 children's education), family community (households with dependent children, Census 2021), environment (IoD 2025 living and outdoor environment).
• Affordability = 200 × (1 − price ÷ budget), capped at 100: 100 at half the budget or less, 0 at the budget.
• Default weights 35 / 20 / 20 / 10 / 15; the sliders are re-scaled to 100%.
• Not eligible: over budget, busy centre, or no price.
• Price: median of houses sold in the LSOA (HM Land Registry, standard sales); the wider MSOA median where there were fewer than 10 sales (16 LSOAs).
• Value vs price: the NSI compared with the NSI expected for the price (about +27 points per doubling of price, R² 0.38). Good value = 20+ points above, with an NSI of 50+.
```

**Panel 7 · Outcomes & confidence**
```
Outcomes and data confidence
• Each crime counts once, with its latest police.uk status. Outcome KPIs use crimes at least 6 months old (up to Mar 2026), because outcomes take months to be recorded.
• Positive outcome = charged or summonsed (including "court result unavailable") or an out-of-court resolution. It is not a conviction rate.
• LSOA confidence: Low = busy centre, under 100 crimes in 36 months, or MSOA price; Medium = 100–199 crimes or 10–19 house sales; High otherwise.
• Baseline (navy badge) = fixed weights, identical on every page. Scenario (amber badge) = your weights or budget.
```

**Panel 8 · Sources** (heading `Sources`)
```
Sources
• police.uk street-level crime, ASB and outcomes, South Yorkshire Police, Oct 2023 – Sep 2026
• ONS mid-2024 population estimates by LSOA
• English Indices of Deprivation 2025 (MHCLG)
• Census 2021 (ONS): households and tenure
• HM Land Registry Price Paid Data, Oct 2023 – Sep 2026
• ONS Crime Severity Score weights; Home Office offence counts
• ONS LSOA (Dec 2021) generalised boundaries
```

**Panel 9 · Limitations** (heading `Limitations`)
```
Limitations
• Locations are anonymised; 4.8% of crimes have no location and count only in force totals.
• Rates use residents, so centres, stations and retail parks look worse than residents experience.
• Recorded crime reflects reporting and recording, not all crime.
• Scores are relative: "safer than most of South Yorkshire", not risk-free.
• Prices are medians of recent sales, not valuations; few sales mean more uncertainty.
• The schools measure is an area indicator, not school results or catchments.
```

If a panel's text overflows, reduce the body to 8 pt; do not shrink the heading.

### P8-4 Geolocation by month (core line chart)

1. Insert **Line chart** at **920, 490, 344, 192**.
2. X-axis `Month[Month Start]` (choose Month Start, not the hierarchy); Y-axis `[% Crimes with Location]`.
3. Line teal `#168A86`, width 2; markers off; Y-axis **min 0.9, max 1** (Range), format 0%; X-axis 8 pt; gridlines `#E3E8EF`.
4. **Title:** `Crimes with a location, by month`. Subtitle: `quality check · 92–96% every month`.

### P8-5 Reset

Add `Reset – Data & Method` (Data, Display, Current page, All visuals) and point the rail Reset button at it.

### P8 validation

| # | Check | Expected |
|---|---|---|
| V1 | Cards | **527,597** · **95.2%** · **860** · **36** · **47,943**. |
| V2 | Line chart | 36 points between about **92%** and **96%**; lowest Jul 2026 (91.9%) and Jan 2026 (93.1%). |
| V3 | Text panels | All five panels readable without scrolling at 1280 × 720. |
| V4 | Rail | "Data & Method" highlighted; Reset button works. |

---

## Final check across all pages (after P8)

1. Click through all eight pages with the rail: each highlights correctly, each Reset works.
2. **Selection pane:** every page's objects are named (e.g. `KPI P6-2`, `Map – Family fit`) so tab order and screen readers make sense.
3. **Performance analyzer** (Optimize › Performance analyzer › Start recording › Refresh visuals) on Family Finder and Safety Index: send me the slowest visual's DAX query time if any is over 1 second.
4. Save a copy as `SY_Crime_Property_v1.pbix`.
