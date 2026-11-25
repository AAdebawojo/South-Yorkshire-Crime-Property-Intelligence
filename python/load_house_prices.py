#!/usr/bin/env python3
"""
load_house_prices.py
--------------------
Loads HM Land Registry Price Paid Data (yearly files) and the ONS
postcode -> LSOA lookup into PostgreSQL schema external_raw (CrimeData),
unchanged, as text, keeping only what South Yorkshire needs:

  external_raw.land_registry_ppd   sales whose District is Barnsley,
                                   Doncaster, Rotherham or Sheffield
  external_raw.ons_postcode_lsoa   lookup rows for (a) every postcode that
                                   appears in those sales, and (b) every
                                   postcode in the four local authorities
                                   (needed for the LSOA -> MSOA fallback)

Expected in --folder:
  pp-YYYY.csv                      Price Paid yearly files (no header row)
  *postcode*.csv / *lookup*.csv    ONS "Postcode to OA (2021) to LSOA to
                                   MSOA to LAD Best Fit Lookup" (with header)

Price Paid Data: Contains HM Land Registry data (c) Crown copyright and
database right. Licensed under the Open Government Licence v3.0.

Usage
  python load_house_prices.py --folder "C:\\...\\Crime Rate Analysis\\external_data"
Requirements: psycopg2-binary
"""

from __future__ import annotations

import argparse
import csv
import getpass
import io
import os
import sys
from pathlib import Path

import psycopg2

DB_NAME = "CrimeData"
SCHEMA = "external_raw"
SY_DISTRICTS = {"BARNSLEY", "DONCASTER", "ROTHERHAM", "SHEFFIELD"}
SY_LAD_CODES = {"E08000016", "E08000017", "E08000018", "E08000019"}

# Published Price Paid column order (the files have no header row)
PPD_COLUMNS = ["transaction_id", "price", "date_of_transfer", "postcode", "property_type",
               "old_new", "duration", "paon", "saon", "street", "locality", "town_city",
               "district", "county", "ppd_category", "record_status"]

# Lookup columns we need, with accepted header spellings (case-insensitive)
LOOKUP_FIELDS = {
    "pcds":     ["pcds", "pcd8", "pcd7", "pcd", "pcd2", "postcode"],
    "doterm":   ["doterm"],
    "oa21cd":   ["oa21cd", "oa21"],
    "lsoa21cd": ["lsoa21cd", "lsoa21", "lsoa21cd_"],
    "msoa21cd": ["msoa21cd", "msoa21"],
    "msoa21nm": ["msoa21nm"],
    "ladcd":    ["ladcd", "lad25cd", "lad24cd", "lad23cd", "lad22cd", "lad21cd", "laua", "oslaua"],
}
REQUIRED = ["pcds", "lsoa21cd", "msoa21cd"]


def compact(pc: str) -> str:
    return pc.replace(" ", "").upper()


def copy_rows(conn, table: str, columns: list[str], rows) -> int:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n")
    n = 0
    for r in rows:
        w.writerow(r)
        n += 1
    buf.seek(0)
    with conn.cursor() as cur:
        cur.copy_expert(f"COPY {SCHEMA}.{table} ({', '.join(columns)}) FROM STDIN WITH (FORMAT csv)", buf)
    return n


def main():
    ap = argparse.ArgumentParser(description="Load Land Registry Price Paid + ONS postcode lookup (raw).")
    ap.add_argument("--folder", required=True)
    ap.add_argument("--host", default=os.getenv("PGHOST", "localhost"))
    ap.add_argument("--port", type=int, default=int(os.getenv("PGPORT", "5432")))
    ap.add_argument("--user", default=os.getenv("PGUSER", "postgres"))
    ap.add_argument("--password", default=os.getenv("PGPASSWORD"))
    args = ap.parse_args()
    if args.password is None:
        args.password = getpass.getpass(f"PostgreSQL password for user '{args.user}': ")

    folder = Path(args.folder).expanduser()
    ppd_files = sorted(folder.glob("pp-*.csv"))
    lookup_files = [p for p in sorted(folder.glob("*.csv"))
                    if ("postcode" in p.name.lower() or "lookup" in p.name.lower()) and not p.name.startswith("pp-")]
    if not ppd_files:
        sys.exit(f"No pp-YYYY.csv files in {folder}")
    if len(lookup_files) != 1:
        sys.exit(f"Expected exactly one postcode lookup CSV in {folder}, found: {[p.name for p in lookup_files]}")
    lookup = lookup_files[0]

    conn = psycopg2.connect(host=args.host, port=args.port, user=args.user,
                            password=args.password, dbname=DB_NAME)
    with conn.cursor() as cur:
        cur.execute(f"CREATE SCHEMA IF NOT EXISTS {SCHEMA}")
        # create once, then empty and refill: views built on these tables stay intact
        cur.execute(f"""CREATE TABLE IF NOT EXISTS {SCHEMA}.land_registry_ppd (
                          {', '.join(c + ' TEXT' for c in PPD_COLUMNS)},
                          source_file TEXT NOT NULL, source_row INTEGER NOT NULL,
                          loaded_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
        cur.execute(f"""CREATE TABLE IF NOT EXISTS {SCHEMA}.ons_postcode_lsoa (
                          {', '.join(c + ' TEXT' for c in LOOKUP_FIELDS)},
                          source_file TEXT NOT NULL, source_row INTEGER NOT NULL,
                          loaded_at TIMESTAMPTZ NOT NULL DEFAULT now())""")
        cur.execute(f"TRUNCATE {SCHEMA}.land_registry_ppd, {SCHEMA}.ons_postcode_lsoa")

    # 1. Price Paid: keep South Yorkshire districts
    sale_postcodes: set[str] = set()
    total = 0
    for f in ppd_files:
        kept = []
        with f.open(encoding="utf-8", newline="") as fh:
            for i, row in enumerate(csv.reader(fh), start=1):
                if len(row) != 16:
                    conn.rollback()
                    sys.exit(f"{f.name} row {i}: {len(row)} fields, expected 16 - is this a Price Paid yearly file?")
                if row[12].strip().upper() in SY_DISTRICTS:
                    kept.append(row + [f.name, i])
                    if row[3].strip():
                        sale_postcodes.add(compact(row[3]))
        n = copy_rows(conn, "land_registry_ppd", PPD_COLUMNS + ["source_file", "source_row"], kept)
        total += n
        print(f"  {f.name}: {n:,} South Yorkshire sales kept")
    conn.commit()

    # 2. Postcode lookup: header detected by name
    with lookup.open(encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        header = [h.strip().lower() for h in next(reader)]
        idx = {}
        for field, aliases in LOOKUP_FIELDS.items():
            idx[field] = next((header.index(a) for a in aliases if a in header), None)
        missing = [f for f in REQUIRED if idx[f] is None]
        if missing:
            sys.exit(f"{lookup.name}: required columns not found {missing}. Header is: {header[:25]}")
        print(f"  {lookup.name}: using columns " +
              ", ".join(f"{k}={header[v]}" for k, v in idx.items() if v is not None))
        kept, scanned = [], 0
        for i, row in enumerate(reader, start=2):
            scanned += 1
            pc = compact(row[idx["pcds"]]) if idx["pcds"] < len(row) else ""
            lad = row[idx["ladcd"]].strip() if idx["ladcd"] is not None and idx["ladcd"] < len(row) else ""
            if pc in sale_postcodes or lad in SY_LAD_CODES:
                kept.append([row[v].strip() if v is not None and v < len(row) else ""
                             for v in idx.values()] + [lookup.name, i])
        n = copy_rows(conn, "ons_postcode_lsoa", list(LOOKUP_FIELDS) + ["source_file", "source_row"], kept)
        print(f"  {lookup.name}: scanned {scanned:,} postcodes, kept {n:,}")

    with conn.cursor() as cur:
        cur.execute(f"CREATE INDEX IF NOT EXISTS ix_ons_postcode_lsoa_pcds ON {SCHEMA}.ons_postcode_lsoa (pcds)")
        cur.execute(f"CREATE INDEX IF NOT EXISTS ix_land_registry_ppd_postcode ON {SCHEMA}.land_registry_ppd (postcode)")
    conn.commit()
    conn.close()
    print(f"Done. {total:,} sales; {len(sale_postcodes):,} distinct sale postcodes.")


if __name__ == "__main__":
    main()
