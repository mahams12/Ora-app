# Pakistan city dataset (Slice 2A)

**CANDIDATE — NOT APPROVED — NOT SEEDED**

PBS Census 2023 Table 2 → candidate Ora service-city pack for product/ops review.

| Path | Purpose |
| ---- | ------- |
| `source/` | Unmodified official PBS downloads + manifest/checksums |
| `candidate/candidate_city_catalog.json` | Candidate import-shaped list (`id`, `displayName`, `active`) — **not for Firestore yet** |
| `candidate/candidate_city_provenance.json` | Audit trail — **never import** |
| `candidate/candidate_city_review.md` | Human review package (Slice 2A) |
| `candidate/review_required_cities.md` | Slice 2B — all 67 REVIEW_REQUIRED rows + cantonment/dup/metro analysis |
| `candidate/city_catalog_decisions.md` | Slice 2B — product/ops decision matrix (D-CITY-*) |
| `candidate/candidate_city_stats.json` | Counts / bands |
| `prepare_candidate_dataset.py` | Deterministic transform (re-runnable) |
| `generate_slice2b_review.py` | Regenerates Slice 2B review markdown from provenance |

**Licensing:** `LICENSE_REVIEW_REQUIRED`

**Firestore / production APIs:** not touched by this slice.

Regenerate:

```bash
python3 prepare_candidate_dataset.py
```

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

## Slice 2D — Approved service-city catalog

**Status:** GREEN dataset under frozen product decisions.  
**Licensing:** BLOCKED_PENDING_LICENSING_REVIEW  
**Firestore:** NOT TOUCHED

| File | Purpose |
| ---- | ------- |
| `final/approved_city_catalog.json` | Final approved catalog |
| `final/approved_city_provenance.json` | Provenance |
| `final/final_decision_matrix.md` | Decision freeze record |
| `final/validation_report.json` | Validation |
| `generate_slice2d_approved_catalog.py` | Deterministic builder |

Regenerate:

```bash
python3 generate_slice2d_approved_catalog.py
```
