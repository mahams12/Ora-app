# Final city catalog artifacts (Slice 2D + 2E gate)

**APPROVED dataset under frozen product decisions.**  
**NOT seeded to Firestore.**  
**Licensing:** `PRODUCTION_IMPORT_STATUS = BLOCKED_PENDING_LICENSING_REVIEW`

| File | Purpose |
| ---- | ------- |
| `approved_city_catalog.json` | Runtime-shaped catalog (`id`, `displayName`, `countryCode`, `active`, timestamps) |
| `approved_city_provenance.json` | PBS row → city traceability, merges, exclusions, unresolved |
| `final_decision_matrix.md` | Frozen decisions as applied |
| `validation_report.json` | Deterministic validation (Slice 2D) |
| `slice2e_import_dry_run_report.json` | Slice 2E dry-run — `FIRESTORE_WRITE_STATUS=BLOCKED` |
| `slice2e_import_manifest.json` | Deterministic Admin-SDK import plan (not executed) |

## Slice 2E status

```text
SLICE 2E — YELLOW / IMPORT BLOCKED
FIRESTORE_WRITE_STATUS = BLOCKED
REASON = LICENSING_GATE
```

Import prep lives in `backend/auth-service/src/cities/city_catalog_import.ts`.  
Dry-run: `npm --prefix backend/auth-service run test:city-catalog-import-dry-run`.  
Do **not** run live Firestore import until licensing is explicitly cleared.

Prior Slice 2C `decision_pending_city_catalog.json` is superseded for approval status but retained for history.

Generated: 2026-09-21T10:03:20.140Z (2D); 2E dry-run artifacts regenerated on demand.
