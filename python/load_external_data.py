#!/usr/bin/env python3
"""
load_external_data.py
---------------------
Loads the Phase 4 external datasets into PostgreSQL, unchanged, in schema
external_raw of database CrimeData. Every value is stored as text exactly
as published, plus the source file / sheet / row for traceability.
Cleaning and typing happen later in SQL (analytics schema).

Files expected in --folder (names can differ; matched by pattern):
  *Population*.xlsx / sape*.xlsx   ONS LSOA population, mid-2022 to mid-2024
  *Deprivation*.csv / File_7*.csv  English Indices of Deprivation 2025, File 7
  census2021-ts003.zip             Census 2021 household composition (bulk)
  census2021-ts054.zip             Census 2021 tenure (bulk)

Each file's header is checked against the published layout; a file that
does not match is reported and skipped, never half-loaded.
Re-running replaces the tables' contents (safe to repeat).

Usage
  python load_external_data.py --folder "C:\\...\\Crime Rate Analysis\\external_data"

Requirements: psycopg2-binary, openpyxl   (pip install openpyxl)
"""

from __future__ import annotations

import argparse
import csv
import getpass
import io
import os
import sys
import zipfile
from pathlib import Path

import psycopg2

DB_NAME = "CrimeData"
SCHEMA = "external_raw"

# --------------------------------------------------------------------------
# Expected layouts: (target column name, expected source header)
# Headers are compared case-insensitively on their start, so small wording
# changes (e.g. LAD 2021 vs LAD 2023) are tolerated where marked with "".
# --------------------------------------------------------------------------
POP_COLUMNS = [
    ("lad_code", "LAD 20"), ("lad_name", "LAD 20"), ("lsoa_code", "LSOA 2021 Code"),
    ("lsoa_name", "LSOA 2021 Name"), ("total", "Total"),
    ("f_0_15", "F0 to 15"), ("f_16_29", "F16 to 29"), ("f_30_44", "F30 to 44"),
    ("f_45_64", "F45 to 64"), ("f_65_plus", "F65 and over"),
    ("m_0_15", "M0 to 15"), ("m_16_29", "M16 to 29"), ("m_30_44", "M30 to 44"),
    ("m_45_64", "M45 to 64"), ("m_65_plus", "M65 and over"),
]
MEDIAN_AGE_COLUMNS = [
    ("lad_code", "LAD 20"), ("lad_name", "LAD 20"), ("lsoa_code", "LSOA 2021 Code"),
    ("lsoa_name", "LSOA 2021 Name"), ("median_age_2024", "Median age mid-2024"),
    ("median_age_2023", "Median age mid-2023"), ("median_age_2022", "Median age mid-2022"),
]
IOD_COLUMNS = [
    ("lsoa_code", "LSOA code (2021)"), ("lsoa_name", "LSOA name (2021)"),
    ("lad_code", "Local Authority District code"), ("lad_name", "Local Authority District name"),
    ("imd_score", "Index of Multiple Deprivation (IMD) Score"),
    ("imd_rank", "Index of Multiple Deprivation (IMD) Rank"),
    ("imd_decile", "Index of Multiple Deprivation (IMD) Decile"),
    ("income_score", "Income Score"), ("income_rank", "Income Rank"), ("income_decile", "Income Decile"),
    ("employment_score", "Employment Score"), ("employment_rank", "Employment Rank"),
    ("employment_decile", "Employment Decile"),
    ("education_score", "Education, Skills and Training Score"),
    ("education_rank", "Education, Skills and Training Rank"),
    ("education_decile", "Education, Skills and Training Decile"),
    ("health_score", "Health Deprivation and Disability Score"),
    ("health_rank", "Health Deprivation and Disability Rank"),
    ("health_decile", "Health Deprivation and Disability Decile"),
    ("crime_score", "Crime Score"), ("crime_rank", "Crime Rank"), ("crime_decile", "Crime Decile"),
    ("barriers_score", "Barriers to Housing and Services Score"),
    ("barriers_rank", "Barriers to Housing and Services Rank"),
    ("barriers_decile", "Barriers to Housing and Services Decile"),
    ("living_env_score", "Living Environment Score"), ("living_env_rank", "Living Environment Rank"),
    ("living_env_decile", "Living Environment Decile"),
    ("idaci_score", "Income Deprivation Affecting Children Index (IDACI) Score"),
    ("idaci_rank", "Income Deprivation Affecting Children Index (IDACI) Rank"),
    ("idaci_decile", "Income Deprivation Affecting Children Index (IDACI) Decile"),
    ("idaopi_score", "Income Deprivation Affecting Older People (IDAOPI) Score"),
    ("idaopi_rank", "Income Deprivation Affecting Older People (IDAOPI) Rank"),
    ("idaopi_decile", "Income Deprivation Affecting Older People (IDAOPI) Decile"),
    ("cyp_score", "Children and Young People Sub-domain Score"),
    ("cyp_rank", "Children and Young People Sub-domain Rank"),
    ("cyp_decile", "Children and Young People Sub-domain Decile"),
    ("adult_skills_score", "Adult Skills Sub-domain Score"),
    ("adult_skills_rank", "Adult Skills Sub-domain Rank"),
    ("adult_skills_decile", "Adult Skills Sub-domain Decile"),
    ("geo_barriers_score", "Geographical Barriers Sub-domain Score"),
    ("geo_barriers_rank", "Geographical Barriers Sub-domain Rank"),
    ("geo_barriers_decile", "Geographical Barriers Sub-domain Decile"),
    ("wider_barriers_score", "Wider Barriers Sub-domain Score"),
    ("wider_barriers_rank", "Wider Barriers Sub-domain Rank"),
    ("wider_barriers_decile", "Wider Barriers Sub-domain Decile"),
    ("indoors_score", "Indoors Sub-domain Score"), ("indoors_rank", "Indoors Sub-domain Rank"),
    ("indoors_decile", "Indoors Sub-domain Decile"),
    ("outdoors_score", "Outdoors Sub-domain Score"), ("outdoors_rank", "Outdoors Sub-domain Rank"),
    ("outdoors_decile", "Outdoors Sub-domain Decile"),
    ("pop_total_2022", "Total population: mid 2022"),
    ("pop_children_0_15_2022", "Dependent Children aged 0-15: mid 2022"),
    ("pop_older_60_plus_2022", "Older population aged 60 and over: mid 2022"),
    ("pop_working_age_2022", "Working age population 18-66"),
]
_HC = "Household composition: "
TS003_COLUMNS = [
    ("census_date", "date"), ("lsoa_name", "geography"), ("lsoa_code", "geography code"),
    ("hh_total", _HC + "Total"),
    ("hh_one_person", _HC + "One person household; "),
    ("hh_one_person_66_plus", _HC + "One person household: Aged 66"),
    ("hh_one_person_other", _HC + "One person household: Other"),
    ("hh_single_family", _HC + "Single family household; "),
    ("hh_family_all_66_plus", _HC + "Single family household: All aged 66"),
    ("hh_married", _HC + "Single family household: Married or civil partnership couple; "),
    ("hh_married_no_children", _HC + "Single family household: Married or civil partnership couple: No children"),
    ("hh_married_dependent_children", _HC + "Single family household: Married or civil partnership couple: Dependent children"),
    ("hh_married_nondependent_children", _HC + "Single family household: Married or civil partnership couple: All children non-dependent"),
    ("hh_cohabiting", _HC + "Single family household: Cohabiting couple family; "),
    ("hh_cohabiting_no_children", _HC + "Single family household: Cohabiting couple family: No children"),
    ("hh_cohabiting_dependent_children", _HC + "Single family household: Cohabiting couple family: With dependent children"),
    ("hh_cohabiting_nondependent_children", _HC + "Single family household: Cohabiting couple family: All children non-dependent"),
    ("hh_lone_parent", _HC + "Single family household: Lone parent family; "),
    ("hh_lone_parent_dependent_children", _HC + "Single family household: Lone parent family: With dependent children"),
    ("hh_lone_parent_nondependent_children", _HC + "Single family household: Lone parent family: All children non-dependent"),
    ("hh_other_single_family", _HC + "Single family household: Other single family household; "),
    ("hh_other_single_family_other", _HC + "Single family household: Other single family household: Other"),
    ("hh_other_types", _HC + "Other household types; "),
    ("hh_other_types_dependent_children", _HC + "Other household types: With dependent children"),
    ("hh_other_types_other", _HC + "Other household types: Other, including"),
]
_T = "Tenure of household: "
TS054_COLUMNS = [
    ("census_date", "date"), ("lsoa_name", "geography"), ("lsoa_code", "geography code"),
    ("ten_total", _T + "Total"), ("ten_owned", _T + "Owned"),
    ("ten_owned_outright", _T + "Owned: Owns outright"),
    ("ten_owned_mortgage", _T + "Owned: Owns with a mortgage"),
    ("ten_shared_ownership", _T + "Shared ownership"),
    ("ten_shared_ownership_detail", _T + "Shared ownership: Shared ownership"),
    ("ten_social_rented", _T + "Social rented"),
    ("ten_social_rented_council", _T + "Social rented: Rents from council"),
    ("ten_social_rented_other", _T + "Social rented: Other social rented"),
    ("ten_private_rented", _T + "Private rented"),
    ("ten_private_rented_landlord", _T + "Private rented: Private landlord"),
    ("ten_private_rented_other", _T + "Private rented: Other private rented"),
    ("ten_rent_free", _T + "Lives rent free"),
]


def check_header(actual: list[str], spec: list[tuple[str, str]], label: str) -> None:
    if len(actual) < len(spec):
        raise ValueError(f"{label}: expected {len(spec)} columns, found {len(actual)}")
    for i, (target, expected) in enumerate(spec):
        got = (actual[i] or "").strip()
        if not got.lower().startswith(expected.lower()):
            raise ValueError(f"{label}: column {i + 1} is '{got}', expected it to start with '{expected}'")


def text(v) -> str:
    if v is None:
        return ""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v).strip()


# --------------------------------------------------------------------------
# Readers: each yields (rows, label) with rows = list of lists of text
# --------------------------------------------------------------------------
def read_population(path: Path):
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    out_pop, out_age = [], []
    for ws in wb.worksheets:
        title = ws.title.strip()
        is_pop = title.startswith("Mid-") and "LSOA 2021" in title
        is_age = title.lower().startswith("median age")
        if not (is_pop or is_age):
            continue
        rows = ws.iter_rows(values_only=True)
        header, n = None, 0
        for r in rows:
            n += 1
            if r and r[2] is not None and str(r[2]).strip().lower().startswith("lsoa 2021 code"):
                header = [text(c) for c in r]
                break
        if header is None:
            raise ValueError(f"{path.name} / {title}: header row not found")
        spec = POP_COLUMNS if is_pop else MEDIAN_AGE_COLUMNS
        check_header(header, spec, f"{path.name} / {title}")
        idx = list(range(len(spec))) if is_pop else [0, 1, 2, 3] + [header.index(h) for _, h in spec[4:]]
        year = title.split()[0].replace("Mid-", "") if is_pop else None
        for r in rows:
            n += 1
            vals = [text(r[i]) if i < len(r) else "" for i in idx]
            if not vals[2]:                       # skip blank / footnote rows
                continue
            rec = vals + [path.name, title, n]
            (out_pop if is_pop else out_age).append(([year] if is_pop else []) + rec)
    return out_pop, out_age


def read_csv_rows(fh, spec, label):
    r = csv.reader(fh)
    header = next(r)
    check_header(header, spec, label)
    rows = []
    for i, row in enumerate(r, start=2):
        if not any(c.strip() for c in row):
            continue
        rows.append([c.strip() for c in row[:len(spec)]] + [label, "", i])
    return rows


def read_iod(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as fh:
        return read_csv_rows(fh, IOD_COLUMNS, path.name)


def read_census_zip(path: Path, table: str, spec):
    with zipfile.ZipFile(path) as zf:
        name = next((n for n in zf.namelist() if n.lower().endswith(f"{table}-lsoa.csv")), None)
        if name is None:
            raise ValueError(f"{path.name}: no '{table}-lsoa.csv' inside the zip")
        with zf.open(name) as raw:
            fh = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
            return read_csv_rows(fh, spec, f"{path.name}/{name}")


# --------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------
def replace_table(conn, table: str, columns: list[str], rows: list[list]) -> int:
    cols_sql = ", ".join(f"{c} TEXT" for c in columns)
    with conn.cursor() as cur:
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS {SCHEMA}")
        # create once, then empty and refill: views built on these tables stay intact
        cur.execute(f"""CREATE TABLE IF NOT EXISTS {SCHEMA}.{table} ({cols_sql},
                         source_file TEXT NOT NULL, source_sheet TEXT, source_row INTEGER NOT NULL,
                         loaded_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
        cur.execute(f"TRUNCATE {SCHEMA}.{table}")
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\n")
        w.writerows(rows)
        buf.seek(0)
        cur.copy_expert(f"COPY {SCHEMA}.{table} ({', '.join(columns)}, source_file, source_sheet, source_row) "
                        f"FROM STDIN WITH (FORMAT csv)", buf)
        cur.execute(f"CREATE INDEX IF NOT EXISTS ix_{table}_lsoa ON {SCHEMA}.{table} (lsoa_code)")
    conn.commit()
    return len(rows)


def find(folder: Path, patterns: list[str]) -> Path | None:
    for p in patterns:
        hits = sorted(folder.glob(p))
        if hits:
            return hits[0]
    return None


def main():
    ap = argparse.ArgumentParser(description="Load Phase 4 external datasets (raw) into PostgreSQL.")
    ap.add_argument("--folder", required=True)
    ap.add_argument("--host", default=os.getenv("PGHOST", "localhost"))
    ap.add_argument("--port", type=int, default=int(os.getenv("PGPORT", "5432")))
    ap.add_argument("--user", default=os.getenv("PGUSER", "postgres"))
    ap.add_argument("--password", default=os.getenv("PGPASSWORD"))
    args = ap.parse_args()
    if args.password is None:
        args.password = getpass.getpass(f"PostgreSQL password for user '{args.user}': ")

    folder = Path(args.folder).expanduser()
    conn = psycopg2.connect(host=args.host, port=args.port, user=args.user,
                            password=args.password, dbname=DB_NAME)

    jobs = [
        ("population", ["*Population*.xlsx", "*population*.xlsx", "sape*.xlsx"]),
        ("iod", ["*Deprivation*.csv", "*deprivation*.csv", "File_7*.csv", "*IoD2025*.csv"]),
        ("ts003", ["census2021-ts003*.zip"]),
        ("ts054", ["census2021-ts054*.zip"]),
    ]
    failures = 0
    for job, patterns in jobs:
        path = find(folder, patterns)
        if path is None:
            print(f"  {job}: no file matching {patterns} - skipped")
            failures += 1
            continue
        try:
            if job == "population":
                pop, age = read_population(path)
                n1 = replace_table(conn, "ons_population_lsoa", ["mid_year"] + [c for c, _ in POP_COLUMNS], pop)
                n2 = replace_table(conn, "ons_median_age_lsoa", [c for c, _ in MEDIAN_AGE_COLUMNS], age)
                print(f"  {path.name}: ons_population_lsoa {n1:,} rows, ons_median_age_lsoa {n2:,} rows")
            elif job == "iod":
                n = replace_table(conn, "iod2025_lsoa", [c for c, _ in IOD_COLUMNS], read_iod(path))
                print(f"  {path.name}: iod2025_lsoa {n:,} rows")
            elif job == "ts003":
                n = replace_table(conn, "census_ts003_lsoa", [c for c, _ in TS003_COLUMNS],
                                  read_census_zip(path, "ts003", TS003_COLUMNS))
                print(f"  {path.name}: census_ts003_lsoa {n:,} rows")
            else:
                n = replace_table(conn, "census_ts054_lsoa", [c for c, _ in TS054_COLUMNS],
                                  read_census_zip(path, "ts054", TS054_COLUMNS))
                print(f"  {path.name}: census_ts054_lsoa {n:,} rows")
        except Exception as e:  # noqa: BLE001
            conn.rollback()
            failures += 1
            print(f"  {path.name}: FAILED - {e}")
    conn.close()
    print("Done." if failures == 0 else f"Done with {failures} problem(s) - see above.")


if __name__ == "__main__":
    main()
