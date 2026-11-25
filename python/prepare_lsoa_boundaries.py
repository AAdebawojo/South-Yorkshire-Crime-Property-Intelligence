#!/usr/bin/env python3
"""
prepare_lsoa_boundaries.py
--------------------------
Cuts the ONS "Lower layer Super Output Areas (December 2021) Boundaries EW
BGC (V5)" GeoJSON down to the 860 South Yorkshire LSOAs used in the model,
for the Azure Maps reference layer (and a TopoJSON for the Shape Map fallback).

Steps
  1. Read the England & Wales GeoJSON (WGS84 / EPSG:4326 as published).
  2. Keep features whose LSOA21NM starts with Barnsley / Doncaster /
     Rotherham / Sheffield (the four South Yorkshire local authorities).
  3. Validate: expect 860 features, unique LSOA21CD, valid geometry;
     optional cross-check against a CSV of the model's LSOA codes.
  4. Light coverage-preserving simplification (shared borders stay shared),
     coordinates rounded to 5 decimals (~1 m), properties reduced to
     LSOA21CD + LSOA21NM.
  5. Write sy_lsoa_boundaries.geojson (+ .topojson if the topojson package
     is installed) and print a validation report.

Usage
  python prepare_lsoa_boundaries.py --input "<EW BGC V5>.geojson"
         [--codes model_lsoa_codes.csv] [--tolerance 0.00005] [--outdir .]
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import shapely
from shapely.geometry import mapping, shape

LAS = ("Barnsley ", "Doncaster ", "Rotherham ", "Sheffield ")


def round_coords(obj, nd=5):
    if isinstance(obj, (list, tuple)):
        if obj and isinstance(obj[0], (int, float)):
            return [round(obj[0], nd), round(obj[1], nd)]
        return [round_coords(o, nd) for o in obj]
    return obj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--codes", help="CSV with a column of the model's LSOA codes (optional cross-check)")
    ap.add_argument("--tolerance", type=float, default=0.00005, help="coverage simplification tolerance in degrees (~4 m)")
    ap.add_argument("--outdir", default=".")
    a = ap.parse_args()

    src = json.loads(Path(a.input).read_text(encoding="utf-8"))
    feats = src["features"]
    # newer portal exports name the fields CODE / NAME instead of LSOA21CD / LSOA21NM
    for f in feats:
        pr = f["properties"]
        pr.setdefault("LSOA21CD", pr.get("CODE"))
        pr.setdefault("LSOA21NM", pr.get("NAME"))
    keep = [f for f in feats if str(f["properties"].get("LSOA21NM", "")).startswith(LAS)]
    codes = [f["properties"]["LSOA21CD"] for f in keep]
    geoms = [shape(f["geometry"]) for f in keep]

    print(f"Source features: {len(feats):,}  |  South Yorkshire kept: {len(keep)} (expect 860)")
    print(f"Unique codes: {len(set(codes))}  |  invalid geometries before: {sum(not g.is_valid for g in geoms)}")
    lon_lat = [c for g in geoms for c in g.envelope.exterior.coords]
    print(f"Bounding box lon {min(x for x, _ in lon_lat):.3f} to {max(x for x, _ in lon_lat):.3f}, "
          f"lat {min(y for _, y in lon_lat):.3f} to {max(y for _, y in lon_lat):.3f}  (expect WGS84 ~ -2.0..-0.9, 53.3..53.7)")

    if a.codes:
        with open(a.codes, newline="", encoding="utf-8-sig") as fh:
            model = {row[0].strip() for row in csv.reader(fh) if row and row[0].startswith("E01")}
        print(f"Model codes: {len(model)}  |  in boundary file: {len(model & set(codes))}  |  "
              f"missing from boundaries: {sorted(model - set(codes))[:10]}  |  extra: {sorted(set(codes) - model)[:10]}")

    simplified = shapely.coverage_simplify(geoms, a.tolerance) if a.tolerance > 0 else geoms
    simplified = [g if g.is_valid else shapely.make_valid(g) for g in simplified]
    print(f"Invalid geometries after simplification: {sum(not g.is_valid for g in simplified)}")
    v_before = sum(shapely.get_num_coordinates(g) for g in geoms)
    v_after = sum(shapely.get_num_coordinates(g) for g in simplified)
    print(f"Vertices: {v_before:,} -> {v_after:,}")

    out = {"type": "FeatureCollection", "features": []}
    for f, g in zip(keep, simplified):
        out["features"].append({
            "type": "Feature",
            "properties": {"LSOA21CD": f["properties"]["LSOA21CD"], "LSOA21NM": f["properties"]["LSOA21NM"]},
            "geometry": {"type": mapping(g)["type"], "coordinates": round_coords(mapping(g)["coordinates"])},
        })
    outdir = Path(a.outdir)
    gj = outdir / "sy_lsoa_boundaries.geojson"
    gj.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")
    print(f"Written {gj}  ({gj.stat().st_size / 1024:,.0f} KB)")

    try:
        import topojson as tp
        topo = tp.Topology(out, prequantize=False, topology=True, object_name="lsoa")
        tj = outdir / "sy_lsoa_boundaries.topojson"
        tj.write_text(topo.to_json(), encoding="utf-8")
        print(f"Written {tj}  ({tj.stat().st_size / 1024:,.0f} KB)  object name 'lsoa' (Shape Map fallback)")
    except ImportError:
        print("topojson package not installed: TopoJSON (Shape Map fallback) not written")


if __name__ == "__main__":
    main()
