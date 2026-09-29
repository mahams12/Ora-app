#!/usr/bin/env python3
"""
Slice 2A — Prepare CANDIDATE Pakistan city dataset from PBS Census 2023 Table 2.

CANDIDATE — NOT APPROVED — NOT SEEDED
Does NOT write to Firestore.
Does NOT invent cities outside the PBS source.

normalizeCitySlug equivalent (trim + lowercase) is the only storage normalizer.
Multi-word names get spaces→hyphens BEFORE normalize so IDs remain catalog-compatible
(a-z0-9-hyphen). That shaping is documented; it is not a second normalizer.
"""

from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "source"
CANDIDATE = ROOT / "candidate"
NATIONAL_XLSX = SOURCE / "table_2_national.xlsx"

SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

# Population band headers / non-locality rows
BAND_RE = re.compile(
    r"^(?:\d[\d,]*(?:\s*-\s*\d[\d,]*)?|500,000 AND ABOVE|BELOW 5,000|"
    r"\d+\s*AND ABOVE)$",
    re.I,
)

LEGAL_SUFFIX_RE = re.compile(
    r"\s*(?:"
    r"METROPOLITAN CORPORATION|"
    r"MUNICIPAL CORPORATION|"
    r"DISTRICT MUNICIPAL CORPORATION|"
    r"CANTONMENT|"
    r"\bMC\b|"
    r"\bTC\b|"
    r"\bUC\b"
    r")\s*$",
    re.I,
)

PART_OF_RE = re.compile(
    r"^(?P<head>.+?)\s*\(\s*Part of\s+(?P<part>.+?)\s*\)\s*$",
    re.I,
)


def normalize_city_slug(raw: str | None) -> str | None:
    """Mirror backend normalizeCitySlug(): trim + lowercase only."""
    if raw is None or not isinstance(raw, str):
        return None
    slug = raw.strip().lower()
    return slug if slug else None


def shape_slug_input(display_or_base: str) -> str:
    """Spaces → hyphens, strip non [a-z0-9-] after lowercasing path via normalize."""
    s = display_or_base.strip().lower()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s


def title_display(base: str) -> str:
    # Simple title case; keep small connectors lowercase when mid-string.
    words = re.split(r"\s+", base.strip())
    out = []
    for i, w in enumerate(words):
        lw = w.lower()
        if i > 0 and lw in {"of", "the", "and", "de", "al", "e"}:
            out.append(lw)
        else:
            out.append(lw[:1].upper() + lw[1:] if lw else lw)
    return " ".join(out)


def parse_locality_name(raw: str) -> dict:
    name = " ".join(str(raw).split())
    part = None
    m = PART_OF_RE.match(name)
    if m:
        head = m.group("head").strip()
        part = m.group("part").strip()
    else:
        head = name

    upper = head.upper()
    legal_type = None
    if "CANTONMENT" in upper:
        legal_type = "CANTONMENT"
    elif "DISTRICT MUNICIPAL CORPORATION" in upper:
        legal_type = "DMC"
    elif "METROPOLITAN CORPORATION" in upper:
        legal_type = "METROPOLITAN_CORPORATION"
    elif "MUNICIPAL CORPORATION" in upper:
        legal_type = "MUNICIPAL_CORPORATION"
    elif re.search(r"\bMC\b", head, re.I):
        legal_type = "MC"
    elif re.search(r"\bTC\b", head, re.I):
        legal_type = "TC"
    else:
        legal_type = "OTHER"

    base = LEGAL_SUFFIX_RE.sub("", head).strip()
    # Also strip leading DMC / DISTRICT MUNICIPAL CORPORATION leftovers
    base = re.sub(
        r"^(?:DISTRICT\s+MUNICIPAL\s+CORPORATION|MUNICIPAL\s+CORPORATION|"
        r"METROPOLITAN\s+CORPORATION)\s+",
        "",
        base,
        flags=re.I,
    ).strip()
    if not base:
        base = head

    return {
        "sourceName": name,
        "head": head,
        "base": base,
        "partOf": part,
        "legalType": legal_type,
    }


def load_raw_rows() -> list[dict]:
    wb = openpyxl.load_workbook(NATIONAL_XLSX, data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows: list[dict] = []
    current_band = None
    for i, row in enumerate(ws.iter_rows(min_row=1, values_only=True), start=1):
        admin = row[0]
        district = row[1]
        pop = row[2]
        if admin is None:
            continue
        admin_s = str(admin).strip()
        if i <= 3:
            continue
        if district is None and BAND_RE.match(admin_s.replace(",", ",")):
            # band header like "500,000 AND ABOVE" or "100,000 - 199,999"
            if re.search(r"\d", admin_s) and pop is None:
                current_band = admin_s
                continue
        if district is None:
            # non-data
            if pop is None:
                if re.search(r"\d", admin_s):
                    current_band = admin_s
                continue
        if district is None or pop is None:
            continue
        try:
            population = int(pop)
        except (TypeError, ValueError):
            continue

        parsed = parse_locality_name(admin_s)
        district_s = str(district).strip()
        province_guess = province_from_district(district_s)
        rows.append(
            {
                "sourceRow": i,
                "sourceFile": "table_2_national.xlsx",
                "populationBand": current_band,
                "district": district_s,
                "provinceTerritory": province_guess,
                "population2023": population,
                "population2017": row[6],
                **parsed,
            }
        )
    return rows


# Lightweight province hints from known district patterns / names
# (national sheet has no province column; used for reporting only).
KP_HINTS = {
    "PESHAWAR",
    "MARDAN",
    "SWAT",
    "ABBOTTABAD",
    "SWABI",
    "NOWSHERA",
    "KOHAT",
    "BANNU",
    "DERA ISMAIL KHAN",
    "CHARSADDA",
    "MANSEHRA",
    "HARIPUR",
    "LOWER DIR",
    "UPPER DIR",
    "BUNER",
    "MALAKAND",
    "HANGU",
    "KARAK",
    "LAKKI",
    "TANK",
    "BATTAGRAM",
    "TORGHAR",
    "SHANGLA",
    "CHITRAL",
    "KHYBER",
    "KURRAM",
    "MOHMAND",
    "BAJAUR",
    "ORAKZAI",
    "NORTH WAZIRISTAN",
    "SOUTH WAZIRISTAN",
    "KOLAI",
}
SINDH_HINTS = {
    "KARACHI",
    "HYDERABAD",
    "SUKKUR",
    "LARKANA",
    "THATTA",
    "BADIN",
    "SANGHAR",
    "NAUSHAHRO",
    "NAWABSHAH",
    "SHAHEED",
    "MIRPURKHAS",
    "UMERKOT",
    "THARPARKAR",
    "JACOBABAD",
    "SHIKARPUR",
    "GHOTKI",
    "KASHMORE",
    "KAMBAR",
    "DADU",
    "JAMSHORO",
    "MATIARI",
    "TANDO",
    "SBA",
    "KORANGI",
    "MALIR",
    "KEAMARI",
}
BALOCH_HINTS = {
    "QUETTA",
    "GWADAR",
    "TURBAT",
    "KHUZDAR",
    "LORALAI",
    "ZHOB",
    "SIBI",
    "NASIRABAD",
    "JAFARABAD",
    "DERA BUGTI",
    "KOHLU",
    "BARKHAN",
    "MUSAKHEL",
    "PANJGUR",
    "KECH",
    "LASBELA",
    "AWARAN",
    "WASHUK",
    "KHARAN",
    "CHAGAI",
    "NUSHKI",
    "PISHIN",
    "KILLA",
    "ZIARAT",
    "MASTUNG",
    "KALAT",
    "SURAB",
    "HUB",
}


def province_from_district(district: str) -> str:
    d = district.upper().replace(" DISTRICT", "").strip()
    if d == "ISLAMABAD":
        return "Islamabad Capital Territory"
    for h in SINDH_HINTS:
        if h in d:
            return "Sindh"
    for h in BALOCH_HINTS:
        if h in d:
            return "Balochistan"
    for h in KP_HINTS:
        if h in d:
            return "Khyber Pakhtunkhwa"
    return "Punjab"  # residual; national sheet is majority Punjab


def karachi_family(row: dict) -> bool:
    name_u = row["sourceName"].upper()
    dist_u = row["district"].upper()
    if row["legalType"] != "DMC" and "DISTRICT MUNICIPAL CORPORATION" not in name_u:
        return False
    # Karachi city DMCs across renamed districts
    if any(
        x in name_u
        for x in (
            "KARACHI EAST",
            "KARACHI WEST",
            "KARACHI SOUTH",
            "KARACHI CENTRAL",
            "KORANGI",
            "MALIR",
            "KEAMARI",
        )
    ):
        return True
    if any(
        x in dist_u
        for x in (
            "KARACHI EAST",
            "KARACHI WEST",
            "KARACHI SOUTH",
            "KARACHI CENTRAL",
            "KORANGI",
            "MALIR",
            "KEAMARI",
        )
    ) and "DISTRICT MUNICIPAL CORPORATION" in name_u:
        return True
    return False


def coalesce_key(row: dict) -> tuple[str, str, str] | None:
    """
    Return (candidate_id_base, displayName, reason) for HIGH-confidence coalesce,
    or None if not an explicit coalesce rule.
    """
    name_u = row["sourceName"].upper()
    head_u = row["head"].upper()

    if head_u.startswith("LAHORE METROPOLITAN CORPORATION"):
        return (
            "lahore",
            "Lahore",
            "Multiple Lahore Metropolitan Corporation census parts → one passenger city",
        )
    if karachi_family(row):
        return (
            "karachi",
            "Karachi",
            "Karachi District Municipal Corporation / district parts → one passenger city",
        )
    if head_u.startswith("HYDERABAD MUNICIPAL CORPORATION"):
        return (
            "hyderabad",
            "Hyderabad",
            "Hyderabad Municipal Corporation taluka parts → one passenger city",
        )
    if head_u.startswith("QUETTA METROPOLITAN CORPORATION"):
        return (
            "quetta",
            "Quetta",
            "Quetta Metropolitan Corporation subdivision parts → one passenger city",
        )
    # Single-row metros (still mark COALESCED if Part of, else DIRECT handled elsewhere)
    if "Part of" in row["sourceName"] and head_u.startswith("GUJRAT METROPOLITAN"):
        return (
            "gujrat",
            "Gujrat",
            "Gujrat Metropolitan Corporation parts → one passenger city",
        )
    if "Part of" in row["sourceName"] and "METROPOLITAN CORPORATION" in head_u:
        # Other metro splits not in explicit list → do not silent coalesce
        return None
    if "Part of" in row["sourceName"] and "MUNICIPAL CORPORATION" in head_u:
        return None
    return None


def suggested_cantonment_parent(row: dict) -> tuple[str | None, str]:
    dist = row["district"].upper().replace(" DISTRICT", "").strip()
    name_u = row["sourceName"].upper()
    # Explicit name hints
    if "WALTON" in name_u or "LAHORE" in name_u:
        return "lahore", "Name/district points to Lahore"
    if "RAWALPINDI" in name_u or dist == "RAWALPINDI":
        return "rawalpindi", "Name/district points to Rawalpindi"
    if any(x in name_u for x in ("KARACHI", "CLIFTON", "MANORA", "FAISAL")) and (
        "KARACHI" in dist
        or "KORANGI" in dist
        or "MALIR" in dist
        or "KEAMARI" in dist
        or "KARACHI" in name_u
        or "CLIFTON" in name_u
        or "MANORA" in name_u
    ):
        return "karachi", "Name/district points to Karachi metro"
    if "PESHAWAR" in name_u or dist == "PESHAWAR":
        return "peshawar", "Name/district points to Peshawar"
    if "MULTAN" in name_u or dist == "MULTAN":
        return "multan", "Name/district points to Multan"
    if "HYDERABAD" in name_u or dist == "HYDERABAD":
        return "hyderabad", "Name/district points to Hyderabad"
    if "QUETTA" in name_u or dist == "QUETTA":
        return "quetta", "Name/district points to Quetta"
    if "SIALKOT" in name_u or dist == "SIALKOT":
        return "sialkot", "Name/district points to Sialkot"
    if "GUJRANWALA" in name_u or dist == "GUJRANWALA":
        return "gujranwala", "Name/district points to Gujranwala"
    if "TAXILA" in name_u:
        return "taxila", "Named Taxila cantonment / locality"
    if "MURREE" in name_u:
        return "murree", "Named Murree; district is Abbottabad — parent ambiguous"
    if "ORMARA" in name_u:
        return "ormara", "Named Ormara"
    if "CHERAT" in name_u:
        return None, "Cherat Cantonment — military hill station; parent city unclear"
    if "MARDAN" in name_u or dist == "MARDAN":
        return "mardan", "Name/district points to Mardan"
    if "NOWSHERA" in name_u or dist == "NOWSHERA":
        return "nowshera", "Name/district points to Nowshera"
    if "KOHAT" in name_u or dist == "KOHAT":
        return "kohat", "Name/district points to Kohat"
    if "BANNU" in name_u or dist == "BANNU":
        return "bannu", "Name/district points to Bannu"
    if "ABBOTTABAD" in dist and "MURREE" not in name_u:
        return "abbottabad", "District Abbottabad"
    if "LORALAI" in name_u or dist == "LORALAI":
        return "loralai", "Name/district points to Loralai"
    if "ZHOB" in name_u or dist == "ZHOB":
        return "zhob", "Name/district points to Zhob"
    if "GWADAR" in dist:
        return "gwadar", "District Gwadar"
    # Generic: district name as parent suggestion
    if dist:
        return shape_slug_input(dist.lower()), f"Fallback suggestion from district '{row['district']}'"
    return None, "No confident parent"


def make_id(display_or_base: str) -> str | None:
    shaped = shape_slug_input(display_or_base)
    norm = normalize_city_slug(shaped)
    if norm is None:
        return None
    if not SLUG_RE.match(norm):
        return None
    return norm


def main() -> None:
    CANDIDATE.mkdir(parents=True, exist_ok=True)
    raw = load_raw_rows()

    # Phase: classify each row
    coalesce_buckets: dict[str, list[dict]] = defaultdict(list)
    coalesce_meta: dict[str, dict] = {}
    direct_rows: list[dict] = []
    review_rows: list[dict] = []
    cantonment_rows: list[dict] = []

    for row in raw:
        if row["legalType"] == "CANTONMENT":
            parent, reason = suggested_cantonment_parent(row)
            cantonment_rows.append(row)
            review_rows.append(
                {
                    **row,
                    "decision": "REVIEW_REQUIRED",
                    "confidence": "LOW",
                    "reason": (
                        "Cantonment policy: do not auto-create separate Ora city or "
                        f"silently merge. Suggested parent={parent!r}. {reason}"
                    ),
                    "suggestedParentId": parent,
                    "candidateId": None,
                    "displayName": None,
                }
            )
            continue

        ck = coalesce_key(row)
        if ck:
            cid, display, reason = ck
            coalesce_buckets[cid].append(row)
            coalesce_meta[cid] = {
                "displayName": display,
                "reason": reason,
                "confidence": "HIGH",
                "decision": "COALESCED",
            }
            continue

        # Remaining "Part of" splits without rule → review
        if row["partOf"]:
            review_rows.append(
                {
                    **row,
                    "decision": "REVIEW_REQUIRED",
                    "confidence": "LOW",
                    "reason": (
                        "Split locality (Part of …) without an explicit HIGH-confidence "
                        "coalesce rule — do not invent a merge"
                    ),
                    "suggestedParentId": None,
                    "candidateId": None,
                    "displayName": None,
                }
            )
            continue

        # Odd university / special TCs
        if "UNIVERSITY" in row["sourceName"].upper():
            review_rows.append(
                {
                    **row,
                    "decision": "REVIEW_REQUIRED",
                    "confidence": "LOW",
                    "reason": "Special/university TC — may not be a passenger service city",
                    "suggestedParentId": None,
                    "candidateId": None,
                    "displayName": None,
                }
            )
            continue

        # Direct mapping
        display = title_display(row["base"])
        cid = make_id(row["base"])
        if cid is None:
            review_rows.append(
                {
                    **row,
                    "decision": "REVIEW_REQUIRED",
                    "confidence": "LOW",
                    "reason": "Could not derive slug-shaped canonical id via normalizeCitySlug path",
                    "suggestedParentId": None,
                    "candidateId": None,
                    "displayName": display,
                }
            )
            continue

        direct_rows.append(
            {
                **row,
                "decision": "DIRECT",
                "confidence": "HIGH",
                "reason": "Single urban locality row maps 1:1 to candidate service city",
                "candidateId": cid,
                "displayName": display,
            }
        )

    # Build coalesced provenance entries
    provenance: list[dict] = []
    catalog_candidates: list[dict] = []

    for cid, rows in sorted(coalesce_buckets.items()):
        meta = coalesce_meta[cid]
        pop = sum(r["population2023"] for r in rows)
        entry = {
            "candidateId": cid,
            "displayName": meta["displayName"],
            "sourceRows": [r["sourceRow"] for r in rows],
            "sourceNames": [r["sourceName"] for r in rows],
            "districts": sorted({r["district"] for r in rows}),
            "provincesTerritories": sorted({r["provinceTerritory"] for r in rows}),
            "population2023": pop,
            "decision": "COALESCED",
            "reason": meta["reason"],
            "confidence": meta["confidence"],
            "sourceRowCount": len(rows),
        }
        provenance.append(entry)

    for row in direct_rows:
        entry = {
            "candidateId": row["candidateId"],
            "displayName": row["displayName"],
            "sourceRows": [row["sourceRow"]],
            "sourceNames": [row["sourceName"]],
            "districts": [row["district"]],
            "provincesTerritories": [row["provinceTerritory"]],
            "population2023": row["population2023"],
            "decision": "DIRECT",
            "reason": row["reason"],
            "confidence": row["confidence"],
            "sourceRowCount": 1,
            "legalType": row["legalType"],
        }
        provenance.append(entry)

    # Detect duplicate canonical IDs among COALESCED+DIRECT
    by_id: dict[str, list[dict]] = defaultdict(list)
    for e in provenance:
        if e.get("candidateId") and e["decision"] in ("COALESCED", "DIRECT"):
            by_id[e["candidateId"]].append(e)

    demoted_ids: set[str] = set()
    demote_keys: set[tuple] = set()  # (decision, first source row, candidateId)

    for cid, entries in by_id.items():
        if len(entries) < 2:
            continue
        demoted_ids.add(cid)
        coalesced = [e for e in entries if e["decision"] == "COALESCED"]
        directs = [e for e in entries if e["decision"] == "DIRECT"]
        owners = [
            f"{e['decision']}:{e['displayName']}@rows{e['sourceRows']}" for e in entries
        ]
        if coalesced and directs:
            # Keep metro coalesce; demote colliding DIRECT rows only
            for e in directs:
                demote_keys.add(("DIRECT", e["sourceRows"][0], cid))
        else:
            # Ambiguous DIRECT vs DIRECT (or multi coalesce) — demote all
            for e in entries:
                demote_keys.add((e["decision"], e["sourceRows"][0], cid))

    new_prov: list[dict] = []
    for e in provenance:
        key = (e["decision"], e["sourceRows"][0], e.get("candidateId"))
        if key in demote_keys:
            owners = [
                f"{x['decision']}:{x['displayName']}"
                for x in by_id.get(e["candidateId"], [])
            ]
            new_prov.append(
                {
                    **e,
                    "decision": "REVIEW_REQUIRED",
                    "confidence": "LOW",
                    "reason": (
                        e["reason"]
                        + f" | DUPLICATE_CANONICAL_ID '{e.get('candidateId')}' shared by: "
                        + "; ".join(owners)
                    ),
                    "duplicateCanonicalId": True,
                    "priorDecision": e["decision"],
                }
            )
        else:
            new_prov.append(e)
    provenance = new_prov

    for row in review_rows:
        provenance.append(
            {
                "candidateId": row.get("candidateId"),
                "displayName": row.get("displayName"),
                "sourceRows": [row["sourceRow"]],
                "sourceNames": [row["sourceName"]],
                "districts": [row["district"]],
                "provincesTerritories": [row["provinceTerritory"]],
                "population2023": row["population2023"],
                "decision": "REVIEW_REQUIRED",
                "reason": row["reason"],
                "confidence": row["confidence"],
                "suggestedParentId": row.get("suggestedParentId"),
                "legalType": row["legalType"],
                "sourceRowCount": 1,
            }
        )

    # Catalog file: only COALESCED/DIRECT that remain approved-as-candidate (not demoted)
    for e in provenance:
        if e["decision"] in ("COALESCED", "DIRECT") and e.get("candidateId"):
            catalog_candidates.append(
                {
                    "id": e["candidateId"],
                    "displayName": e["displayName"],
                    "active": True,
                }
            )

    # Sort catalog by displayName
    catalog_candidates.sort(key=lambda x: (x["displayName"].lower(), x["id"]))

    # Deduplicate catalog by id (should already be unique after demotion)
    seen = set()
    unique_catalog = []
    for c in catalog_candidates:
        if c["id"] in seen:
            continue
        seen.add(c["id"])
        unique_catalog.append(c)
    catalog_candidates = unique_catalog

    # Stats
    pops = [e["population2023"] for e in provenance if e.get("population2023")]
    def band(p: int) -> str:
        if p >= 500_000:
            return ">=500k"
        if p >= 100_000:
            return "100k-499k"
        if p >= 50_000:
            return "50k-99k"
        if p >= 25_000:
            return "25k-49k"
        if p >= 10_000:
            return "10k-24k"
        if p >= 5_000:
            return "5k-9k"
        return "<5k"

    # Population distribution for CATALOG candidates (summed coalesced)
    cat_pop_bands = Counter()
    for e in provenance:
        if e["decision"] in ("COALESCED", "DIRECT"):
            cat_pop_bands[band(int(e["population2023"]))] += 1

    raw_pop_bands = Counter(band(r["population2023"]) for r in raw)

    decisions = Counter(e["decision"] for e in provenance)
    metro_split_raw = sum(1 for r in raw if r["partOf"])
    cantonment_count = len(cantonment_rows)

    provinces = Counter(r["provinceTerritory"] for r in raw)

    stats = {
        "label": "CANDIDATE — NOT APPROVED — NOT SEEDED",
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "source": {
            "organization": "Pakistan Bureau of Statistics",
            "dataset": "7th Population and Housing Census 2023 — Table 2",
            "title": "Urban localities by population size and their population by sex, annual growth rate and household size",
            "primaryPage": "https://www.pbs.gov.pk/result-excel/",
            "primaryExcelUrl": "https://www.pbs.gov.pk/wp-content/uploads/2020/07/table_2_national.xlsx",
            "primaryPdfUrl": "https://www.pbs.gov.pk/wp-content/uploads/census_tables/tables/table_2_national.pdf",
            "localExcel": "source/table_2_national.xlsx",
            "downloadDateUtc": (SOURCE / "SOURCE_MANIFEST.txt").read_text().split("download_date_utc=")[-1].split("\n")[0] if (SOURCE / "SOURCE_MANIFEST.txt").exists() else None,
        },
        "rawPbsLocalityRows": len(raw),
        "provinceTerritoryCountsRaw": dict(provinces),
        "candidateCatalogCities": len(catalog_candidates),
        "provenanceEntries": len(provenance),
        "decisionCounts": dict(decisions),
        "coalescedGroups": sum(1 for e in provenance if e["decision"] == "COALESCED"),
        "directMappings": sum(1 for e in provenance if e["decision"] == "DIRECT"),
        "reviewRequired": sum(1 for e in provenance if e["decision"] == "REVIEW_REQUIRED"),
        "cantonmentSourceRows": cantonment_count,
        "metropolitanOrSplitSourceRows": metro_split_raw,
        "duplicateCanonicalIdsDemoted": sorted(demoted_ids),
        "duplicateCanonicalIdCount": len(demoted_ids),
        "rawPopulationBandCounts": dict(raw_pop_bands),
        "candidatePopulationBandCounts": dict(cat_pop_bands),
        "licensing": "LICENSE_REVIEW_REQUIRED",
        "firestore": "NOT_TOUCHED",
    }

    # Write files
    catalog_path = CANDIDATE / "candidate_city_catalog.json"
    prov_path = CANDIDATE / "candidate_city_provenance.json"
    stats_path = CANDIDATE / "candidate_city_stats.json"
    review_path = CANDIDATE / "candidate_city_review.md"

    catalog_doc = {
        "_meta": {
            "status": "CANDIDATE — NOT APPROVED — NOT SEEDED",
            "warning": "Do not import into Firestore until product/ops + license approval.",
            "countryCode": "PK (enforced by CityCatalogService; omitted here per import contract)",
            "activeNote": "active=true on candidates is a PLACEHOLDER for review — not a production activation decision",
            "source": stats["source"],
            "licensing": "LICENSE_REVIEW_REQUIRED",
        },
        "cities": catalog_candidates,
    }

    with catalog_path.open("w", encoding="utf-8") as f:
        json.dump(catalog_doc, f, ensure_ascii=False, indent=2)
        f.write("\n")

    with prov_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "_meta": {
                    "status": "PROVENANCE / AUDIT — NOT FOR FIRESTORE IMPORT",
                    "licensing": "LICENSE_REVIEW_REQUIRED",
                },
                "records": provenance,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
        f.write("\n")

    with stats_path.open("w", encoding="utf-8") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # Review markdown
    coalesced = [e for e in provenance if e["decision"] == "COALESCED"]
    reviews = [e for e in provenance if e["decision"] == "REVIEW_REQUIRED"]
    cant_reviews = [e for e in reviews if e.get("legalType") == "CANTONMENT"]

    lines = []
    lines.append("# Candidate Pakistan City Dataset — Product Review Pack")
    lines.append("")
    lines.append("**Status:** CANDIDATE — NOT APPROVED — NOT SEEDED")
    lines.append("")
    lines.append("**Firestore:** NOT TOUCHED")
    lines.append("")
    lines.append("**Licensing:** LICENSE_REVIEW_REQUIRED")
    lines.append("")
    lines.append("## Source")
    lines.append("")
    lines.append("- **Organization:** Pakistan Bureau of Statistics (PBS)")
    lines.append("- **Dataset:** 7th Population and Housing Census 2023 — Table 2")
    lines.append(
        "- **Title:** Urban localities by population size and their population by sex, annual growth rate and household size"
    )
    lines.append(f"- **Result page:** {stats['source']['primaryPage']}")
    lines.append(f"- **Official Excel:** {stats['source']['primaryExcelUrl']}")
    lines.append(f"- **Official PDF (cross-check):** {stats['source']['primaryPdfUrl']}")
    lines.append(f"- **Local unmodified source:** `source/table_2_national.xlsx`")
    lines.append(f"- **Download date (UTC):** {stats['source'].get('downloadDateUtc')}")
    lines.append(f"- **Raw urban locality rows parsed:** {stats['rawPbsLocalityRows']}")
    lines.append(
        f"- **Province/territory hints (from district names; national sheet has no province col):** {json.dumps(stats['provinceTerritoryCountsRaw'])}"
    )
    lines.append("")
    lines.append("## Transformation Rules")
    lines.append("")
    lines.append("1. Parse PBS Table 2 national Excel (preserve source row + name + district + population).")
    lines.append("2. **Do not** map 1 PBS row = 1 Ora city when the row is a metro/DMC split.")
    lines.append("3. HIGH-confidence coalescing (explicit only):")
    lines.append("   - Lahore Metropolitan Corporation (all Part-of tehsil rows) → `lahore`")
    lines.append("   - Karachi DMC family (Karachi East/West/South/Central, Korangi, Malir, Keamari) → `karachi`")
    lines.append("   - Hyderabad Municipal Corporation parts → `hyderabad`")
    lines.append("   - Quetta Metropolitan Corporation parts → `quetta`")
    lines.append("4. Other `Part of …` splits without an explicit rule → `REVIEW_REQUIRED` (not forced).")
    lines.append("5. Cantonments → `REVIEW_REQUIRED` with suggested parent only (no auto-merge, no auto `*-cantonment` city).")
    lines.append("6. Remaining single MC/TC/Municipal Corporation rows → `DIRECT` candidate.")
    lines.append("7. Display names: cleaned passenger-facing Title Case (not raw census strings).")
    lines.append(
        "8. Canonical id: multi-word spaces→hyphens, then **only** `normalizeCitySlug()` (trim+lowercase); must match `^[a-z0-9]+(?:-[a-z0-9]+)*$`."
    )
    lines.append("9. Duplicate canonical ids → demoted to `REVIEW_REQUIRED` (`DUPLICATE_CANONICAL_ID`).")
    lines.append("10. **No population floor** applied.")
    lines.append("11. `active: true` in the candidate catalog file is a **placeholder for review**, not ops activation.")
    lines.append("")
    lines.append("## Candidate Count")
    lines.append("")
    lines.append(f"- Raw PBS locality rows: **{stats['rawPbsLocalityRows']}**")
    lines.append(f"- Candidate Ora cities (catalog file): **{stats['candidateCatalogCities']}**")
    lines.append(f"- Coalesced groups: **{stats['coalescedGroups']}**")
    lines.append(f"- Direct mappings: **{stats['directMappings']}**")
    lines.append(f"- Review-required provenance entries: **{stats['reviewRequired']}**")
    lines.append("")
    lines.append("## Coalescing Decisions")
    lines.append("")
    for e in coalesced:
        lines.append(
            f"- **{e['displayName']}** (`{e['candidateId']}`) — {e['sourceRowCount']} source rows; "
            f"pop2023 sum={e['population2023']:,}; districts={', '.join(e['districts'])}"
        )
        lines.append(f"  - Reason: {e['reason']}")
    if not coalesced:
        lines.append("- (none)")
    lines.append("")
    lines.append("## Cantonment Decisions")
    lines.append("")
    lines.append(
        f"- Cantonment source rows: **{cantonment_count}** — all marked `REVIEW_REQUIRED` (no silent merge / no separate auto cities)."
    )
    lines.append("- Suggested parents (for human review only):")
    for e in sorted(cant_reviews, key=lambda x: x["sourceNames"][0]):
        lines.append(
            f"  - `{e['sourceNames'][0]}` ({e['districts'][0]}, pop {e['population2023']:,}) "
            f"→ suggestedParent=`{e.get('suggestedParentId')}`"
        )
    lines.append("")
    lines.append("## Ambiguous Records")
    lines.append("")
    lines.append(f"- Total `REVIEW_REQUIRED` entries: **{len(reviews)}**")
    lines.append(f"- Of which cantonments: **{len(cant_reviews)}**")
    lines.append(f"- Metropolitan/split source rows in raw data: **{metro_split_raw}**")
    non_cant = [e for e in reviews if e.get("legalType") != "CANTONMENT"]
    lines.append(f"- Non-cantonment reviews: **{len(non_cant)}** (see provenance JSON for full list)")
    for e in non_cant[:40]:
        lines.append(
            f"  - row {e['sourceRows'][0]}: {e['sourceNames'][0]} — {e['reason'][:120]}"
        )
    if len(non_cant) > 40:
        lines.append(f"  - … +{len(non_cant) - 40} more in provenance file")
    lines.append("")
    lines.append("## Duplicate IDs")
    lines.append("")
    if demoted_ids:
        lines.append(f"- Demoted duplicate canonical ids: {', '.join(sorted(demoted_ids))}")
    else:
        lines.append("- None after demotion pass (or none detected).")
    lines.append("")
    lines.append("## Population Distribution")
    lines.append("")
    lines.append("### Raw PBS locality rows (no coalesce)")
    lines.append("")
    for k in [">=500k", "100k-499k", "50k-99k", "25k-49k", "10k-24k", "5k-9k", "<5k"]:
        lines.append(f"- {k}: {raw_pop_bands.get(k, 0)}")
    lines.append("")
    lines.append("### Candidate catalog cities (coalesced sums / direct)")
    lines.append("")
    for k in [">=500k", "100k-499k", "50k-99k", "25k-49k", "10k-24k", "5k-9k", "<5k"]:
        lines.append(f"- {k}: {cat_pop_bands.get(k, 0)}")
    lines.append("")
    lines.append("No population cutoff was applied.")
    lines.append("")
    lines.append("## Licensing Status")
    lines.append("")
    lines.append("**LICENSE_REVIEW_REQUIRED**")
    lines.append("")
    lines.append(
        "PBS dissemination materials describe Tier 1 aggregate products as reusable with attribution "
        "under an open-government-style licence. That is **not** a substitute for Ora legal clearance "
        "to store a derived city catalog in Firestore and expose it via API."
    )
    lines.append("")
    lines.append("## Product Decisions Still Required")
    lines.append("")
    lines.append("1. Approve or revise HIGH-confidence coalescing (Lahore, Karachi, Hyderabad, Quetta).")
    lines.append("2. Cantonment policy: merge into parent vs exclude vs separate service cities.")
    lines.append("3. Resolve every `REVIEW_REQUIRED` row (accept / merge / drop).")
    lines.append("4. Confirm displayName spelling (English Title Case vs official PBS casing).")
    lines.append("5. Confirm multi-word slug shaping (spaces→hyphens then `normalizeCitySlug`).")
    lines.append("6. Activation policy: all candidates `active=true` vs staged rollout.")
    lines.append("7. Optional later population floor — **not** applied here.")
    lines.append("8. **Legal/license approval** before any Firestore population.")
    lines.append("9. Deliver a signed approved import list matching CityCatalogService contract.")
    lines.append("")
    lines.append("## Files")
    lines.append("")
    lines.append("- `candidate/candidate_city_catalog.json`")
    lines.append("- `candidate/candidate_city_provenance.json`")
    lines.append("- `candidate/candidate_city_stats.json`")
    lines.append("- `candidate/candidate_city_review.md`")
    lines.append("- `source/` — unmodified PBS downloads + manifest")
    lines.append("")

    review_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(json.dumps({k: stats[k] for k in (
        "rawPbsLocalityRows",
        "candidateCatalogCities",
        "coalescedGroups",
        "directMappings",
        "reviewRequired",
        "cantonmentSourceRows",
        "duplicateCanonicalIdCount",
        "licensing",
    )}, indent=2))


if __name__ == "__main__":
    main()
