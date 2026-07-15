# Vehicle Registrations in Ukraine 2019–2025
### How COVID and War Reshaped the Automotive Market — a PostgreSQL + Tableau Case Study

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?style=flat&logo=postgresql&logoColor=white)
![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?style=flat&logo=tableau&logoColor=white)
![Data](https://img.shields.io/badge/Dataset-14.5M%20rows-2E86AB?style=flat)
![Period](https://img.shields.io/badge/Period-2019--2025-1D9E75?style=flat)
![Status](https://img.shields.io/badge/Status-Completed-1D9E75?style=flat)

---

## Project Overview

This is my second portfolio case study (after the [Cyclistic bike-share capstone](https://github.com/osynichenko/Cyclistic_Bike_Share_Analysis)). It analyzes **14,497,205 vehicle registration operations** from the open data registry of the Ministry of Internal Affairs of Ukraine, spanning **2019–2025** — a period that includes the COVID-19 pandemic and the full-scale russian invasion.

**Central question:**
> *What do Ukrainians drive — and how did two crises (pandemic and war) change the automotive market?*

🔗 **Interactive visualizations:** [Tableau Public — collection "Vehicle registrations in Ukraine 2019 2025"](https://public.tableau.com/app/profile/oleksandr.synichenko/vizzes)

---

## Data

| Parameter | Details |
|-----------|---------|
| **Source** | [data.gov.ua — MVS Ukraine, vehicle registration open data](https://data.gov.ua/dataset/06779371-308f-42d7-895e-5a39833375f0) |
| **Period** | 7 annual CSV files, 2019–2025 |
| **Raw size** | ~5 GB / 14,497,205 rows |
| **Structure** | 2019–2020: 19 columns (no VIN); 2021–2025: 20 columns |
| **Encoding** | UTF-8, `;`-delimited, quoted values |

**Privacy note:** the registry contains no personal identifiers; analysis is performed on aggregate level only.

---

## Tools

| Tool | Purpose |
|------|---------|
| **PostgreSQL 18** (Homebrew, macOS) | ETL, data quality diagnostics, all analysis (SQL) |
| **psql / pgAdmin 4** | Loading (`\copy`), query development |
| **Tableau Public** | 9 published visualizations |
| **GitHub** | Version control, documentation |

---

## Methodology

### Three-layer architecture

```
7 CSV files ──▶ tz_staging (all TEXT, buffer) ──▶ tz_raw (mirror of source + source_year)
                                                        │  typing & value-level cleaning
                                                        ▼
                                                  tz_clean (typed analytical layer)
                                                        + koatuu_regions (27 regions)
                                                        + oper_directory (145 operation codes → 22 categories)
```

Key principles (several learned the hard way — see *Lessons*):

- **Raw data is immutable.** Cleaning produces new tables; broken *values* become NULL, *rows are never deleted*.
- **Every load is verified twice:** `COPY N = INSERT N`, and totals per `source_year` must equal `wc -l` of the source file minus header. This verification caught two real loading errors (year mislabeling; cumulative duplicates).
- **Operation codes, not names.** One `oper_code` appears in the registry with up to 3 spelling variants of its name. All grouping is done by code; the "canonical" name is the *most frequent* variant (`DISTINCT ON` + frequency sort), never `MIN(name)` — alphabetical choice had silently mislabeled used-car imports as new cars.
- **Hypothesis ≠ fact.** Every "obvious" claim was tested against the data. Some were confirmed (wartime code 213 first appears in 2022; code 71 is used-car import — 70%+ of vehicles aged 6–20 years), some refuted (trailer production did *not* grow during the war; "BA3" was not a Latin-alphabet duplicate of "ВАЗ" but a homoglyph illusion — the real duplicate was LADA).

### Documented data-quality findings

| Finding | Scale | Decision |
|---|---|---|
| Two date formats (`dd.mm.yyyy` in 2019–2022, `dd.mm.yy` in 2023–2025) | 100% of rows | Two-branch CASE in typing; 0 dates lost |
| Comma decimals (`105,5`) in own_weight | 8,435 values | REPLACE + regex guard |
| Missing KOATUU (owner region) in 2020 | **404,584 rows (~23% of the year)**, systematically from May 2020 | Rows kept; regional analysis of 2020 runs on ~77% coverage with explicit disclaimer |
| April 2020 collapse: 6,984 operations vs typical 150–200K/month | — | Not an error: first COVID lockdown fingerprint |
| Unknown region prefix `52` | 18 rows of 14M | → unknown |
| Brand duplicates (ВАЗ + LADA) | 10,288 rows | Merged — and this 1.4% **flipped the regional leader of Zaporizhzhia oblast** (gap: 457 operations) |

---

## Key Findings

### 1. The market runs on used cars
The secondary market (ownership changes incl. e-services) accounts for **51.3%** of all operations. **Used-car imports (19.4%) outnumber new-car registrations (6.7%) three to one.**

### 2. Two crises, two different fingerprints
- **COVID:** April 2020 — market-wide collapse to 6,984 operations (−96%).
- **War:** March 2022 — used imports drop to 9,144 (−74%); but the *annual* 2022 figure looks decent only because of the **zero-customs-duty window (Apr–Jun 2022)**: monthly data shows a ×2.5 spike (May 88.5K, June 95.4K), a July tail, then a wartime plateau of ~21K/month vs ~35K pre-war. *Annual aggregation masked three opposite events inside one year.*

### 3. Geography of taste: a Volkswagen empire with a VAZ east
VW leads in ~20 of 25 analyzed regions. VAZ holds the east/south-east (Donetsk, Luhansk, Zaporizhzhia, Kirovohrad); Toyota rules Odesa. Crimea and Sevastopol are shown on the map as **"no data"** (occupied since 2014; 4,224 + 982 operations total) — absence of data displayed as absence of data.

### 4. The EV boom accelerated through the war
Pure-electric registrations grew **×15.5** (11,920 → 185,223), with 2025 nearly doubling 2024. **In 2025 Tesla Model 3 dethroned Nissan Leaf** after six years of Leaf dominance. China-market models (Honda M-NV, BYD Song Plus, VW ID.4 Crozz) signal a new import wave — visible in the top-20, not yet on the podium.

### 5. "Made in Ukraine" = Škoda and trailers
The biggest "Ukrainian-made" passenger car is **Škoda assembled by Eurocar in Zakarpattia**; the industry's true mass product is trailers. Buses fully recovered after 2022; passenger assembly keeps fading: **−81% from the 2021 peak** by 2025 — production resumed (per manufacturer), demand did not.

### 6. What color is Ukraine on the roads?
**71% of passenger-car operations involve shades of gray** (gray 32.7% + black 21.9% + white 16.4%).

---

## Visualizations (Tableau Public)

1. **Heat map of vehicle registration 2019–2025** — 22 categories × 7 years, row-normalized; white gaps = category didn't exist (wartime from 2022, Diia from 2023)
2. **The most popular car brands by region** — filled map, top-3 per oblast via Viz in Tooltip, Crimea as neutral "no data"
3. **Dynamics of used-car imports in 2022** — the zero-customs-duty fingerprint, month by month
4. **Dynamics of EV registrations 2019–2025** — the ×15.5 curve
5. **The EV throne race** — bump chart: Tesla Model 3 dethrones Nissan Leaf in 2025
6. **TOP-20 electric vehicles**
7. **Ukrainian automotive industry after 2022** — by vehicle type
8. **Škoda made in Zakarpattia** — 84-month "pulse" line with COVID/war annotations
9. **What color is Ukraine on the roads?** — colors rendered as themselves

🔗 All live at: [public.tableau.com/app/profile/oleksandr.synichenko](https://public.tableau.com/app/profile/oleksandr.synichenko/vizzes)

---

## Repository Structure

```
ukraine-vehicle-registrations/
│
├── README.md                        # This file
├── docs/
│   └── handbook.md                  # Full step-by-step methodology handbook (UA)
├── sql/
│   ├── 01_schema.sql                # staging / raw / clean DDL
│   ├── 02_load.sh                   # Loading script (\copy loop with verification)
│   ├── 03_diagnostics.sql           # Data-quality checks
│   ├── 04_build_clean.sql           # Typed layer
│   ├── 05_dictionaries.sql          # koatuu_regions, oper_directory
│   └── 06_analysis.sql              # All analytical queries
└── data/                            # (not uploaded — ~5 GB; see source link)
```

---

## How to Reproduce

1. Download 7 annual CSVs (2019–2025) from [data.gov.ua](https://data.gov.ua/dataset/06779371-308f-42d7-895e-5a39833375f0).
2. `createdb tz_registry` → run `sql/01_schema.sql`.
3. Load: `sql/02_load.sh` (note: 2019–2020 files have 19 columns — the script passes an explicit column list so VIN becomes NULL). Verify row counts against `wc -l`.
4. Run diagnostics → build `tz_clean` → dictionaries → analysis queries.
5. Export result CSVs → connect in Tableau Public.

---

## Lessons Learned (the honest section)

1. Verification catches what eyes don't: two loading errors and one "ghost table" (uncommitted pgAdmin transaction) were caught by routine count checks.
2. `MIN(text)` is an alphabetical lottery, not a representative name.
3. Homoglyphs are real: Cyrillic ВАЗ renders identically to Latin "BA3". Check duplicates with queries, not eyes.
4. Small volume ≠ small impact: merging a 1.4% brand duplicate flipped a regional leader decided by 457 operations.
5. Annual aggregates hide intra-year drama — monthly resolution is mandatory for crisis periods.
6. External context (laws, lockdowns, manufacturer news) is a source of *hypotheses*, not conclusions — until its fingerprint is found in the data.
7. We count *operations*, not the car fleet — and every chart says so.

---

## Author

**Oleksandr Synichenko**
IT Professional | Data Analytics

[LinkedIn](https://www.linkedin.com/in/itspecotonopts/) · [Tableau Public](https://public.tableau.com/app/profile/oleksandr.synichenko/vizzes)

---

## License & Attribution

Source data © Ministry of Internal Affairs of Ukraine, published as open data on [data.gov.ua](https://data.gov.ua). This project is for educational and portfolio purposes.
