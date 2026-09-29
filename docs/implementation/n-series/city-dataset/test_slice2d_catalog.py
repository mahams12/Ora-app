#!/usr/bin/env python3
"""Slice 2D unit validation — run: python3 test_slice2d_catalog.py"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

FINAL = Path(__file__).resolve().parent / "final"
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def normalize_city_slug(raw: str) -> str | None:
    if not isinstance(raw, str):
        return None
    s = raw.strip().lower()
    return s if s else None


def main() -> int:
    catalog = json.load(open(FINAL / "approved_city_catalog.json"))
    prov = json.load(open(FINAL / "approved_city_provenance.json"))
    report = json.load(open(FINAL / "validation_report.json"))

    cities = catalog["cities"]
    ids = [c["id"] for c in cities]
    failed = []

    def check(cond: bool, msg: str) -> None:
        if not cond:
            failed.append(msg)

    check(catalog["_meta"]["licensing"] == "BLOCKED_PENDING_LICENSING_REVIEW", "licensing meta")
    check(catalog["_meta"]["productionImportAllowed"] is False, "import blocked")
    check(len(ids) == len(set(ids)), "unique ids")
    check(len(cities) == report["counts"]["finalCatalogCities"], "count match report")

    for c in cities:
        check(c["countryCode"] == "PK", f"PK {c['id']}")
        check(bool(c["displayName"].strip()), f"display {c['id']}")
        check(normalize_city_slug(c["id"]) == c["id"], f"normalize {c['id']}")
        check(bool(SLUG_RE.match(c["id"])), f"slug {c['id']}")
        check("createdAt" in c and "updatedAt" in c, f"timestamps {c['id']}")
        check(c["active"] is True, f"active {c['id']}")

    for m in ("lahore", "karachi", "hyderabad", "quetta", "sukkur"):
        check(ids.count(m) == 1, f"metro {m}")

    check("sahiwal" in ids and any(i.startswith("sahiwal-") for i in ids), "sahiwal pair")
    check("khanpur" in ids and any(i.startswith("khanpur-") for i in ids), "khanpur pair")
    check("khangarh" in ids and any(i.startswith("khangarh-") for i in ids), "khangarh pair")
    check("karampur" in ids and any(i.startswith("karampur-") for i in ids), "karampur pair")
    check("hyderabad-bhakkar" in ids, "hyderabad-bhakkar")
    check(not any("university" in i for i in ids), "no university city")

    prov_ids = {c["id"] for c in prov["cities"]}
    check(set(ids) == prov_ids, "catalog/provenance id parity")

    check(report["overall"] == "GREEN", f"report overall {report['overall']}")
    check(report["errors"] == [], f"report errors {report['errors']}")
    check(report["counts"]["unaccountedSourceRows"] == 0, "unaccounted")
    check(report["counts"]["pbsSourceRows"] == 657, "657 sources")

    # naming fixes
    by_id = {c["id"]: c for c in cities}
    check(by_id["18-hazari"]["displayName"] == "18-Hazari", "18-Hazari")
    check(by_id["46-adda"]["displayName"] == "46-Adda", "46-Adda")
    check(by_id["kingri-pirjo-goth"]["displayName"] == "Kingri", "Kingri")

    if failed:
        print("FAIL")
        for f in failed:
            print(" -", f)
        return 1
    print(
        f"PASS slice2d catalog tests: {len(cities)} cities, "
        f"{report['counts']['unresolvedReviewRequired']} unresolved, licensing blocked"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
