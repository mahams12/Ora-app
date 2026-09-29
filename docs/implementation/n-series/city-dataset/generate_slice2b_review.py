#!/usr/bin/env python3
"""Slice 2B — generate ambiguity review markdown from existing Slice 2A package.
Does NOT modify candidate_city_catalog.json or write to Firestore.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "candidate"
PROV = json.load(open(ROOT / "candidate_city_provenance.json"))["records"]
CATALOG = json.load(open(ROOT / "candidate_city_catalog.json"))["cities"]
REVIEWS = [e for e in PROV if e["decision"] == "REVIEW_REQUIRED"]
COALESCED = [e for e in PROV if e["decision"] == "COALESCED"]

PART = re.compile(r"\(\s*Part of\s+(.+?)\s*\)", re.I)


def tehsil_of(name: str) -> str:
    m = PART.search(name)
    return m.group(1) if m else "—"


def categorize(e: dict) -> str:
    name = e["sourceNames"][0].upper()
    reason = e.get("reason", "")
    lt = e.get("legalType")
    if lt == "CANTONMENT" or "CANTONMENT" in name:
        return "A"
    if e.get("duplicateCanonicalId") or "DUPLICATE_CANONICAL_ID" in reason:
        return "D"
    if "UNIVERSITY" in name:
        return "E"
    if "Part of" in e["sourceNames"][0] or "Split locality" in reason:
        if "MUNICIPAL CORPORATION" in name or "METROPOLITAN" in name:
            return "B"
        return "C"
    return "F"


def recommend(e: dict, cat: str) -> tuple[str, str]:
    parent = e.get("suggestedParentId")
    name = e["sourceNames"][0]
    if cat == "A":
        if parent is None or "Cherat" in name:
            return (
                "REVIEW_REQUIRED",
                "No clear passenger-facing parent / specialty military site",
            )
        if "Murree Gallies" in name:
            return (
                "REVIEW_REQUIRED",
                "Murree vs Abbottabad parent ambiguity",
            )
        if "WAH CANTONMENT" in name.upper():
            return (
                "REVIEW_REQUIRED",
                "Wah is often treated as its own town vs Rawalpindi suburb — product must choose",
            )
        # District-admin parents inside Karachi metro are not passenger cities
        if parent in ("malir", "keamari", "korangi") or (
            parent and parent.startswith("karachi") and parent != "karachi"
        ):
            return (
                "REVIEW_REQUIRED",
                f"Suggested parent `{parent}` is admin/district-shaped; passenger merge target is likely `karachi`",
            )
        if parent == "ormara":
            return (
                "REVIEW_REQUIRED",
                "Ormara Cantonment vs Ormara town / Gwadar — confirm parent",
            )
        return (
            "MERGE_WITH_PARENT",
            f"Proposal only: treat as part of `{parent}` for pickup-city UX (not a separate Ora city)",
        )
    if cat == "B":
        return (
            "COALESCE",
            "Proposal only: Sukkur MC taluka parts → one passenger city `sukkur` (same pattern as Hyderabad)",
        )
    if cat == "D":
        return (
            "REVIEW_REQUIRED",
            "Genuine cross-district name collision — product must choose distinct IDs or drop one; no silent suffixes",
        )
    if cat == "E":
        return (
            "EXCLUDE_FROM_CITY_CATALOG",
            "Proposal only: university township unlikely as passenger pickup-city selector row",
        )
    return ("REVIEW_REQUIRED", "Needs product judgment")


def display_proposal(e: dict, cat: str) -> str:
    if e.get("displayName"):
        return e["displayName"]
    name = e["sourceNames"][0]
    if cat == "A":
        base = PART.sub("", name)
        base = re.sub(r"\s*CANTONMENT\s*", " ", base, flags=re.I).strip()
        return " ".join(w.capitalize() for w in base.lower().split()) if base else "—"
    if cat == "B":
        return "Sukkur"
    if cat == "E":
        return "Peshawar University"
    return "—"


def esc(s: object) -> str:
    return str(s).replace("|", "\\|")


def why_text(e: dict, cat: str) -> str:
    if e.get("duplicateCanonicalId"):
        return f"DUPLICATE_CANONICAL_ID → `{e.get('candidateId')}`"
    if cat == "A":
        return "Cantonment — no auto city / no silent merge"
    if cat == "B":
        return "Municipal Corporation Part-of split without approved coalesce rule"
    if cat == "E":
        return "University / institutional TC"
    return e.get("reason", "").split("|")[0].strip()


def write_review_required() -> None:
    cats = Counter(categorize(e) for e in REVIEWS)
    order = {"A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "F": 5}
    reviews_sorted = sorted(
        REVIEWS,
        key=lambda e: (order[categorize(e)], -(e.get("population2023") or 0), e["sourceNames"][0]),
    )

    lines: list[str] = []
    lines += [
        "# REVIEW_REQUIRED Cities — Complete Decision Table",
        "",
        "**Status:** CANDIDATE ambiguity review — **NOT APPROVED** — **NOT SEEDED**",
        "",
        "**Source package:** Slice 2A candidate from PBS Census 2023 Table 2",
        "",
        "**Rule:** Recommended treatment is advisory for product/ops. It is **not** a silent final decision.",
        "",
        "Allowed recommended-treatment labels: `DIRECT` | `COALESCE` | `MERGE_WITH_PARENT` | `EXCLUDE_FROM_CITY_CATALOG` | `REVIEW_REQUIRED`",
        "",
        "## Category breakdown",
        "",
        "| Category | Code | Count |",
        "| -------- | ---- | ----- |",
        f"| Cantonments | A | {cats['A']} |",
        f"| Metropolitan / municipal split | B | {cats['B']} |",
        f"| Other \"Part of…\" records | C | {cats.get('C', 0)} |",
        f"| Duplicate canonical IDs | D | {cats['D']} |",
        f"| University / institutional township | E | {cats['E']} |",
        f"| Other special cases | F | {cats.get('F', 0)} |",
        f"| **Total** | | **{len(REVIEWS)}** |",
        "",
        "## Complete table (all 67)",
        "",
        "| # | PBS source locality | Province/region | District | Tehsil / part-of | Pop 2023 | Source row | Proposed parent | Candidate ID | Why REVIEW_REQUIRED | Recommended treatment | Confidence | DISPLAY_NAME_PROPOSAL |",
        "| - | ------------------- | --------------- | -------- | ---------------- | -------- | ---------- | --------------- | ------------ | ------------------- | --------------------- | ---------- | --------------------- |",
    ]

    for i, e in enumerate(reviews_sorted, 1):
        cat = categorize(e)
        name = e["sourceNames"][0]
        rec, rec_reason = recommend(e, cat)
        lines.append(
            "| {i} | {name} | {prov} | {dist} | {teh} | {pop} | {row} | `{parent}` | `{cid}` | {why} | **{rec}** — {rr} | {conf} | {dprop} |".format(
                i=i,
                name=esc(name),
                prov=esc(e.get("provincesTerritories", ["—"])[0]),
                dist=esc(e.get("districts", ["—"])[0]),
                teh=esc(tehsil_of(name)),
                pop=f"{e.get('population2023', 0):,}",
                row=",".join(str(x) for x in e.get("sourceRows", [])),
                parent=esc(e.get("suggestedParentId") or "—"),
                cid=esc(e.get("candidateId") or "—"),
                why=esc(why_text(e, cat)),
                rec=rec,
                rr=esc(rec_reason),
                conf=e.get("confidence", "LOW"),
                dprop=esc(display_proposal(e, cat)),
            )
        )

    lines += ["", "## A. Cantonments (55)", ""]
    lines += [
        "Policy constraint from Slice 2A: do **not** auto-create `*-cantonment` Ora cities; do **not** silently merge.",
        "",
        "| Cantonment | District | Pop 2023 | Suggested parent | Recommended treatment | Reason |",
        "| ---------- | -------- | -------- | ---------------- | --------------------- | ------ |",
    ]
    for e in sorted(
        [x for x in REVIEWS if categorize(x) == "A"],
        key=lambda x: -(x["population2023"]),
    ):
        rec, rr = recommend(e, "A")
        lines.append(
            f"| {esc(e['sourceNames'][0])} | {esc(e['districts'][0])} | {e['population2023']:,} | `{e.get('suggestedParentId')}` | **{rec}** | {esc(rr)} |"
        )

    lines += [
        "",
        "### Cantonment notes for product",
        "",
        "- **Lahore cluster:** Walton + Lahore Cantonment — suggested parent `lahore` (already coalesced metro).",
        "- **Rawalpindi cluster:** Rawalpindi + Wah + Chaklala — suggested parent `rawalpindi` (Wah is often perceived as its own town — confirm).",
        "- **Karachi cluster:** Faisal / Clifton / Malir / Manora / Karachi Cantonments — Malir Cantt currently suggests `malir`; passenger-facing parent is likely `karachi` if merging.",
        "- **Specialty:** Cherat (no parent), Murree Gallies (Murree vs Abbottabad), Ormara Cantt (Ormara vs Gwadar).",
        "",
        "## B. Metropolitan / municipal splits (not yet coalesced)",
        "",
    ]
    b_list = [e for e in REVIEWS if categorize(e) == "B"]
    for e in b_list:
        lines.append(
            f"- **{e['sourceNames'][0]}** — {e['districts'][0]} — pop {e['population2023']:,} — row {e['sourceRows'][0]}"
        )
    lines += [
        "",
        f"Combined Sukkur MC parts population if coalesced: **{sum(e['population2023'] for e in b_list):,}**",
        "",
        "**Proposal (not approved):** `COALESCE` → `sukkur` / displayName `Sukkur` (same pattern as Hyderabad MC parts).",
        "",
        "## C. Other Part-of records",
        "",
    ]
    c_list = [e for e in REVIEWS if categorize(e) == "C"]
    if not c_list:
        lines.append(
            "_None in this REVIEW_REQUIRED set (Karachi/Lahore/Hyderabad/Quetta Part-of rows were already coalesced in Slice 2A)._"
        )
    else:
        for e in c_list:
            lines.append(f"- {e['sourceNames'][0]}")

    lines += ["", "## D. Duplicate canonical IDs", ""]
    lines += [
        "`normalizeCitySlug` = trim + lowercase only. Multi-word shaping uses spaces→hyphens before that.",
        "Collisions happen when **different districts** share the same cleaned base name.",
        "",
    ]

    notes = {
        "sahiwal": (
            "Sahiwal MetCorp (Sahiwal District, ~538k) vs Sahiwal MC (Sargodha District, ~57k) are **different passenger-facing places**.",
            "Possible approach (examples only — product must choose): keep larger as `sahiwal`; disambiguate smaller with a product-approved naming rule — **do not invent suffixes in this review**.",
        ),
        "khanpur": (
            "Khanpur MC (Rahim Yar Khan, ~247k) vs Khanpur TC (Shikarpur, ~18k) — **different places**.",
            "Product must assign distinct canonical IDs or exclude one.",
        ),
        "khangarh": (
            "Khangarh TC (Ghotki, Sindh) vs Khangarh MC (Muzaffargarh, Punjab) — **different places**.",
            "Product must assign distinct canonical IDs or exclude one.",
        ),
        "karampur": (
            "Karampur TC (Vehari, Punjab) vs Karampur TC (Kashmore, Sindh) — **different places**.",
            "Product must assign distinct canonical IDs or exclude one.",
        ),
        "hyderabad": (
            "Collision is between **coalesced Hyderabad (Sindh) metro** (kept in catalog) and **Hyderabad TC in Bhakkar District (Punjab)** (~25k).",
            "These are **different passenger-facing places**. Punjab TC must not steal `hyderabad` from Sindh metro. Distinct id for the TC is product-owned — **not assigned here**.",
        ),
    }

    for cid in ["sahiwal", "khanpur", "khangarh", "karampur", "hyderabad"]:
        es = [e for e in REVIEWS if e.get("candidateId") == cid and (
            e.get("duplicateCanonicalId") or "DUPLICATE_CANONICAL_ID" in e.get("reason", "")
        )]
        # hyderabad review is only the TC; still show
        if cid == "hyderabad":
            es = [e for e in REVIEWS if e.get("candidateId") == "hyderabad"]
        lines += [f"### `{cid}`", ""]
        lines += [
            "| PBS source | District | Pop | Prior decision | Display | Why same ID |",
            "| ---------- | -------- | --- | -------------- | ------- | ----------- |",
        ]
        for e in es:
            lines.append(
                f"| {esc(e['sourceNames'][0])} | {esc(e['districts'][0])} | {e['population2023']:,} | {e.get('priorDecision')} | {e.get('displayName')} | cleaned base → `{cid}` |"
            )
        lines.append("")
        for n in notes[cid]:
            lines.append(f"- {n}")
        lines.append("")

    lines += ["## E. University / institutional", ""]
    for e in [x for x in REVIEWS if categorize(x) == "E"]:
        lines.append(
            f"- **{e['sourceNames'][0]}** — {e['districts'][0]} — pop {e['population2023']:,} — row {e['sourceRows'][0]}"
        )
        lines.append(
            "  - Recommended: **EXCLUDE_FROM_CITY_CATALOG** (proposal). Alternative: coverage via `peshawar` without a selector row."
        )
    lines += ["", "## F. Other", ""]
    f_list = [e for e in REVIEWS if categorize(e) == "F"]
    if not f_list:
        lines.append("_None._")
    else:
        for e in f_list:
            lines.append(f"- {e['sourceNames'][0]} — {e['reason']}")

    lines += ["", "## Metro coalesce validation (already in candidate catalog)", ""]
    for e in COALESCED:
        lines += [
            f"### {e['displayName']} (`{e['candidateId']}`)",
            "",
            f"- Source rows: **{e['sourceRowCount']}**",
            f"- Combined population 2023: **{e['population2023']:,}**",
            f"- Districts: {', '.join(e['districts'])}",
            f"- Reason: {e['reason']}",
            "- Source localities:",
        ]
        for n, r in zip(e["sourceNames"], e["sourceRows"]):
            lines.append(f"  - row {r}: {n}")
        lines += [
            "- **Review verdict:** Source evidence is **consistent** with one passenger-facing city. **No change recommended** in this review (product still must formally approve).",
            "",
        ]

    # Population bands
    cat_ids = {c["id"] for c in CATALOG}
    id_to_pop = {
        e["candidateId"]: e["population2023"]
        for e in PROV
        if e["decision"] in ("COALESCED", "DIRECT") and e.get("candidateId") in cat_ids
    }

    def band(p: int) -> str:
        if p > 1_000_000:
            return ">1m"
        if p >= 500_000:
            return "500k–1m"
        if p >= 100_000:
            return "100k–500k"
        if p >= 50_000:
            return "50k–100k"
        if p >= 25_000:
            return "25k–50k"
        if p >= 10_000:
            return "10k–25k"
        if p >= 5_000:
            return "5k–10k"
        return "<5k"

    bands = Counter(band(id_to_pop[i]) for i in cat_ids)
    lines += [
        "## Population distribution (candidate catalog — informational)",
        "",
        "No population floor applied.",
        "",
        "| Band | Candidate cities |",
        "| ---- | ---------------- |",
    ]
    for k in ["<5k", "5k–10k", "10k–25k", "25k–50k", "50k–100k", "100k–500k", "500k–1m", ">1m"]:
        lines.append(f"| {k} | {bands.get(k, 0)} |")
    lines += [
        f"| **Total** | **{sum(bands.values())}** |",
        "",
        "## Licensing",
        "",
        "**LICENSE_REVIEW_REQUIRED** — unchanged from Slice 2A.",
        "",
        "## Extraction bugs",
        "",
        "_None identified that require changing `candidate_city_catalog.json` in this slice._",
        "",
        "Note: province/territory on provenance rows are **hints derived from district names** (national Table 2 has no province column).",
        "",
    ]

    path = ROOT / "review_required_cities.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", path, "reviews", len(REVIEWS), "cats", dict(cats))


def write_decisions() -> None:
    lines = [
        "# City Catalog — Product / Ops Decision Matrix (Slice 2B)",
        "",
        "**Status:** Decisions **REQUIRED** — nothing below is silently approved.",
        "",
        "**Candidate dataset remains:** CANDIDATE — NOT APPROVED — NOT SEEDED",
        "",
        "Related: [`review_required_cities.md`](review_required_cities.md), [`candidate_city_review.md`](candidate_city_review.md)",
        "",
        "---",
        "",
        "## D-CITY-GEOGRAPHIC-UNIT",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | PBS Census 2023 **urban localities** (657 rows) transformed into passenger-facing **service cities** (555 candidates + 67 reviews). |",
        "| **Options** | (1) Urban localities coalesced to service cities (current direction). (2) Districts (~160). (3) All raw PBS rows 1:1. (4) Major cities only. |",
        "| **Evidence** | Architecture freeze: Redis shard = passenger city id; villages/PPL too fine; districts too coarse for mega-cities. |",
        "| **Decision required** | Confirm service-city unit = coalesced urban locality (not district, not every census row). |",
        "",
        "## D-CITY-METRO-COALESCE",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | HIGH-confidence coalesces in candidate catalog: **Lahore** (5), **Karachi** (28), **Hyderabad** (2), **Quetta** (4). Sukkur MC parts still REVIEW_REQUIRED. |",
        "| **Options** | (1) Approve current four. (2) Add Sukkur coalesce. (3) Split any metro back. (4) Different Karachi model (e.g. keep districts). |",
        "| **Evidence** | See metro section in `review_required_cities.md` — Part-of rows are census partitions of one corporation/metro. |",
        "| **Decision required** | Formal approve/reject of Lahore/Karachi/Hyderabad/Quetta; decide Sukkur. |",
        "",
        "## D-CITY-CANTONMENT",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | 55 cantonment rows are REVIEW_REQUIRED; not in candidate catalog; suggested parents only. |",
        "| **Options** | (1) `MERGE_WITH_PARENT` into metro/city. (2) `EXCLUDE_FROM_CITY_CATALOG`. (3) Separate Ora cities (not recommended by architecture). (4) Mixed by cluster (e.g. merge Lahore/Karachi cantts; review Wah/Murree). |",
        "| **Evidence** | Full cantonment table in `review_required_cities.md`. Large cantts (Walton, Rawalpindi, Lahore) are material population. |",
        "| **Decision required** | Per-cantonment or policy-level treatment for all 55. |",
        "",
        "## D-CITY-SPLIT-LOCALITY",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | Explicit coalesce rules for some Part-of metros; Sukkur Parts still open; other Part-of without rule → REVIEW. |",
        "| **Options** | (1) Extend coalesce list (Sukkur, …). (2) Leave unresolved forever (blocks completeness). (3) Keep as separate cities (usually wrong for passenger UX). |",
        "| **Evidence** | Sukkur New Sukkur + Sukkur City taluka parts (~564k combined). |",
        "| **Decision required** | Approve coalesce rules for remaining Part-of municipal/metro splits. |",
        "",
        "## D-CITY-DUPLICATE-ID",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | Collisions: `sahiwal`, `khanpur`, `khangarh`, `karampur`, plus `hyderabad` TC (Punjab) vs Sindh metro. Demoted from catalog. |",
        "| **Options** | (1) District-qualified IDs (product-defined scheme). (2) Keep one / exclude other. (3) Manual unique slug table. **Forbidden:** silent arbitrary suffixes in transform. |",
        "| **Evidence** | Duplicate analysis in `review_required_cities.md` — all listed collisions are **different places**. |",
        "| **Decision required** | Naming rule + exact IDs for each collision pair/group. |",
        "",
        "## D-CITY-NAMING",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | Candidate `displayName` = cleaned Title Case; PBS source strings retained in provenance. |",
        "| **Options** | (1) Keep Title Case English. (2) Official PBS casing. (3) Add Urdu later. |",
        "| **Evidence** | DISPLAY_NAME_PROPOSAL column in review table (proposals only). |",
        "| **Decision required** | Approve displayName policy; confirm multi-word slug shaping (spaces→hyphens then `normalizeCitySlug`). |",
        "",
        "## D-CITY-ACTIVATION",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | Candidate file uses `active: true` as **placeholder**. Not an ops activation. |",
        "| **Options** | (1) All approved cities active. (2) Staged activation. (3) Serviceability-driven. (4) Phased by province/metro. |",
        "| **Evidence** | Architecture: geographic existence ≠ active; Pakistan-wide = coverage capability. |",
        "| **Decision required** | Activation policy before Firestore population. |",
        "",
        "## D-CITY-POPULATION-FLOOR",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | **No floor applied.** Distribution reported in review doc. |",
        "| **Options** | (1) Keep all sizes. (2) Apply floor (e.g. ≥10k / ≥25k / ≥50k) — product only. |",
        "| **Evidence** | Catalog bands include small TCs; floor would shrink Pakistan-wide membership. |",
        "| **Decision required** | Whether any floor exists; if yes, exact threshold. Default recommendation from Slice 2A/2B: **no floor unless product opts in**. |",
        "",
        "## D-CITY-LICENSING",
        "",
        "| | |",
        "| -- | -- |",
        "| **Current state** | **LICENSE_REVIEW_REQUIRED**. PBS Tier-1 open/reuse language is not Ora legal clearance. |",
        "| **Options** | (1) Counsel clears derived Firestore catalog + API exposure with attribution. (2) Block until cleared. |",
        "| **Evidence** | Slice 2 research + PBS dissemination materials. |",
        "| **Decision required** | Written legal approval before any Firestore seed / public catalog API. |",
        "",
        "---",
        "",
        "## Sign-off checklist (product / ops / legal)",
        "",
        "- [ ] D-CITY-GEOGRAPHIC-UNIT",
        "- [ ] D-CITY-METRO-COALESCE (incl. Sukkur)",
        "- [ ] D-CITY-CANTONMENT (all 55)",
        "- [ ] D-CITY-SPLIT-LOCALITY",
        "- [ ] D-CITY-DUPLICATE-ID (all collisions)",
        "- [ ] D-CITY-NAMING",
        "- [ ] D-CITY-ACTIVATION",
        "- [ ] D-CITY-POPULATION-FLOOR",
        "- [ ] D-CITY-LICENSING",
        "",
        "Until checked: **do not populate Firestore**. **do not proceed to Slice 2 population.**",
        "",
    ]
    path = ROOT / "city_catalog_decisions.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", path)


if __name__ == "__main__":
    write_review_required()
    write_decisions()
