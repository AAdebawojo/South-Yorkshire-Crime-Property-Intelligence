#!/usr/bin/env python3
"""
load_bulk_csv.py
----------------
Loads the data.police.uk bulk "street" CSV files (one per month) into
PostgreSQL as an untouched raw table:

    CrimeData.police_bulk.street_crimes_raw

Every CSV column is stored exactly as text, plus the file name and row
number so each row can be traced back to its source. Nothing is cleaned
here; cleansing happens later in the analytics schema.

Re-running is safe: each file's rows are deleted and reloaded, so a file
is never loaded twice.

Usage
  python load_bulk_csv.py --folder "C:\\path\\to\\csv folder"
  python load_bulk_csv.py --folder . --pattern "*street*.csv"

Requirements: psycopg2-binary (already installed for load_crime_data.py)
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
SCHEMA = "police_bulk"
TABLE = "street_crimes_raw"

EXPECTED_HEADER = [
    "Crime ID", "Month", "Reported by", "Falls within", "Longitude", "Latitude",
    "Location", "LSOA code", "LSOA name", "Crime type", "Last outcome category", "Context",
]

DDL = f"""
CREATE SCHEMA IF NOT EXISTS {SCHEMA};

CREATE TABLE IF NOT EXISTS {SCHEMA}.{TABLE} (
    source_file             TEXT    NOT NULL,
    source_row              INTEGER NOT NULL,   -- data row number in the file (header = 0)
    crime_id                TEXT,
    month                   TEXT,
    reported_by             TEXT,
    falls_within            TEXT,
    longitude               TEXT,
    latitude                TEXT,
    location                TEXT,
    lsoa_code               TEXT,
    lsoa_name               TEXT,
    crime_type              TEXT,
    last_outcome_category   TEXT,
    context                 TEXT,
    loaded_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (source_file, source_row)
);

CREATE INDEX IF NOT EXISTS ix_street_raw_coords   ON {SCHEMA}.{TABLE} (latitude, longitude);
CREATE INDEX IF NOT EXISTS ix_street_raw_crime_id ON {SCHEMA}.{TABLE} (crime_id);
CREATE INDEX IF NOT EXISTS ix_street_raw_month    ON {SCHEMA}.{TABLE} (month);
"""

COPY_COLUMNS = ("source_file, source_row, crime_id, month, reported_by, falls_within, longitude, "
                "latitude, location, lsoa_code, lsoa_name, crime_type, last_outcome_category, context")


def parse_args():
    p = argparse.ArgumentParser(description="Load data.police.uk bulk street CSVs into PostgreSQL (raw).")
    p.add_argument("--folder", required=True, help="Folder containing the monthly CSV files.")
    p.add_argument("--pattern", default="*street*.csv", help='File name pattern (default "*street*.csv").')
    p.add_argument("--recursive", action="store_true",
                   help="Also search sub-folders (the data.police.uk download puts each month in its own folder).")
    p.add_argument("--host", default=os.getenv("PGHOST", "localhost"))
    p.add_argument("--port", type=int, default=int(os.getenv("PGPORT", "5432")))
    p.add_argument("--user", default=os.getenv("PGUSER", "postgres"))
    p.add_argument("--password", default=os.getenv("PGPASSWORD"))
    args = p.parse_args()
    if args.password is None:
        args.password = getpass.getpass(f"PostgreSQL password for user '{args.user}': ")
    return args


def file_to_copy_buffer(path: Path) -> tuple[io.StringIO, int]:
    """Read one CSV, check its header, and return a COPY-ready buffer plus row count."""
    with path.open(encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header is None:
            raise ValueError("file is empty")
        header = [h.strip() for h in header]
        if header != EXPECTED_HEADER:
            raise ValueError(f"unexpected header: {header}")
        buf = io.StringIO()
        writer = csv.writer(buf, lineterminator="\n")
        n = 0
        for i, row in enumerate(reader, start=1):
            if not any(cell.strip() for cell in row):
                continue                                   # skip fully blank lines
            if len(row) != len(EXPECTED_HEADER):
                raise ValueError(f"row {i} has {len(row)} fields, expected {len(EXPECTED_HEADER)}")
            writer.writerow([path.name, i] + row)
            n += 1
    buf.seek(0)
    return buf, n


def main():
    args = parse_args()
    folder = Path(args.folder).expanduser()
    files = sorted(folder.rglob(args.pattern) if args.recursive else folder.glob(args.pattern))
    names = [f.name for f in files]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        sys.exit(f"The same file name appears in more than one folder: {', '.join(sorted(dupes))}. "
                 f"Remove the copies, then run again.")
    if not files:
        hint = "" if args.recursive else " (add --recursive to search sub-folders)"
        sys.exit(f"No files matching '{args.pattern}' in {folder.resolve()}{hint}")
    print(f"Found {len(files)} files in {folder.resolve()}")

    try:
        conn = psycopg2.connect(host=args.host, port=args.port, user=args.user,
                                password=args.password, dbname=DB_NAME)
    except psycopg2.OperationalError as e:
        sys.exit(f"Could not connect to {DB_NAME}: {e}")

    with conn.cursor() as cur:
        cur.execute(DDL)
    conn.commit()

    total, failed = 0, []
    for path in files:
        try:
            buf, n = file_to_copy_buffer(path)
            with conn.cursor() as cur:
                cur.execute(f"DELETE FROM {SCHEMA}.{TABLE} WHERE source_file = %s", (path.name,))
                cur.copy_expert(f"COPY {SCHEMA}.{TABLE} ({COPY_COLUMNS}) FROM STDIN WITH (FORMAT csv)", buf)
            conn.commit()
            total += n
            print(f"  {path.name}: {n:,} rows")
        except Exception as e:  # noqa: BLE001
            conn.rollback()
            failed.append(path.name)
            print(f"  {path.name}: FAILED - {e}")

    with conn.cursor() as cur:
        cur.execute(f"ANALYZE {SCHEMA}.{TABLE}")
        cur.execute(f"SELECT COUNT(*), COUNT(DISTINCT source_file), MIN(month), MAX(month) FROM {SCHEMA}.{TABLE}")
        rows, nfiles, first, last = cur.fetchone()
    conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    print(f"Loaded this run: {total:,} rows from {len(files) - len(failed)} files")
    print(f"Table {SCHEMA}.{TABLE}: {rows:,} rows, {nfiles} files, months {first} to {last}")
    if failed:
        print(f"Failed files ({len(failed)}): {', '.join(failed)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
