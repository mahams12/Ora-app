# Final Decision Matrix — Slice 2D

**Status:** Product decisions **APPLIED** to dataset artifacts.  
**Licensing:** `PRODUCTION_IMPORT_STATUS = BLOCKED_PENDING_LICENSING_REVIEW`  
**Firestore:** NOT TOUCHED  
**Generated:** 2026-09-21T10:03:20.140Z

| Decision | Resolution | Status |
| -------- | ---------- | ------ |
| Geographic unit | Operational passenger service city (not raw PBS row / district / tehsil / village) | **APPROVED / APPLIED** |
| Pakistan-wide | Full service-city catalog; not launch-subset | **APPROVED / APPLIED** |
| Lahore coalesce | → `lahore` / Lahore | **APPROVED / APPLIED** |
| Karachi coalesce | → `karachi` / Karachi | **APPROVED / APPLIED** |
| Hyderabad (Sindh) coalesce | → `hyderabad` / Hyderabad | **APPROVED / APPLIED** |
| Quetta coalesce | → `quetta` / Quetta | **APPROVED / APPLIED** |
| Sukkur coalesce | → `sukkur` / Sukkur | **APPROVED / APPLIED** |
| Cantonment policy | Merge embedded cantts into parent; leave ambiguous as REVIEW_REQUIRED | **APPROVED / APPLIED** |
| Peshawar University TC | Not standalone; covered by `peshawar` | **APPROVED / APPLIED** |
| Duplicate-name policy | Distinct places kept; district-qualified slugs where needed | **APPROVED / APPLIED** |
| Naming policy | Passenger-facing English; audit fixes for 18-Hazari, 46-Adda, Kingri | **APPROVED / APPLIED** |
| Population floor | **None** | **APPROVED / APPLIED** |
| Activation | Catalog records `active: true` as approved membership; not a Firestore activation | **APPROVED / APPLIED** |
| Licensing gate | Production import blocked pending legal review | **BLOCKED** |

## Counts

- Final catalog cities: **565**
- PBS source rows: **657**
- Remaining REVIEW_REQUIRED: **9**
- Excluded (covered): **1**

## Remaining REVIEW_REQUIRED

These are **intentionally unresolved** under the frozen “do not guess ambiguous cantonments” rule:

- WAH CANTONMENT (RAWALPINDI DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- MALIR CANTONMENT (Part of Airport Sub-Division) (MALIR DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- MALIR CANTONMENT (Part of Gulzar-e-Hijri Sub-Division) (KARACHI EAST DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- KORANGI CREEK CANTONMENT (Part of Korangi Sub-Division) (KORANGI DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- MALIR CANTONMENT (Part of Murad Memon Sub-Division) (MALIR DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- KORANGI CREEK CANTONMENT (Part of Ibrahim Hydri Sub-Division) (MALIR DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- ORMARA CANTONMENT (GWADAR DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- CHERAT CANTONMENT (NOWSHERA DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed
- MURREE GALLIES CANTONMENT (ABBOTTABAD DISTRICT) — Slice2D: ambiguous cantonment listed in product freeze / Slice2C REQUIRE_PRODUCT_DECISION — not guessed

## Compatibility

`id` remains compatible with `rides.city`, `drivers.homeCity`, and Redis `geo:drivers:{id}` via `normalizeCitySlug` / slug shape rules.
