# City Catalog Decision Matrix (Slice 2C)

**Data governance / decision-freeze.** Engineering proposals are **not** product policy.

**No decision is APPROVED** in this document — no authoritative product/ops sign-off artifact exists in the repository.

| Decision ID | Current candidate interpretation | Engineering proposal | Source evidence | Product/ops decision required | Status | Unresolved questions |
| ------------ | -------------------------------- | -------------------- | --------------- | ----------------------------- | ------ | -------------------- |
| D-CITY-GEOGRAPHIC-UNIT | PBS urban localities → passenger service cities (coalesce/direct/review) | Use coalesced urban service cities (not districts, not every raw PBS row, not villages) | PBS Table 2 = 657 urban localities; architecture requires Redis shard = passenger city | Confirm service-city unit definition | PROPOSED | Is 'service city' formally the product unit? Any locality types always excluded? |
| D-CITY-METRO-COALESCE | Lahore/Karachi/Hyderabad/Quetta coalesced in candidate; Sukkur still review | Approve L/K/H/Q coalesces; decide Sukkur separately | Part-of corporation rows; metro_coalesce_resolution.md | Formal approve/reject each metro coalesce | PROPOSED | Approve Lahore? Karachi? Hyderabad? Quetta? Sukkur? |
| D-CITY-CANTONMENT | 55 cantonments excluded from candidate catalog; suggested parents only | Merge clear embedded cantts into parent; keep ambiguous as product review | cantonment_resolution.md; PBS cantonment rows | Per-cantonment or policy-level treatment for all 55 | REVIEW_REQUIRED | Merge vs exclude vs separate city? Wah/Malir/Cherat/Murree Gallies/Ormara? |
| D-CITY-SPLIT-LOCALITY | Some Part-of coalesced; Sukkur Parts unresolved | Extend explicit coalesce rules only with product approval | Sukkur MC New Sukkur + Sukkur City parts | Approve remaining Part-of municipal/metro splits | REVIEW_REQUIRED | Coalesce Sukkur? Any other Part-of rules? |
| D-CITY-DUPLICATE-ID | sahiwal/khanpur/khangarh/karampur/hyderabad-TC collisions demoted | Distinct places need distinct IDs via product naming rule — no silent suffixes | duplicate_id_resolution.md | Approve deterministic disambiguation scheme + exact IDs | REVIEW_REQUIRED | What naming convention for same-name different-district cities? |
| D-CITY-NAMING | Title Case cleaned displayNames; PBS strings in provenance | Passenger-facing Title Case; spaces→hyphens then normalizeCitySlug for ids | naming_audit.md | Approve displayName + slug shaping policy | PROPOSED | Approve Title Case? Urdu later? Fix 18-hazari casing? |
| D-CITY-ACTIVATION | Candidate uses active:true as placeholder only | Do not treat placeholder as ops activation; choose staged vs all-on | Architecture: existence ≠ active | Activation policy before Firestore population | REVIEW_REQUIRED | All-on vs staged vs serviceability-driven? |
| D-CITY-POPULATION-FLOOR | No floor applied; full size distribution retained | No population floor unless product opts in | Population bands in review_required_cities.md | Confirm no floor OR set exact threshold | PROPOSED | Any minimum population for catalog membership? |
| D-CITY-LICENSING | LICENSE_REVIEW_REQUIRED; no counsel sign-off in repo | Block production import until legal clearance | licensing_gate.md; PBS dissemination materials | Written legal approval for derived catalog + API | REVIEW_REQUIRED | Is commercial/API/Firestore derived use permitted with attribution? |

## Status legend

- `PROPOSED` — engineering recommendation only
- `APPROVED` — requires authoritative product/ops artifact (**none present**)
- `REJECTED` — requires authoritative rejection (**none present**)
- `REVIEW_REQUIRED` — cannot proceed to production import without human decision

Generated: 2026-09-21T09:40:09.151182+00:00

