# City Catalog — Product / Ops Decision Matrix (Slice 2B)

**Status:** Decisions **REQUIRED** — nothing below is silently approved.

**Candidate dataset remains:** CANDIDATE — NOT APPROVED — NOT SEEDED

Related: [`review_required_cities.md`](review_required_cities.md), [`candidate_city_review.md`](candidate_city_review.md)

---

## D-CITY-GEOGRAPHIC-UNIT

| | |
| -- | -- |
| **Current state** | PBS Census 2023 **urban localities** (657 rows) transformed into passenger-facing **service cities** (555 candidates + 67 reviews). |
| **Options** | (1) Urban localities coalesced to service cities (current direction). (2) Districts (~160). (3) All raw PBS rows 1:1. (4) Major cities only. |
| **Evidence** | Architecture freeze: Redis shard = passenger city id; villages/PPL too fine; districts too coarse for mega-cities. |
| **Decision required** | Confirm service-city unit = coalesced urban locality (not district, not every census row). |

## D-CITY-METRO-COALESCE

| | |
| -- | -- |
| **Current state** | HIGH-confidence coalesces in candidate catalog: **Lahore** (5), **Karachi** (28), **Hyderabad** (2), **Quetta** (4). Sukkur MC parts still REVIEW_REQUIRED. |
| **Options** | (1) Approve current four. (2) Add Sukkur coalesce. (3) Split any metro back. (4) Different Karachi model (e.g. keep districts). |
| **Evidence** | See metro section in `review_required_cities.md` — Part-of rows are census partitions of one corporation/metro. |
| **Decision required** | Formal approve/reject of Lahore/Karachi/Hyderabad/Quetta; decide Sukkur. |

## D-CITY-CANTONMENT

| | |
| -- | -- |
| **Current state** | 55 cantonment rows are REVIEW_REQUIRED; not in candidate catalog; suggested parents only. |
| **Options** | (1) `MERGE_WITH_PARENT` into metro/city. (2) `EXCLUDE_FROM_CITY_CATALOG`. (3) Separate Ora cities (not recommended by architecture). (4) Mixed by cluster (e.g. merge Lahore/Karachi cantts; review Wah/Murree). |
| **Evidence** | Full cantonment table in `review_required_cities.md`. Large cantts (Walton, Rawalpindi, Lahore) are material population. |
| **Decision required** | Per-cantonment or policy-level treatment for all 55. |

## D-CITY-SPLIT-LOCALITY

| | |
| -- | -- |
| **Current state** | Explicit coalesce rules for some Part-of metros; Sukkur Parts still open; other Part-of without rule → REVIEW. |
| **Options** | (1) Extend coalesce list (Sukkur, …). (2) Leave unresolved forever (blocks completeness). (3) Keep as separate cities (usually wrong for passenger UX). |
| **Evidence** | Sukkur New Sukkur + Sukkur City taluka parts (~564k combined). |
| **Decision required** | Approve coalesce rules for remaining Part-of municipal/metro splits. |

## D-CITY-DUPLICATE-ID

| | |
| -- | -- |
| **Current state** | Collisions: `sahiwal`, `khanpur`, `khangarh`, `karampur`, plus `hyderabad` TC (Punjab) vs Sindh metro. Demoted from catalog. |
| **Options** | (1) District-qualified IDs (product-defined scheme). (2) Keep one / exclude other. (3) Manual unique slug table. **Forbidden:** silent arbitrary suffixes in transform. |
| **Evidence** | Duplicate analysis in `review_required_cities.md` — all listed collisions are **different places**. |
| **Decision required** | Naming rule + exact IDs for each collision pair/group. |

## D-CITY-NAMING

| | |
| -- | -- |
| **Current state** | Candidate `displayName` = cleaned Title Case; PBS source strings retained in provenance. |
| **Options** | (1) Keep Title Case English. (2) Official PBS casing. (3) Add Urdu later. |
| **Evidence** | DISPLAY_NAME_PROPOSAL column in review table (proposals only). |
| **Decision required** | Approve displayName policy; confirm multi-word slug shaping (spaces→hyphens then `normalizeCitySlug`). |

## D-CITY-ACTIVATION

| | |
| -- | -- |
| **Current state** | Candidate file uses `active: true` as **placeholder**. Not an ops activation. |
| **Options** | (1) All approved cities active. (2) Staged activation. (3) Serviceability-driven. (4) Phased by province/metro. |
| **Evidence** | Architecture: geographic existence ≠ active; Pakistan-wide = coverage capability. |
| **Decision required** | Activation policy before Firestore population. |

## D-CITY-POPULATION-FLOOR

| | |
| -- | -- |
| **Current state** | **No floor applied.** Distribution reported in review doc. |
| **Options** | (1) Keep all sizes. (2) Apply floor (e.g. ≥10k / ≥25k / ≥50k) — product only. |
| **Evidence** | Catalog bands include small TCs; floor would shrink Pakistan-wide membership. |
| **Decision required** | Whether any floor exists; if yes, exact threshold. Default recommendation from Slice 2A/2B: **no floor unless product opts in**. |

## D-CITY-LICENSING

| | |
| -- | -- |
| **Current state** | **LICENSE_REVIEW_REQUIRED**. PBS Tier-1 open/reuse language is not Ora legal clearance. |
| **Options** | (1) Counsel clears derived Firestore catalog + API exposure with attribution. (2) Block until cleared. |
| **Evidence** | Slice 2 research + PBS dissemination materials. |
| **Decision required** | Written legal approval before any Firestore seed / public catalog API. |

---

## Sign-off checklist (product / ops / legal)

- [ ] D-CITY-GEOGRAPHIC-UNIT
- [ ] D-CITY-METRO-COALESCE (incl. Sukkur)
- [ ] D-CITY-CANTONMENT (all 55)
- [ ] D-CITY-SPLIT-LOCALITY
- [ ] D-CITY-DUPLICATE-ID (all collisions)
- [ ] D-CITY-NAMING
- [ ] D-CITY-ACTIVATION
- [ ] D-CITY-POPULATION-FLOOR
- [ ] D-CITY-LICENSING

Until checked: **do not populate Firestore**. **do not proceed to Slice 2 population.**

