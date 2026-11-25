#!/usr/bin/env python3
"""
derive_severity_weights.py
--------------------------
Derives one severity weight per police.uk crime category for South Yorkshire
from official sources, so the weighting is reproducible and auditable.

Method
  weight(category) = sum(ONS offence weight x SY offences) / sum(SY offences)
  over all Home Office offence codes in the category, for the financial
  quarters that overlap the crime window (Oct 2023 - Jun 2026).

Sources (all in --folder)
  ONS Crime Severity Score, year ending March 2025 (.xls)   sheet "List of weights"
      ONS weights = equivalent days of custody, from MoJ sentencing data.
  Home Office police recorded crime open data, PFA tables (.ods)
      South Yorkshire offences by offence code, offence subgroup and quarter.
  police-uk-category-mappings.csv
      Used only to cross-check the subgroup -> police.uk category assignment.

Output
  crime_severity_weights.csv  (category, weight, offences, share of offences,
                               share of severity)

Requirements: xlrd, lxml   (pip install xlrd lxml)
Usage: python derive_severity_weights.py --folder "C:\\...\\external_data"
"""

from __future__ import annotations

import argparse
import collections
import csv
import re
import sys
import zipfile
from pathlib import Path

import xlrd
from lxml import etree

FORCE = "South Yorkshire"
# Home Office offence subgroup -> police.uk category (published police.uk grouping)
SUBGROUP_TO_CATEGORY = {
    "Violence without injury": "Violence and sexual offences",
    "Violence with injury": "Violence and sexual offences",
    "Stalking and harassment": "Violence and sexual offences",
    "Other sexual offences": "Violence and sexual offences",
    "Rape offences": "Violence and sexual offences",
    "Homicide": "Violence and sexual offences",
    "Death or serious injury - unlawful driving": "Violence and sexual offences",
    "Robbery of personal property": "Robbery",
    "Robbery of business property": "Robbery",
    "Residential burglary": "Burglary",
    "Non-residential burglary": "Burglary",
    "Domestic burglary": "Burglary",
    "Non-domestic burglary": "Burglary",
    "Vehicle offences": "Vehicle crime",
    "Theft from the person": "Theft from the person",
    "Bicycle theft": "Bicycle theft",
    "Shoplifting": "Shoplifting",
    "Other theft offences": "Other theft",
    "Criminal damage": "Criminal damage and arson",
    "Arson": "Criminal damage and arson",
    "Possession of drugs": "Drugs",
    "Trafficking of drugs": "Drugs",
    "Possession of weapons offences": "Possession of weapons",
    "Public order offences": "Public order",
    "Miscellaneous crimes against society": "Other crime",
}


def in_window(fy: str, q: str) -> bool:
    y, q = int(fy[:4]), int(float(q))
    return (y == 2023 and q >= 3) or y in (2024, 2025) or (y == 2026 and q == 1)


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def read_ons_weights(path: Path):
    sh = xlrd.open_workbook(str(path), on_demand=True).sheet_by_name("List of weights")
    by_code, by_desc = {}, {}
    for i in range(sh.nrows):
        r = sh.row_values(i)
        if len(r) < 5 or not isinstance(r[4], float) or not str(r[2]).strip():
            continue
        for c in re.split(r"\s*,\s*", str(r[1]).strip()):
            c = c[:-2] if c.endswith(".0") else c
            if c:
                by_code.setdefault(c, r[4])
        by_desc.setdefault(norm(r[2]), r[4])
    return by_code, by_desc


def read_sy_counts(path: Path):
    """Stream the ODS content.xml (too large for spreadsheet libraries) and keep South Yorkshire rows."""
    T = "{urn:oasis:names:tc:opendocument:xmlns:table:1.0}"
    O = "{urn:oasis:names:tc:opendocument:xmlns:office:1.0}"
    counts, meta = collections.Counter(), {}
    with zipfile.ZipFile(path) as zf, zf.open("content.xml") as fh:
        for _, el in etree.iterparse(fh, events=("end",), tag=T + "table-row"):
            vals = []
            for c in el:
                rep = min(int(c.get(T + "number-columns-repeated", "1")), 20)
                v = c.get(O + "value")
                vals.extend([v if v is not None else "".join(c.itertext())] * rep)
            if len(vals) >= 8 and vals[2] == FORCE and re.match(r"\d{4}/\d{2}", vals[0] or ""):
                if in_window(vals[0], vals[1]):
                    code = vals[6].strip()
                    counts[code] += int(float(vals[7] or 0))
                    meta[code] = (vals[3], vals[5])
            el.clear()
            while el.getprevious() is not None:
                del el.getparent()[0]
    return counts, meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--folder", required=True)
    args = ap.parse_args()
    folder = Path(args.folder).expanduser()
    css = next(folder.glob("*Crime Severity Score*.xls*"), None)
    prc = next(folder.glob("prc-pfa-*.ods"), None)
    mapping = folder / "police-uk-category-mappings.csv"
    if not (css and prc and mapping.exists()):
        sys.exit("Need the ONS Crime Severity Score .xls, the prc-pfa-*.ods and police-uk-category-mappings.csv")

    by_code, by_desc = read_ons_weights(css)
    counts, meta = read_sy_counts(prc)
    with mapping.open(encoding="cp1252", newline="") as fh:
        police_uk = {norm(r["Offence"]): r["Police.uk Category"] for r in csv.DictReader(fh)}

    totals = collections.defaultdict(lambda: [0, 0.0])
    unweighted, unmapped, agree, disagree = 0, 0, 0, []
    for code, n in counts.items():
        if n == 0:
            continue
        desc, sub = meta[code]
        cat = SUBGROUP_TO_CATEGORY.get(sub)
        if cat is None:
            unmapped += n
            continue
        w = by_code.get(code) or by_desc.get(norm(desc))
        if w is None:
            unweighted += n
            continue
        totals[cat][0] += n
        totals[cat][1] += n * w
        pu = police_uk.get(norm(desc))
        if pu:
            if pu.lower() == cat.lower():
                agree += n
            else:
                disagree.append((n, code, desc, cat, pu))

    all_n = sum(v[0] for v in totals.values())
    all_s = sum(v[1] for v in totals.values())
    out = folder.parent / "crime_severity_weights.csv"
    with out.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["category", "ons_weight", "sy_offences", "pct_offences", "pct_severity"])
        for cat, (n, s) in sorted(totals.items(), key=lambda kv: -kv[1][1] / kv[1][0]):
            w.writerow([cat, round(s / n, 2), n, round(100 * n / all_n, 2), round(100 * s / all_s, 2)])
            print(f"{cat:32} weight {s / n:9.2f}  offences {n:7,}  "
                  f"{100 * n / all_n:5.1f}% of offences  {100 * s / all_s:5.1f}% of severity")
    print(f"\nOffences weighted: {all_n:,}; without weight: {unweighted:,}; without category: {unmapped:,}")
    print(f"Cross-check vs police.uk mapping (offences matched by description): agree {agree:,}, disagree {len(disagree)}")
    for d in sorted(disagree, reverse=True)[:10]:
        print("   disagree:", d)
    print(f"Written: {out}")


if __name__ == "__main__":
    main()
