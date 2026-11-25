#!/usr/bin/env python3
"""
load_crime_data.py
------------------
Pulls South Yorkshire crime data from the data.police.uk API and loads it
into a PostgreSQL database called "CrimeData" (schema: police).

What it loads
  * Reference lists : forces, available months, crime categories, outcome categories
  * Neighbourhoods  : details + boundary polygons for every South Yorkshire neighbourhood
  * Crimes          : street-level crimes (all categories) for every available month,
                      plus crimes recorded with no location
  * Outcomes        : full outcome history from /outcomes-at-location

How it works
  The API refuses any custom area holding more than 10,000 crimes in a month, so the
  force is fetched one neighbourhood polygon at a time. Each crime's map point is then
  matched to the neighbourhood that contains it. Points outside South Yorkshire
  (picked up by the small buffer around each polygon) are discarded.

  Every finished (neighbourhood, month) piece is recorded in police.load_log, so if the
  script is stopped (Ctrl+C, network drop) just run it again: it only fetches what is
  missing or failed.

Usage examples
  python load_crime_data.py --schema-only          # create database + tables only
  python load_crime_data.py --test                 # latest month, 3 neighbourhoods
  python load_crime_data.py                        # everything the API has
  python load_crime_data.py --start 2025-01 --end 2025-06
  python load_crime_data.py --refresh              # re-fetch months already loaded

Requirements: pip install -r requirements.txt   (requests, psycopg2-binary, shapely)
"""

from __future__ import annotations

import argparse
import getpass
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from urllib.parse import quote

import psycopg2
import psycopg2.extras
import requests
from psycopg2 import sql
from shapely import STRtree
from shapely.geometry import MultiPolygon, Point, Polygon, box

# ----------------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------------
API_BASE = "https://data.police.uk/api"
FORCE_ID = "south-yorkshire"
DB_NAME = "CrimeData"
SCHEMA = "police"
SCHEMA_FILE = Path(__file__).with_name("schema.sql")

REQUESTS_PER_SECOND = 10        # API limit is 15/s average; stay under it
MAX_RETRIES = 6
HTTP_TIMEOUT = 120              # seconds; big polygon queries can be slow
QUERY_BUFFER_DEG = 0.0005       # ~35-55 m buffer around each neighbourhood for the API query
BORDER_TOLERANCE_DEG = 0.0002   # ~15-20 m: points this close to a SY boundary still count as SY
MAX_POLY_CHARS = 3000           # keeps GET URLs well under the API's 4,094 char limit
MAX_SPLIT_DEPTH = 4             # how many times a polygon may be quartered on a 10k-limit 503

USER_AGENT = "CrimeData-loader/1.0 (personal analysis project)"


# ----------------------------------------------------------------------------
# HTTP client (thread-safe, rate limited, retrying)
# ----------------------------------------------------------------------------
class TooManyResults(Exception):
    """API returned 503 for a custom area: more than 10,000 records."""


class ApiError(Exception):
    pass


class RateLimiter:
    def __init__(self, per_second: float):
        self.interval = 1.0 / per_second
        self.lock = threading.Lock()
        self.next_slot = time.monotonic()

    def wait(self):
        with self.lock:
            now = time.monotonic()
            slot = max(self.next_slot, now)
            self.next_slot = slot + self.interval
        delay = slot - now
        if delay > 0:
            time.sleep(delay)


_limiter = RateLimiter(REQUESTS_PER_SECOND)
_local = threading.local()


def _session() -> requests.Session:
    s = getattr(_local, "session", None)
    if s is None:
        s = requests.Session()
        s.headers["User-Agent"] = USER_AGENT
        _local.session = s
    return s


def api_get(path: str, params: dict | None = None, raw_query: str | None = None,
            is_poly: bool = False, allow_404: bool = False):
    """GET {API_BASE}/{path}. Returns parsed JSON (or None on allowed 404)."""
    url = f"{API_BASE}/{path}"
    if raw_query:
        url = f"{url}?{raw_query}"
    last_err = None
    poly_503s = 0
    for attempt in range(MAX_RETRIES):
        _limiter.wait()
        try:
            r = _session().get(url, params=params, timeout=HTTP_TIMEOUT)
        except requests.RequestException as e:
            last_err = e
            time.sleep(min(60, 2 ** attempt))
            continue

        if r.status_code == 200:
            text = r.text.strip()
            return r.json() if text else []
        if r.status_code == 404 and allow_404:
            return None
        if r.status_code == 503 and is_poly:
            poly_503s += 1
            if poly_503s >= 2:          # one retry, then assume it's the 10k cap
                raise TooManyResults(url)
            time.sleep(3)
            continue
        if r.status_code in (429, 500, 502, 503, 504):
            last_err = ApiError(f"HTTP {r.status_code} for {url[:200]}")
            time.sleep(min(60, 2 ** attempt))
            continue
        raise ApiError(f"HTTP {r.status_code} for {url[:200]}: {r.text[:200]}")
    raise ApiError(f"Gave up after {MAX_RETRIES} attempts: {last_err}")


# ----------------------------------------------------------------------------
# Geometry helpers
# ----------------------------------------------------------------------------
def to_month_date(s: str | None) -> date | None:
    """'2024-01' or '2024-01-01' -> date(2024, 1, 1)."""
    if not s:
        return None
    parts = s.split("-")
    return date(int(parts[0]), int(parts[1]), 1)


def month_str(d: date) -> str:
    return f"{d.year:04d}-{d.month:02d}"


def polygon_parts(geom) -> list[Polygon]:
    if geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    # GeometryCollection etc.
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon) and not g.is_empty]


def poly_to_param(p: Polygon) -> str:
    """Shapely polygon (x=lng, y=lat) -> 'lat,lng:lat,lng:...' (closing point dropped)."""
    coords = list(p.exterior.coords)[:-1]
    return ":".join(f"{y:.5f},{x:.5f}" for x, y in coords)


def query_polygons(exact: Polygon | MultiPolygon) -> list[Polygon]:
    """Buffered + simplified polygons small enough to send in a GET URL."""
    buffered = exact.buffer(QUERY_BUFFER_DEG)
    out = []
    for part in polygon_parts(buffered):
        tol = 0.00005
        simp = Polygon(part.exterior)
        while len(poly_to_param(simp)) > MAX_POLY_CHARS:
            # simplify then re-buffer by the tolerance so nothing inside is cut off
            simp = Polygon(part.exterior).simplify(tol, preserve_topology=True).buffer(tol)
            simp = Polygon(max(polygon_parts(simp), key=lambda g: g.area).exterior)
            tol *= 1.6
        out.append(simp)
    return out


def split_in_four(p: Polygon) -> list[Polygon]:
    minx, miny, maxx, maxy = p.bounds
    mx, my = (minx + maxx) / 2, (miny + maxy) / 2
    pieces = []
    for b in (box(minx, miny, mx, my), box(mx, miny, maxx, my),
              box(minx, my, mx, maxy), box(mx, my, maxx, maxy)):
        for part in polygon_parts(p.intersection(b)):
            if part.area > 0:
                pieces.append(Polygon(part.exterior))
    return pieces


def fetch_poly(path: str, poly: Polygon, month: str, depth: int = 0) -> list:
    """Fetch a poly endpoint, quartering the polygon if the 10k cap is hit."""
    query = f"date={month}&poly={poly_to_param(poly)}"
    try:
        return api_get(path, raw_query=query, is_poly=True)
    except TooManyResults:
        if depth >= MAX_SPLIT_DEPTH:
            raise ApiError(f"{path} {month}: still over 10,000 records after {depth} splits "
                           f"(or the API is returning 503 errors)")
        results = []
        for piece in split_in_four(poly):
            results.extend(fetch_poly(path, piece, month, depth + 1))
        return results


class Locator:
    """Finds which South Yorkshire neighbourhood contains a lat/lng point."""

    def __init__(self, polys: dict[str, Polygon]):
        self.ids = list(polys)
        self.tree = STRtree([polys[i] for i in self.ids])
        self.cache: dict[tuple, str | None] = {}

    def locate(self, lat: float, lng: float) -> str | None:
        key = (lat, lng)
        if key in self.cache:
            return self.cache[key]
        p = Point(lng, lat)
        hits = self.tree.query(p, predicate="intersects")
        if len(hits) == 0:
            hits = self.tree.query_nearest(p, max_distance=BORDER_TOLERANCE_DEG)
        result = self.ids[int(min(hits))] if len(hits) else None
        self.cache[key] = result
        return result


# ----------------------------------------------------------------------------
# Data classes passed from worker threads to the DB writer
# ----------------------------------------------------------------------------
@dataclass
class Neighbourhood:
    nid: str
    name: str
    exact: Polygon | None = None
    query_polys: list[Polygon] = field(default_factory=list)


@dataclass
class TaskResult:
    load_type: str
    neighbourhood_id: str
    month: date
    crimes: list = field(default_factory=list)       # raw API crime dicts
    outcomes: list = field(default_factory=list)     # raw API outcome dicts
    locations: dict = field(default_factory=dict)    # location_id -> (street, lat, lng, nbhd)
    dropped: int = 0
    error: str | None = None


def _location_tuple(loc: dict, locator: Locator):
    lat = float(loc["latitude"])
    lng = float(loc["longitude"])
    nbhd = locator.locate(lat, lng)
    street = loc.get("street") or {}
    return street.get("id"), street.get("name"), lat, lng, nbhd


def fetch_street_task(n: Neighbourhood, month: date, locator: Locator, want_outcomes: bool) -> TaskResult:
    m = month_str(month)
    res = TaskResult("street", n.nid, month)
    try:
        crimes: dict[int, dict] = {}
        for qp in n.query_polys:
            for c in fetch_poly("crimes-street/all-crime", qp, m):
                crimes[c["id"]] = c
        for c in crimes.values():
            loc = c.get("location")
            if not loc:
                continue
            lid, street, lat, lng, nbhd = _location_tuple(loc, locator)
            if nbhd is None or lid is None:      # outside South Yorkshire
                res.dropped += 1
                continue
            res.locations[lid] = (street, lat, lng, nbhd)
            res.crimes.append(c)

        if want_outcomes:
            seen = set()
            for qp in n.query_polys:
                for o in fetch_poly("outcomes-at-location", qp, m):
                    crime = o.get("crime") or {}
                    key = (crime.get("persistent_id"), (o.get("category") or {}).get("code"),
                           o.get("date"), o.get("person_id"))
                    if key in seen or not crime.get("persistent_id"):
                        continue
                    seen.add(key)
                    loc = crime.get("location")
                    if loc:
                        lid, street, lat, lng, nbhd = _location_tuple(loc, locator)
                        if nbhd is None or lid is None:
                            continue
                        res.locations[lid] = (street, lat, lng, nbhd)
                    res.outcomes.append(o)
    except Exception as e:  # noqa: BLE001 - record any failure and carry on
        res.error = f"{type(e).__name__}: {e}"
    return res


def fetch_no_location_task(month: date) -> TaskResult:
    res = TaskResult("no_location", "_force", month)
    try:
        data = api_get("crimes-no-location",
                       params={"category": "all-crime", "force": FORCE_ID, "date": month_str(month)})
        res.crimes = data or []
    except Exception as e:  # noqa: BLE001
        res.error = f"{type(e).__name__}: {e}"
    return res


# ----------------------------------------------------------------------------
# Database
# ----------------------------------------------------------------------------
def connect(args, dbname: str):
    return psycopg2.connect(host=args.host, port=args.port, user=args.user,
                            password=args.password, dbname=dbname)


def ensure_database(args):
    conn = connect(args, args.maintenance_db)
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,))
        if cur.fetchone():
            print(f"Database \"{DB_NAME}\" already exists.")
        else:
            cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(DB_NAME)))
            print(f"Created database \"{DB_NAME}\".")
    conn.close()


def ensure_schema(conn):
    with conn.cursor() as cur:
        cur.execute(SCHEMA_FILE.read_text(encoding="utf-8"))
    conn.commit()
    print(f"Schema \"{SCHEMA}\" and tables are in place.")


def upsert_many(cur, statement: str, rows: list, page_size: int = 1000):
    if rows:
        psycopg2.extras.execute_values(cur, statement, rows, page_size=page_size)


def write_result(conn, res: TaskResult):
    with conn.cursor() as cur:
        if res.error:
            cur.execute(f"""
                INSERT INTO {SCHEMA}.load_log (load_type, neighbourhood_id, month, status, error, loaded_at)
                VALUES (%s, %s, %s, 'failed', %s, now())
                ON CONFLICT (load_type, neighbourhood_id, month)
                DO UPDATE SET status='failed', error=EXCLUDED.error, loaded_at=now()""",
                        (res.load_type, res.neighbourhood_id, res.month, res.error[:2000]))
            conn.commit()
            return

        # categories we have not seen before (keeps the foreign key happy)
        cats = {c["category"] for c in res.crimes}
        cats |= {(o.get("crime") or {}).get("category") for o in res.outcomes}
        cats.discard(None)
        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.crime_categories (category_code, category_name) VALUES %s
            ON CONFLICT (category_code) DO NOTHING""",
                    [(c, c.replace("-", " ").capitalize()) for c in cats])

        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.locations (location_id, street_name, latitude, longitude, neighbourhood_id)
            VALUES %s
            ON CONFLICT (location_id) DO UPDATE SET neighbourhood_id = EXCLUDED.neighbourhood_id""",
                    [(lid, s, lat, lng, nb) for lid, (s, lat, lng, nb) in res.locations.items()])

        crime_rows = []
        for c in res.crimes:
            loc = c.get("location")
            lid = ((loc or {}).get("street") or {}).get("id") if loc else None
            os_ = c.get("outcome_status") or {}
            crime_rows.append((
                c["id"], c.get("persistent_id") or "", c["category"], to_month_date(c["month"]),
                lid, c.get("location_type"), c.get("location_subtype") or None, c.get("context") or None,
                os_.get("category"), to_month_date(os_.get("date")), FORCE_ID,
            ))
        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.crimes (crime_id, persistent_id, category_code, crime_month, location_id,
                location_type, location_subtype, context, latest_outcome, latest_outcome_month, force_id)
            VALUES %s
            ON CONFLICT (crime_id) DO UPDATE SET
                latest_outcome       = EXCLUDED.latest_outcome,
                latest_outcome_month = EXCLUDED.latest_outcome_month,
                location_id          = COALESCE(EXCLUDED.location_id, {SCHEMA}.crimes.location_id),
                loaded_at            = now()""", crime_rows)

        out_cats = {}
        out_rows = []
        for o in res.outcomes:
            cat = o.get("category") or {}
            crime = o.get("crime") or {}
            if not cat.get("code"):
                continue
            out_cats[cat["code"]] = cat.get("name") or cat["code"]
            loc = crime.get("location")
            lid = ((loc or {}).get("street") or {}).get("id") if loc else None
            out_rows.append((
                crime["persistent_id"], crime.get("id"), cat["code"], to_month_date(o.get("date")),
                o.get("person_id"), crime.get("category"), to_month_date(crime.get("month")), lid,
            ))
        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.outcome_categories (outcome_code, outcome_name) VALUES %s
            ON CONFLICT (outcome_code) DO UPDATE SET outcome_name = EXCLUDED.outcome_name""",
                    list(out_cats.items()))
        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.outcomes (persistent_id, crime_id, outcome_code, outcome_month, person_id,
                crime_category_code, crime_month, location_id)
            VALUES %s ON CONFLICT DO NOTHING""", out_rows)

        cur.execute(f"""
            INSERT INTO {SCHEMA}.load_log (load_type, neighbourhood_id, month, status, crime_rows, outcome_rows,
                                           error, loaded_at)
            VALUES (%s, %s, %s, 'done', %s, %s, NULL, now())
            ON CONFLICT (load_type, neighbourhood_id, month) DO UPDATE SET
                status='done', crime_rows=EXCLUDED.crime_rows, outcome_rows=EXCLUDED.outcome_rows,
                error=NULL, loaded_at=now()""",
                    (res.load_type, res.neighbourhood_id, res.month, len(crime_rows), len(out_rows)))
    conn.commit()


# ----------------------------------------------------------------------------
# Reference data
# ----------------------------------------------------------------------------
def load_reference(conn, workers: int) -> tuple[list[date], list[Neighbourhood], date | None]:
    cur = conn.cursor()

    print("Loading forces ...")
    forces = api_get("forces") or []
    upsert_many(cur, f"""
        INSERT INTO {SCHEMA}.forces (force_id, force_name) VALUES %s
        ON CONFLICT (force_id) DO UPDATE SET force_name = EXCLUDED.force_name""",
                [(f["id"], f["name"]) for f in forces])
    sy = api_get(f"forces/{FORCE_ID}") or {}
    cur.execute(f"""
        INSERT INTO {SCHEMA}.forces (force_id, force_name, url, telephone, description)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (force_id) DO UPDATE SET force_name=EXCLUDED.force_name, url=EXCLUDED.url,
            telephone=EXCLUDED.telephone, description=EXCLUDED.description""",
                (FORCE_ID, sy.get("name") or "South Yorkshire Police", sy.get("url"),
                 sy.get("telephone"), sy.get("description")))

    print("Loading available months ...")
    dates = api_get("crimes-street-dates") or []
    months = sorted({to_month_date(d["date"]) for d in dates if d.get("date")}, reverse=True)
    upsert_many(cur, f"INSERT INTO {SCHEMA}.available_months (month) VALUES %s ON CONFLICT DO NOTHING",
                [(m,) for m in months])

    last = api_get("crime-last-updated") or {}
    last_updated = None
    if isinstance(last, dict) and last.get("date"):
        last_updated = datetime.strptime(last["date"][:10], "%Y-%m-%d").date()

    print(f"Loading crime categories for {len(months)} months ...")
    cats = {}
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for result in ex.map(lambda m: api_get("crime-categories", params={"date": month_str(m)}) or [], months):
            for c in result:
                cats[c["url"]] = c["name"]
    upsert_many(cur, f"""
        INSERT INTO {SCHEMA}.crime_categories (category_code, category_name) VALUES %s
        ON CONFLICT (category_code) DO UPDATE SET category_name = EXCLUDED.category_name""",
                list(cats.items()))
    conn.commit()

    print("Loading neighbourhoods and boundaries ...")
    nlist = api_get(f"{FORCE_ID}/neighbourhoods") or []

    def fetch_nbhd(item):
        nid = item["id"]
        enc = quote(nid, safe="")
        detail = api_get(f"{FORCE_ID}/{enc}", allow_404=True) or {}
        boundary = api_get(f"{FORCE_ID}/{enc}/boundary", allow_404=True) or []
        return item, detail, boundary

    neighbourhoods: list[Neighbourhood] = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        fetched = list(ex.map(fetch_nbhd, nlist))

    for item, d, boundary in fetched:
        nid = item["id"]
        name = d.get("name") or item.get("name") or nid
        contact = d.get("contact_details") or {}
        centre = d.get("centre") or {}
        pts = [(float(p["longitude"]), float(p["latitude"])) for p in boundary
               if p.get("latitude") and p.get("longitude")]
        exact = None
        if len(pts) >= 3:
            exact = Polygon(pts).buffer(0)          # repair any self-intersections
            if exact.is_empty:
                exact = None
        try:
            population = int(float(d.get("population"))) if d.get("population") not in (None, "") else None
        except ValueError:
            population = None
        cur.execute(f"""
            INSERT INTO {SCHEMA}.neighbourhoods (neighbourhood_id, force_id, neighbourhood_name, description,
                population, url_force, centre_latitude, centre_longitude, email, telephone, website,
                boundary_wkt, loaded_at)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, now())
            ON CONFLICT (neighbourhood_id) DO UPDATE SET
                neighbourhood_name=EXCLUDED.neighbourhood_name, description=EXCLUDED.description,
                population=EXCLUDED.population, url_force=EXCLUDED.url_force,
                centre_latitude=EXCLUDED.centre_latitude, centre_longitude=EXCLUDED.centre_longitude,
                email=EXCLUDED.email, telephone=EXCLUDED.telephone, website=EXCLUDED.website,
                boundary_wkt=EXCLUDED.boundary_wkt, loaded_at=now()""",
                    (nid, FORCE_ID, name, d.get("description"), population, d.get("url_force"),
                     centre.get("latitude"), centre.get("longitude"), contact.get("email"),
                     contact.get("telephone"), contact.get("web"), exact.wkt if exact else None))
        cur.execute(f"DELETE FROM {SCHEMA}.neighbourhood_boundary_points WHERE neighbourhood_id = %s", (nid,))
        upsert_many(cur, f"""
            INSERT INTO {SCHEMA}.neighbourhood_boundary_points (neighbourhood_id, point_order, latitude, longitude)
            VALUES %s""", [(nid, i, lat, lng) for i, (lng, lat) in enumerate(pts)])

        n = Neighbourhood(nid, name, exact)
        if exact is not None:
            n.query_polys = query_polygons(exact)
        else:
            print(f"  WARNING: neighbourhood {nid} ({name}) has no usable boundary - skipped for crime loads")
        neighbourhoods.append(n)
    conn.commit()
    cur.close()
    print(f"  {len(neighbourhoods)} neighbourhoods loaded.")
    return months, neighbourhoods, last_updated


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(description="Load data.police.uk crime data for South Yorkshire into PostgreSQL.")
    p.add_argument("--host", default=os.getenv("PGHOST", "localhost"))
    p.add_argument("--port", type=int, default=int(os.getenv("PGPORT", "5432")))
    p.add_argument("--user", default=os.getenv("PGUSER", "postgres"))
    p.add_argument("--password", default=os.getenv("PGPASSWORD"),
                   help="Defaults to the PGPASSWORD environment variable; you are prompted if neither is set.")
    p.add_argument("--maintenance-db", default="postgres",
                   help="Existing database used to create CrimeData (default: postgres).")
    p.add_argument("--start", help="First month to load, YYYY-MM (default: earliest the API has).")
    p.add_argument("--end", help="Last month to load, YYYY-MM (default: latest the API has).")
    p.add_argument("--test", action="store_true", help="Quick trial: latest month, first 3 neighbourhoods.")
    p.add_argument("--refresh", action="store_true", help="Re-fetch pieces already marked done.")
    p.add_argument("--skip-outcomes", action="store_true", help="Do not load the outcomes table (halves run time).")
    p.add_argument("--workers", type=int, default=4, help="Parallel API requests (default 4).")
    p.add_argument("--schema-only", action="store_true", help="Create the database and tables, then stop.")
    args = p.parse_args()
    if args.password is None:
        args.password = getpass.getpass(f"PostgreSQL password for user '{args.user}': ")
    return args


def main():
    args = parse_args()
    started = time.time()

    try:
        ensure_database(args)
        conn = connect(args, DB_NAME)
    except psycopg2.OperationalError as e:
        sys.exit(f"Could not connect to PostgreSQL at {args.host}:{args.port} as {args.user}.\n{e}")
    ensure_schema(conn)
    if args.schema_only:
        print("Done (schema only).")
        return

    with conn.cursor() as cur:
        cur.execute(f"INSERT INTO {SCHEMA}.load_runs (started_at) VALUES (now()) RETURNING run_id")
        run_id = cur.fetchone()[0]
    conn.commit()

    months, neighbourhoods, last_updated = load_reference(conn, args.workers)
    if args.start:
        months = [m for m in months if m >= to_month_date(args.start)]
    if args.end:
        months = [m for m in months if m <= to_month_date(args.end)]
    usable = [n for n in neighbourhoods if n.exact is not None]
    if args.test:
        months = months[:1]
        usable = usable[:3]
    if not months:
        sys.exit("No months to load - check --start/--end.")
    print(f"Months to load: {month_str(months[-1])} .. {month_str(months[0])} ({len(months)} months)")

    locator = Locator({n.nid: n.exact for n in neighbourhoods if n.exact is not None})

    with conn.cursor() as cur:
        cur.execute(f"SELECT load_type, neighbourhood_id, month FROM {SCHEMA}.load_log WHERE status = 'done'")
        done = set(cur.fetchall()) if not args.refresh else set()

    tasks = []
    for m in months:
        for n in usable:
            if ("street", n.nid, m) not in done:
                tasks.append(("street", n, m))
        if not args.test and ("no_location", "_force", m) not in done:
            tasks.append(("no_location", None, m))
    skipped = len(months) * len(usable) - sum(1 for t in tasks if t[0] == "street")
    print(f"{len(tasks)} pieces to fetch ({skipped} already loaded and skipped). "
          f"Using {args.workers} parallel workers.\n")

    ok = failed = total_crimes = total_outcomes = total_dropped = 0
    ex = ThreadPoolExecutor(max_workers=args.workers)
    try:
        futures = {}
        for kind, n, m in tasks:
            if kind == "street":
                f = ex.submit(fetch_street_task, n, m, locator, not args.skip_outcomes)
            else:
                f = ex.submit(fetch_no_location_task, m)
            futures[f] = (kind, n, m)

        for i, f in enumerate(as_completed(futures), 1):
            kind, n, m = futures[f]
            res = f.result()
            write_result(conn, res)
            label = n.name if n else "(crimes with no location)"
            if res.error:
                failed += 1
                print(f"[{i}/{len(tasks)}] {month_str(m)} {label}: FAILED - {res.error[:150]}")
            else:
                ok += 1
                total_crimes += len(res.crimes)
                total_outcomes += len(res.outcomes)
                total_dropped += res.dropped
                print(f"[{i}/{len(tasks)}] {month_str(m)} {label}: "
                      f"{len(res.crimes)} crimes, {len(res.outcomes)} outcomes")
    except KeyboardInterrupt:
        print("\nStopped by user. Finished pieces are saved - run the script again to continue.")
        ex.shutdown(wait=False, cancel_futures=True)
        conn.close()
        sys.exit(1)
    ex.shutdown()

    with conn.cursor() as cur:
        cur.execute(f"""UPDATE {SCHEMA}.load_runs SET finished_at=now(), api_last_updated=%s,
                        months_requested=%s, tasks_done=%s, tasks_failed=%s WHERE run_id=%s""",
                    (last_updated, f"{month_str(months[-1])}..{month_str(months[0])}", ok, failed, run_id))
        cur.execute(f"SELECT count(*) FROM {SCHEMA}.crimes")
        crimes_in_db = cur.fetchone()[0]
        cur.execute(f"SELECT count(*) FROM {SCHEMA}.outcomes")
        outcomes_in_db = cur.fetchone()[0]
    conn.commit()
    conn.close()

    mins = (time.time() - started) / 60
    print("\n" + "=" * 60)
    print(f"Finished in {mins:.1f} min.  Pieces OK: {ok}   Failed: {failed}")
    print(f"This run: {total_crimes:,} crime rows, {total_outcomes:,} outcome rows "
          f"({total_dropped:,} points outside South Yorkshire discarded)")
    print(f"Database totals: {crimes_in_db:,} crimes, {outcomes_in_db:,} outcomes")
    if failed:
        print("Some pieces failed - run the script again; it will only retry what is missing.")
    print("=" * 60)


if __name__ == "__main__":
    main()
