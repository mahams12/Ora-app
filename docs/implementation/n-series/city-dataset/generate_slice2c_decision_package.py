#!/usr/bin/env python3
"""
Slice 2C — Decision-freeze / governance package generator.

Does NOT approve product policy.
Does NOT write Firestore.
Does NOT overwrite candidate_city_catalog.json.
"""

from __future__ import annotations

import csv
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CAND = ROOT / "candidate"
FINAL = ROOT / "final"
FINAL.mkdir(parents=True, exist_ok=True)

PROV = json.load(open(CAND / "candidate_city_provenance.json"))["records"]
CATALOG = json.load(open(CAND / "candidate_city_catalog.json"))["cities"]
STATS = json.load(open(CAND / "candidate_city_stats.json"))
REVIEWS = [e for e in PROV if e["decision"] == "REVIEW_REQUIRED"]
COALESCED = [e for e in PROV if e["decision"] == "COALESCED"]
DIRECTS = [e for e in PROV if e["decision"] == "DIRECT"]

PART = re.compile(r"\(\s*Part of\s+(.+?)\s*\)", re.I)
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def normalize_city_slug(raw: str | None) -> str | None:
    if not isinstance(raw, str):
        return None
    s = raw.strip().lower()
    return s if s else None


def categorize(e: dict) -> str:
    name = e["sourceNames"][0].upper()
    reason = e.get("reason", "")
    lt = e.get("legalType")
    if lt == "CANTONMENT" or "CANTONMENT" in name:
        return "CANTONMENT"
    if e.get("duplicateCanonicalId") or "DUPLICATE_CANONICAL_ID" in reason:
        return "DUPLICATE_ID"
    if "UNIVERSITY" in name:
        return "UNIVERSITY_TC"
    if "Part of" in e["sourceNames"][0] or "Split locality" in reason:
        if "MUNICIPAL CORPORATION" in name or "METROPOLITAN" in name:
            return "METRO_SPLIT"
        return "PART_OF"
    return "OTHER"


def engineering_proposal_cantonment(e: dict) -> tuple[str, str | None, str, str]:
    """
    Returns: proposedAction, proposedFinalCityId, proposedFinalDisplayName, evidence
    """
    parent = e.get("suggestedParentId")
    name = e["sourceNames"][0]
    nu = name.upper()

    if parent is None or "CHERAT" in nu:
        return (
            "REQUIRE_PRODUCT_DECISION",
            None,
            None,
            "No clear passenger-facing parent / specialty military site (Cherat or unset)",
        )
    if "MURREE GALLIES" in nu:
        return (
            "REQUIRE_PRODUCT_DECISION",
            None,
            None,
            "Murree vs Abbottabad parent ambiguity in source context",
        )
    if "WAH CANTONMENT" in nu:
        return (
            "REQUIRE_PRODUCT_DECISION",
            None,
            None,
            "Wah often treated as distinct town vs Rawalpindi suburb",
        )
    if parent == "ormara":
        return (
            "REQUIRE_PRODUCT_DECISION",
            None,
            None,
            "Ormara Cantonment vs Ormara town / Gwadar relationship unresolved",
        )
    if parent in ("malir", "keamari", "korangi") or (
        parent and parent.startswith("karachi") and parent != "karachi"
    ):
        return (
            "REQUIRE_PRODUCT_DECISION",
            None,
            None,
            f"Suggested parent `{parent}` is admin/district-shaped; passenger parent may be `karachi` but not product-approved",
        )

    # Engineering proposal only — not approved
    display = {
        "lahore": "Lahore",
        "karachi": "Karachi",
        "rawalpindi": "Rawalpindi",
        "islamabad": "Islamabad",
        "peshawar": "Peshawar",
        "multan": "Multan",
        "hyderabad": "Hyderabad",
        "quetta": "Quetta",
        "sialkot": "Sialkot",
        "gujranwala": "Gujranwala",
        "sargodha": "Sargodha",
        "bahawalpur": "Bahawalpur",
        "abbottabad": "Abbottabad",
        "mardan": "Mardan",
        "nowshera": "Nowshera",
        "kohat": "Kohat",
        "bannu": "Bannu",
        "taxila": "Taxila",
        "loralai": "Loralai",
        "zhob": "Zhob",
        "gwadar": "Gwadar",
        "dera-ismail-khan": "Dera Ismail Khan",
    }.get(parent, parent.replace("-", " ").title() if parent else None)

    return (
        "MERGE_WITH_PARENT",
        parent,
        display,
        f"Engineering proposal: embedded cantonment with suggested parent `{parent}` from district/name evidence — REQUIRES product approval (D-CITY-CANTONMENT)",
    )


def row_for_review(e: dict) -> dict:
    cat = categorize(e)
    name = e["sourceNames"][0]
    source_row = e["sourceRows"][0]
    district = e["districts"][0]
    current = "REVIEW_REQUIRED"
    cid = e.get("candidateId")
    display = e.get("displayName")

    if cat == "CANTONMENT":
        action, final_id, final_disp, evidence = engineering_proposal_cantonment(e)
        decision_id = "D-CITY-CANTONMENT"
    elif cat == "METRO_SPLIT":
        action = "REQUIRE_PRODUCT_DECISION"
        final_id = "sukkur"
        final_disp = "Sukkur"
        evidence = (
            "Sukkur Municipal Corporation Part-of taluka rows — same pattern as Hyderabad "
            "but Sukkur coalesce is NOT approved; engineering may propose COALESCE under D-CITY-METRO-COALESCE / D-CITY-SPLIT-LOCALITY"
        )
        decision_id = "D-CITY-SPLIT-LOCALITY"
        # Keep proposedAction as REQUIRE_PRODUCT_DECISION per stop rules
        action = "REQUIRE_PRODUCT_DECISION"
        final_id = None
        final_disp = None
    elif cat == "DUPLICATE_ID":
        action = "REQUIRE_PRODUCT_DECISION"
        final_id = None
        final_disp = None
        evidence = (
            f"Cross-district name collision on canonical id `{cid}`; entities are distinct — "
            "naming/ID policy not product-approved (D-CITY-DUPLICATE-ID)"
        )
        decision_id = "D-CITY-DUPLICATE-ID"
    elif cat == "UNIVERSITY_TC":
        action = "REQUIRE_PRODUCT_DECISION"
        final_id = None
        final_disp = None
        evidence = (
            "Peshawar University TC — institutional township; exclude vs absorb into peshawar "
            "is product policy (engineering lean: EXCLUDE) — not approved"
        )
        decision_id = "D-CITY-GEOGRAPHIC-UNIT"
    else:
        action = "REQUIRE_PRODUCT_DECISION"
        final_id = None
        final_disp = None
        evidence = e.get("reason", "Unresolved")
        decision_id = "D-CITY-SPLIT-LOCALITY"

    eng_proposal = {
        "CANTONMENT": "See cantonment_resolution.md — MERGE_WITH_PARENT proposed only where parent clear; else unresolved",
        "METRO_SPLIT": "Engineering lean: COALESCE to sukkur (unapproved)",
        "DUPLICATE_ID": "Engineering lean: keep both places with product-defined distinct IDs (no silent suffix)",
        "UNIVERSITY_TC": "Engineering lean: EXCLUDE_FROM_CITY_CATALOG",
        "PART_OF": "Unresolved Part-of",
        "OTHER": "Unresolved",
    }[cat]

    status = (
        "REQUIRE_LICENSING_REVIEW"
        if False
        else ("REVIEW_REQUIRED" if action == "REQUIRE_PRODUCT_DECISION" else "PROPOSED")
    )
    # For matrix status column use decision status vocabulary
    if action == "REQUIRE_PRODUCT_DECISION":
        status = "REVIEW_REQUIRED"
    elif action == "REQUIRE_LICENSING_REVIEW":
        status = "REVIEW_REQUIRED"
    else:
        status = "PROPOSED"  # engineering proposal only

    return {
        "sourceRow": source_row,
        "sourceName": name,
        "district": district,
        "provinceTerritory": e.get("provincesTerritories", [""])[0],
        "population2023": e.get("population2023"),
        "candidateCityId": cid or "",
        "category": cat,
        "currentCandidateAction": current,
        "engineeringProposal": eng_proposal,
        "proposedFinalCityId": final_id or "",
        "proposedFinalDisplayName": final_disp or "",
        "proposedAction": action,
        "decisionId": decision_id,
        "evidence": evidence,
        "status": status,
        "suggestedParentId": e.get("suggestedParentId") or "",
        "legalType": e.get("legalType") or "",
        "priorDecision": e.get("priorDecision") or "",
    }


def write_decision_matrix() -> None:
    rows = [
        (
            "D-CITY-GEOGRAPHIC-UNIT",
            "PBS urban localities → passenger service cities (coalesce/direct/review)",
            "Use coalesced urban service cities (not districts, not every raw PBS row, not villages)",
            "PBS Table 2 = 657 urban localities; architecture requires Redis shard = passenger city",
            "Confirm service-city unit definition",
            "PROPOSED",
            "Is 'service city' formally the product unit? Any locality types always excluded?",
        ),
        (
            "D-CITY-METRO-COALESCE",
            "Lahore/Karachi/Hyderabad/Quetta coalesced in candidate; Sukkur still review",
            "Approve L/K/H/Q coalesces; decide Sukkur separately",
            "Part-of corporation rows; metro_coalesce_resolution.md",
            "Formal approve/reject each metro coalesce",
            "PROPOSED",
            "Approve Lahore? Karachi? Hyderabad? Quetta? Sukkur?",
        ),
        (
            "D-CITY-CANTONMENT",
            "55 cantonments excluded from candidate catalog; suggested parents only",
            "Merge clear embedded cantts into parent; keep ambiguous as product review",
            "cantonment_resolution.md; PBS cantonment rows",
            "Per-cantonment or policy-level treatment for all 55",
            "REVIEW_REQUIRED",
            "Merge vs exclude vs separate city? Wah/Malir/Cherat/Murree Gallies/Ormara?",
        ),
        (
            "D-CITY-SPLIT-LOCALITY",
            "Some Part-of coalesced; Sukkur Parts unresolved",
            "Extend explicit coalesce rules only with product approval",
            "Sukkur MC New Sukkur + Sukkur City parts",
            "Approve remaining Part-of municipal/metro splits",
            "REVIEW_REQUIRED",
            "Coalesce Sukkur? Any other Part-of rules?",
        ),
        (
            "D-CITY-DUPLICATE-ID",
            "sahiwal/khanpur/khangarh/karampur/hyderabad-TC collisions demoted",
            "Distinct places need distinct IDs via product naming rule — no silent suffixes",
            "duplicate_id_resolution.md",
            "Approve deterministic disambiguation scheme + exact IDs",
            "REVIEW_REQUIRED",
            "What naming convention for same-name different-district cities?",
        ),
        (
            "D-CITY-NAMING",
            "Title Case cleaned displayNames; PBS strings in provenance",
            "Passenger-facing Title Case; spaces→hyphens then normalizeCitySlug for ids",
            "naming_audit.md",
            "Approve displayName + slug shaping policy",
            "PROPOSED",
            "Approve Title Case? Urdu later? Fix 18-hazari casing?",
        ),
        (
            "D-CITY-ACTIVATION",
            "Candidate uses active:true as placeholder only",
            "Do not treat placeholder as ops activation; choose staged vs all-on",
            "Architecture: existence ≠ active",
            "Activation policy before Firestore population",
            "REVIEW_REQUIRED",
            "All-on vs staged vs serviceability-driven?",
        ),
        (
            "D-CITY-POPULATION-FLOOR",
            "No floor applied; full size distribution retained",
            "No population floor unless product opts in",
            "Population bands in review_required_cities.md",
            "Confirm no floor OR set exact threshold",
            "PROPOSED",
            "Any minimum population for catalog membership?",
        ),
        (
            "D-CITY-LICENSING",
            "LICENSE_REVIEW_REQUIRED; no counsel sign-off in repo",
            "Block production import until legal clearance",
            "licensing_gate.md; PBS dissemination materials",
            "Written legal approval for derived catalog + API",
            "REVIEW_REQUIRED",
            "Is commercial/API/Firestore derived use permitted with attribution?",
        ),
    ]

    lines = [
        "# City Catalog Decision Matrix (Slice 2C)",
        "",
        "**Data governance / decision-freeze.** Engineering proposals are **not** product policy.",
        "",
        "**No decision is APPROVED** in this document — no authoritative product/ops sign-off artifact exists in the repository.",
        "",
        "| Decision ID | Current candidate interpretation | Engineering proposal | Source evidence | Product/ops decision required | Status | Unresolved questions |",
        "| ------------ | -------------------------------- | -------------------- | --------------- | ----------------------------- | ------ | -------------------- |",
    ]
    for r in rows:
        lines.append(
            "| "
            + " | ".join(str(x).replace("|", "\\|") for x in r)
            + " |"
        )
    lines += [
        "",
        "## Status legend",
        "",
        "- `PROPOSED` — engineering recommendation only",
        "- `APPROVED` — requires authoritative product/ops artifact (**none present**)",
        "- `REJECTED` — requires authoritative rejection (**none present**)",
        "- `REVIEW_REQUIRED` — cannot proceed to production import without human decision",
        "",
        f"Generated: {datetime.now(timezone.utc).isoformat()}",
        "",
    ]
    (ROOT / "decision_matrix.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote decision_matrix.md")


def write_review_csv() -> None:
    path = CAND / "review_resolution_matrix.csv"
    fieldnames = [
        "sourceRow",
        "sourceName",
        "district",
        "provinceTerritory",
        "population2023",
        "candidateCityId",
        "category",
        "currentCandidateAction",
        "engineeringProposal",
        "proposedFinalCityId",
        "proposedFinalDisplayName",
        "proposedAction",
        "decisionId",
        "evidence",
        "status",
        "suggestedParentId",
        "legalType",
        "priorDecision",
    ]
    rows = [row_for_review(e) for e in sorted(REVIEWS, key=lambda x: x["sourceRows"][0])]
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    actions = Counter(r["proposedAction"] for r in rows)
    print("wrote review_resolution_matrix.csv", len(rows), dict(actions))
    return rows


def write_cantonment_md(review_rows: list[dict]) -> None:
    cants = [r for r in review_rows if r["category"] == "CANTONMENT"]
    lines = [
        "# Cantonment Resolution (Slice 2C)",
        "",
        "**Status:** Engineering proposals only — **NOT PRODUCT APPROVED**",
        "",
        f"**Count:** {len(cants)}",
        "",
        "Policy constraint: do not auto-create `*-cantonment` Ora cities; do not silently merge without D-CITY-CANTONMENT approval.",
        "",
    ]
    for r in sorted(cants, key=lambda x: -int(x["population2023"] or 0)):
        lines += [
            f"## {r['sourceName']}",
            "",
            f"- **Source row:** {r['sourceRow']}",
            f"- **District:** {r['district']}",
            f"- **Province/territory (hint):** {r['provinceTerritory']}",
            f"- **Population 2023:** {int(r['population2023']):,}",
            f"- **Suggested parent (from Slice 2A):** `{r['suggestedParentId'] or '—'}`",
            f"- **Engineering proposedAction:** `{r['proposedAction']}`",
            f"- **Proposed final city id:** `{r['proposedFinalCityId'] or '—'}`",
            f"- **Proposed final displayName:** {r['proposedFinalDisplayName'] or '—'}",
            f"- **Evidence:** {r['evidence']}",
            f"- **Decision ID:** {r['decisionId']}",
            f"- **Status:** {r['status']}",
            "",
        ]
    # Ambiguous callouts
    lines += [
        "## Priority ambiguous cases",
        "",
        "| Cantonment | Why special |",
        "| ---------- | ----------- |",
        "| Wah Cantonment | Often treated as own town vs Rawalpindi |",
        "| Malir Cantonment (all parts) | Admin district parent vs Karachi passenger city |",
        "| Cherat Cantonment | Military hill station; no clear parent |",
        "| Murree Gallies Cantonment | Murree vs Abbottabad |",
        "| Ormara Cantonment | Ormara town vs Gwadar |",
        "",
    ]
    (CAND / "cantonment_resolution.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote cantonment_resolution.md", len(cants))


def write_duplicate_md() -> None:
    lines = [
        "# Duplicate Canonical ID Resolution (Slice 2C)",
        "",
        "**Status:** All collisions remain **REQUIRE_PRODUCT_DECISION** — no silent suffixes.",
        "",
        "`normalizeCitySlug` = trim + lowercase. Multi-word shaping: spaces→hyphens then normalize.",
        "",
    ]

    groups = {
        "sahiwal": "Sahiwal MetCorp (Sahiwal District) vs Sahiwal MC (Sargodha District)",
        "khanpur": "Khanpur MC (Rahim Yar Khan) vs Khanpur TC (Shikarpur)",
        "khangarh": "Khangarh TC (Ghotki, Sindh) vs Khangarh MC (Muzaffargarh, Punjab)",
        "karampur": "Karampur TC (Vehari, Punjab) vs Karampur TC (Kashmore, Sindh)",
        "hyderabad": "Coalesced Hyderabad Sindh metro (kept in catalog) vs Hyderabad TC (Bhakkar, Punjab)",
    }

    for cid, summary in groups.items():
        es = [
            e
            for e in REVIEWS
            if e.get("candidateId") == cid
            and (e.get("duplicateCanonicalId") or "DUPLICATE" in e.get("reason", ""))
        ]
        if cid == "hyderabad":
            es = [e for e in REVIEWS if e.get("candidateId") == "hyderabad"]
            coal = next(e for e in COALESCED if e["candidateId"] == "hyderabad")
        lines += [f"## `{cid}`", "", f"**Summary:** {summary}", ""]
        if cid == "hyderabad":
            lines += [
                "### Entity A — Sindh metro (currently in candidate catalog as COALESCED)",
                f"- Display: {coal['displayName']}",
                f"- Population sum: {coal['population2023']:,}",
                f"- Source rows: {coal['sourceRows']}",
                f"- Source names: {coal['sourceNames']}",
                "",
                "### Entity B — Punjab TC (REVIEW_REQUIRED / demoted)",
            ]
        lines += [
            "| PBS source | District | Pop 2023 | Prior | Display |",
            "| ---------- | -------- | -------- | ----- | ------- |",
        ]
        for e in es:
            lines.append(
                f"| {e['sourceNames'][0]} | {e['districts'][0]} | {e['population2023']:,} | {e.get('priorDecision')} | {e.get('displayName')} |"
            )
        lines += [
            "",
            "**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.",
            "",
            "**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.",
            "",
            "**Deterministic strategy (PROPOSAL ONLY — not approved):**",
            "1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.",
            "2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.",
            "3. **Forbidden:** transform-time silent arbitrary suffixes without policy.",
            "",
            "**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)",
            "",
        ]

    (CAND / "duplicate_id_resolution.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote duplicate_id_resolution.md")


def write_metro_md() -> None:
    lines = [
        "# Metropolitan Coalesce Resolution (Slice 2C)",
        "",
        "**Status:** Engineering evidence review — **NOT PRODUCT APPROVED**",
        "",
        "Sukkur must not be assumed merely because other metros coalesced.",
        "",
    ]

    # Existing coalesces
    for e in COALESCED:
        lines += [
            f"## {e['displayName']} (`{e['candidateId']}`) — currently COALESCED in candidate",
            "",
            f"- Source row count: {e['sourceRowCount']}",
            f"- Combined population 2023: **{e['population2023']:,}**",
            f"- Districts: {', '.join(e['districts'])}",
            f"- Canonical ID: `{e['candidateId']}`",
            f"- Rationale: {e['reason']}",
            "- Source localities:",
        ]
        for n, r in zip(e["sourceNames"], e["sourceRows"]):
            lines.append(f"  - row {r}: {n}")
        lines += [
            "- **Engineering assessment:** Source evidence consistent with one passenger-facing city.",
            "- **Product decision status:** `PROPOSED` / awaiting formal approval (D-CITY-METRO-COALESCE)",
            "",
        ]

    # Sukkur
    sukkur = [
        e
        for e in REVIEWS
        if "SUKKUR MUNICIPAL CORPORATION" in e["sourceNames"][0].upper()
    ]
    lines += [
        "## Sukkur — NOT coalesced (REVIEW_REQUIRED)",
        "",
        f"- Source rows: {len(sukkur)}",
    ]
    pop = 0
    for e in sukkur:
        pop += e["population2023"]
        lines.append(
            f"  - row {e['sourceRows'][0]}: {e['sourceNames'][0]} — pop {e['population2023']:,} — {e['districts'][0]}"
        )
    lines += [
        f"- Combined population if coalesced: **{pop:,}**",
        "- Proposed coalesced city (engineering lean only): `sukkur` / displayName `Sukkur`",
        "- Rationale (proposal): Same Part-of Municipal Corporation pattern as Hyderabad",
        "- **Must not auto-approve** from Lahore/Karachi/Hyderabad/Quetta precedent alone",
        "- **Product decision status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-METRO-COALESCE / D-CITY-SPLIT-LOCALITY)",
        "",
        "## Peshawar University TC",
        "",
    ]
    uni = [e for e in REVIEWS if "UNIVERSITY" in e["sourceNames"][0].upper()]
    for e in uni:
        lines += [
            f"- Source: {e['sourceNames'][0]}",
            f"- District: {e['districts'][0]}",
            f"- Population: {e['population2023']:,}",
            f"- Row: {e['sourceRows'][0]}",
            "- Classes: institutional township / TC",
            "- Engineering lean: `EXCLUDE` from passenger city selector",
            "- Alternatives: absorb into `peshawar` coverage without selector row",
            "- **Status:** `REQUIRE_PRODUCT_DECISION` — insufficient to classify as passenger-facing city without policy",
            "",
        ]

    (CAND / "metro_coalesce_resolution.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote metro_coalesce_resolution.md")


def write_naming_audit() -> None:
    lines = [
        "# Naming Audit (Slice 2C)",
        "",
        f"**Candidate cities audited:** {len(CATALOG)}",
        "",
        "**Rule:** Do not silently rename questionable entries into an approved catalog.",
        "",
        "## Safe deterministic cleanups (already applied in Slice 2A transform)",
        "",
        "- Trim whitespace",
        "- Strip legal suffixes (MC/TC/Metropolitan Corporation/…) for displayName construction",
        "- Title Case for passenger-facing labels",
        "- ID: spaces→hyphens then `normalizeCitySlug`",
        "",
        "## Findings",
        "",
    ]

    issues = []
    for c in CATALOG:
        d = c["displayName"]
        i = c["id"]
        if d != d.strip() or "  " in d:
            issues.append((i, d, "whitespace"))
        if "(" in d or ")" in d:
            issues.append((i, d, "parentheses in displayName"))
        if d.islower() or (d[:1].isdigit() and d == d.lower()):
            issues.append((i, d, "displayName not Title Case"))
        if "Corporation" in d or "Cantonment" in d:
            issues.append((i, d, "legal artifact in displayName"))
        if not SLUG_RE.match(i):
            issues.append((i, d, "invalid slug"))
        if normalize_city_slug(i) != i:
            issues.append((i, d, "id not normalizeCitySlug-stable"))

    lines.append(f"Issue count: **{len(issues)}**")
    lines.append("")
    lines.append("| id | displayName | issue | proposed rename (PROPOSAL) | status |")
    lines.append("| -- | ----------- | ----- | -------------------------- | ------ |")
    for i, d, issue in issues:
        prop = d
        if issue == "displayName not Title Case":
            prop = "-".join(p.capitalize() for p in d.split("-")) if "-" in d else d.title()
            # For 18-hazari → 18-Hazari
            parts = d.split("-")
            prop = "-".join(p[:1].upper() + p[1:] if p else p for p in parts)
        if issue == "parentheses in displayName":
            prop = re.sub(r"\s*\(.*?\)\s*", " ", d).strip()
            prop = " ".join(w.capitalize() for w in prop.split())
        lines.append(
            f"| `{i}` | {d} | {issue} | DISPLAY_NAME_PROPOSAL: `{prop}` | REQUIRE_PRODUCT_DECISION |"
        )
    if not issues:
        lines.append("| — | — | none | — | — |")

    # Duplicate display names
    by_disp = defaultdict(list)
    for c in CATALOG:
        by_disp[c["displayName"].lower()].append(c["id"])
    dups = {k: v for k, v in by_disp.items() if len(v) > 1}
    lines += ["", "## Duplicate displayNames in candidate catalog", ""]
    if not dups:
        lines.append("_None among the 555 candidate catalog cities._")
    else:
        for k, v in dups.items():
            lines.append(f"- `{k}` → ids {v}")

    lines += [
        "",
        "## Unresolved naming decisions",
        "",
        "- D-CITY-NAMING: Title Case vs official PBS casing vs bilingual Urdu",
        "- D-CITY-DUPLICATE-ID: district-qualified display names if IDs diverge",
        "- Cantonment display names if ever kept as cities (not recommended)",
        "- Metro display names already clean (`Lahore`, `Karachi`, …) — confirm",
        "",
    ]
    (CAND / "naming_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote naming_audit.md", "issues", len(issues))


def write_licensing_gate() -> None:
    text = f"""# Licensing Gate (Slice 2C)

**Generated:** {datetime.now(timezone.utc).isoformat()}

## Source

- **Organization:** Pakistan Bureau of Statistics (PBS)
- **Dataset:** 7th Population & Housing Census 2023 — Table 2 (urban localities)
- **Primary page:** https://www.pbs.gov.pk/result-excel/
- **Primary Excel:** https://www.pbs.gov.pk/wp-content/uploads/2020/07/table_2_national.xlsx
- **Local unmodified copies:** `docs/implementation/n-series/city-dataset/source/`

## Applicable reuse terms found (research — not legal advice)

PBS Data Dissemination materials describe Tier 1 aggregate statistics / publications as intended for open-government-style reuse with:

- copying / adaptation / redistribution
- commercial and non-commercial use
- attribution / source acknowledgement
- no implied official endorsement
- confidentiality and other laws respected

A 2026-oriented dissemination policy text also discusses a standard open government licence for Tier 1/2 products.

The PBS website also displays copyright / “All Rights Reserved” footers.

## Attribution requirements if documented

If Tier-1 open terms apply, attribution typically requires citing:

- producer (PBS)
- dataset title
- reference period (Census 2023)
- version / publication link
- access date

Exact attribution string **not frozen** without legal review.

## Commercial / API / derived-catalog use

| Question | Status |
| -------- | ------ |
| Commercial use of published aggregate tables | Claimed in dissemination policy language — **not counsel-cleared for Ora** |
| Store transformed city list in Firestore | **Unresolved** |
| Expose derived city names via Ora catalog API | **Unresolved** |
| Redis shard keys equal to derived ids | **Unresolved** (derived identifier use) |

## Unresolved legal questions

1. Does the published Table 2 Excel/PDF fall under the Tier-1 open licence as implemented, or only under general website copyright?
2. Is a **derived** passenger-facing city catalog (coalesced/renamed) permitted without additional PBS permission?
3. What attribution must appear in-app / in API docs / in repo?
4. Are share-alike or non-endorsement clauses binding for Ora’s commercial ride-hailing use?
5. Is production import allowed before written counsel memo?

## Production import status

```text
PRODUCTION_IMPORT_STATUS = BLOCKED_PENDING_LICENSING_REVIEW
```

**Do not claim legal clearance.**
**Do not populate Firestore until licensing is cleared AND product decisions are approved.**

## Decision mapping

- Decision ID: **D-CITY-LICENSING**
- Status: **REVIEW_REQUIRED**
"""
    (ROOT / "licensing_gate.md").write_text(text, encoding="utf-8")
    print("wrote licensing_gate.md")


def write_final_pending(review_rows: list[dict]) -> None:
    """decision_pending catalog = deterministic 555 + countryCode; unresolved listed separately."""
    cities = []
    for c in sorted(CATALOG, key=lambda x: x["id"]):
        cities.append(
            {
                "id": c["id"],
                "displayName": c["displayName"],
                "countryCode": "PK",
                "active": True,
            }
        )

    unresolved = []
    for r in review_rows:
        unresolved.append(
            {
                "sourceRow": r["sourceRow"],
                "sourceName": r["sourceName"],
                "district": r["district"],
                "category": r["category"],
                "proposedAction": r["proposedAction"],
                "decisionId": r["decisionId"],
                "status": r["status"],
                "evidence": r["evidence"],
            }
        )

    doc = {
        "_meta": {
            "status": "DECISION_PENDING — NOT APPROVED — NOT SEEDED",
            "warning": (
                "This is the best deterministic candidate from Slice 2A plus countryCode. "
                "It is NOT an approved production catalog. Unresolved PBS rows are listed "
                "under unresolvedRecords and must not be silently dropped."
            ),
            "licensing": "BLOCKED_PENDING_LICENSING_REVIEW",
            "productDecisionsApproved": False,
            "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "source": STATS.get("source"),
            "counts": {
                "deterministicCandidateCities": len(cities),
                "unresolvedReviewRecords": len(unresolved),
                "pbsSourceLocalityRows": STATS.get("rawPbsLocalityRows"),
            },
        },
        "cities": cities,
        "unresolvedRecords": unresolved,
    }
    path = FINAL / "decision_pending_city_catalog.json"
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote", path, "cities", len(cities), "unresolved", len(unresolved))

    # Explicitly do NOT write approved_city_catalog.json
    approved = FINAL / "approved_city_catalog.json"
    if approved.exists():
        approved.unlink()
    note = FINAL / "README.md"
    note.write_text(
        """# Final package (Slice 2C)

**No approved catalog exists.**

- `decision_pending_city_catalog.json` — deterministic candidate + explicit unresolved records
- `validation_report.json` — machine-readable validation

`approved_city_catalog.json` is **intentionally absent** until product/ops + licensing authorize it.
""",
        encoding="utf-8",
    )


def write_validation(review_rows: list[dict]) -> None:
    # Account for every PBS source row
    # Provenance covers: COALESCED (multi rows), DIRECT, REVIEW_REQUIRED
    accounted_rows: set[int] = set()
    for e in PROV:
        for r in e["sourceRows"]:
            accounted_rows.add(r)

    # Raw count from stats
    raw_n = STATS["rawPbsLocalityRows"]

    cities = [
        {
            "id": c["id"],
            "displayName": c["displayName"],
            "countryCode": "PK",
            "active": True,
        }
        for c in CATALOG
    ]

    ids = [c["id"] for c in cities]
    id_set = set(ids)

    errors = []
    warnings = []

    if len(ids) != len(id_set):
        errors.append("duplicate ids in deterministic candidate")
    for c in cities:
        if normalize_city_slug(c["id"]) != c["id"]:
            errors.append(f"id not normalize-stable: {c['id']}")
        if not SLUG_RE.match(c["id"]):
            errors.append(f"id not slug-shaped: {c['id']}")
        if c["countryCode"] != "PK":
            errors.append(f"bad countryCode: {c['id']}")
        if not c["displayName"] or not str(c["displayName"]).strip():
            errors.append(f"empty displayName: {c['id']}")

    # Every catalog city has provenance COALESCED or DIRECT
    prov_ids = {
        e["candidateId"]
        for e in PROV
        if e["decision"] in ("COALESCED", "DIRECT") and e.get("candidateId")
    }
    missing_prov = sorted(id_set - prov_ids)
    if missing_prov:
        errors.append(f"catalog ids missing provenance: {missing_prov[:10]}")

    # Unresolved not silently in catalog with colliding unresolved ids
    for r in review_rows:
        if r["category"] == "DUPLICATE_ID" and r["candidateCityId"] in id_set:
            # hyderabad metro is in catalog while TC review exists — OK if TC not in catalog
            if r["candidateCityId"] == "hyderabad" and "HYDERABAD TC" in r["sourceName"]:
                warnings.append(
                    "hyderabad Sindh metro remains in candidate; Punjab Hyderabad TC unresolved — intentional pending product ID policy"
                )
            elif r["priorDecision"] == "DIRECT":
                # demoted directs should not remain in catalog
                # check: sahiwal etc should NOT be in catalog
                if r["candidateCityId"] in ("sahiwal", "khanpur", "khangarh", "karampur"):
                    if r["candidateCityId"] in id_set:
                        errors.append(
                            f"demoted duplicate id still in catalog: {r['candidateCityId']}"
                        )

    # For demoted duplicates — both entities should be unresolved (not in catalog) EXCEPT hyderabad metro kept
    for cid in ("sahiwal", "khanpur", "khangarh", "karampur"):
        if cid in id_set:
            errors.append(f"duplicate-demoted id still present in catalog: {cid}")

    # Row accounting: provenance source rows should equal raw locality count
    # Note: coalesced groups store multiple rows in one entry
    if len(accounted_rows) != raw_n:
        warnings.append(
            f"accounted distinct source rows {len(accounted_rows)} vs raw {raw_n}"
        )

    # Classification of each accounted row
    row_disposition = {}
    for e in PROV:
        disp = {
            "COALESCED": "merged",
            "DIRECT": "retained",
            "REVIEW_REQUIRED": "unresolved",
        }[e["decision"]]
        for r in e["sourceRows"]:
            row_disposition[r] = {
                "disposition": disp,
                "decision": e["decision"],
                "candidateId": e.get("candidateId"),
                "sourceName": e["sourceNames"][0] if len(e["sourceNames"]) == 1 else e["sourceNames"],
            }

    # No invented cities: every catalog id from provenance
    invented = sorted(id_set - prov_ids)
    if invented:
        errors.append(f"invented cities: {invented}")

    report = {
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "slice": "2C",
        "overall": "FAIL" if errors else "PASS_WITH_PENDING_DECISIONS",
        "productionImportAllowed": False,
        "licensing": "BLOCKED_PENDING_LICENSING_REVIEW",
        "productDecisionsApproved": False,
        "checks": {
            "deterministicCandidateCount": len(cities),
            "idsUnique": len(ids) == len(id_set),
            "idsNormalizeStable": not any(
                normalize_city_slug(c["id"]) != c["id"] for c in cities
            ),
            "idsSlugShaped": not any(not SLUG_RE.match(c["id"]) for c in cities),
            "countryCodeAllPK": all(c["countryCode"] == "PK" for c in cities),
            "displayNamesNonEmpty": all(bool(str(c["displayName"]).strip()) for c in cities),
            "everyCatalogCityHasProvenance": not missing_prov,
            "noSilentDropOfReviewRecords": len(review_rows) == 67,
            "pbsSourceRowsAccountedDistinct": len(accounted_rows),
            "pbsSourceRowsExpected": raw_n,
            "unresolvedReviewCount": len(review_rows),
            "noInventedCities": not invented,
            "duplicateDemotedIdsAbsentFromCatalog": all(
                cid not in id_set
                for cid in ("sahiwal", "khanpur", "khangarh", "karampur")
            ),
        },
        "errors": errors,
        "warnings": warnings,
        "dispositionCounts": dict(Counter(v["disposition"] for v in row_disposition.values())),
        "reviewProposedActionCounts": dict(
            Counter(r["proposedAction"] for r in review_rows)
        ),
    }
    path = FINAL / "validation_report.json"
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote validation_report.json", report["overall"], "errors", errors)


def update_readme() -> None:
    readme = ROOT / "README.md"
    extra = """
## Slice 2C — Decision freeze

| Path | Purpose |
| ---- | ------- |
| `decision_matrix.md` | Nine D-CITY decisions — all PROPOSED / REVIEW_REQUIRED |
| `licensing_gate.md` | `PRODUCTION_IMPORT_STATUS = BLOCKED_PENDING_LICENSING_REVIEW` |
| `candidate/review_resolution_matrix.csv` | All 67 review rows |
| `candidate/cantonment_resolution.md` | Per-cantonment sections |
| `candidate/duplicate_id_resolution.md` | Duplicate ID groups |
| `candidate/metro_coalesce_resolution.md` | Metro + Sukkur + University TC |
| `candidate/naming_audit.md` | Naming findings |
| `final/decision_pending_city_catalog.json` | Deterministic candidate + unresolved list |
| `final/validation_report.json` | Validation |

**No `approved_city_catalog.json`.** Do not seed Firestore.
"""
    text = readme.read_text(encoding="utf-8")
    if "Slice 2C" not in text:
        readme.write_text(text.rstrip() + "\n" + extra, encoding="utf-8")


def main() -> None:
    write_decision_matrix()
    review_rows = write_review_csv()
    write_cantonment_md(review_rows)
    write_duplicate_md()
    write_metro_md()
    write_naming_audit()
    write_licensing_gate()
    write_final_pending(review_rows)
    write_validation(review_rows)
    update_readme()

    # Sanity
    assert len(review_rows) == 67
    assert not (FINAL / "approved_city_catalog.json").exists()
    print("Slice 2C artifacts complete — YELLOW expected")


if __name__ == "__main__":
    main()
