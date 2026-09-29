# Licensing Gate (Slice 2C)

**Generated:** 2026-09-21T09:40:09.154367+00:00

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

### Slice 2E confirmation

Slice 2E inspected this gate and implemented import **preparation only** (validate + dry-run + refuse writes).  
Authoritative code constant: `PRODUCTION_IMPORT_STATUS` in `backend/auth-service/src/cities/city_catalog_import.ts` remains `BLOCKED_PENDING_LICENSING_REVIEW`.  
Catalog `_meta.productionImportAllowed` remains `false`.

## Decision mapping

- Decision ID: **D-CITY-LICENSING**
- Status: **REVIEW_REQUIRED**
