# Naming Audit (Slice 2C)

**Candidate cities audited:** 555

**Rule:** Do not silently rename questionable entries into an approved catalog.

## Safe deterministic cleanups (already applied in Slice 2A transform)

- Trim whitespace
- Strip legal suffixes (MC/TC/Metropolitan Corporation/…) for displayName construction
- Title Case for passenger-facing labels
- ID: spaces→hyphens then `normalizeCitySlug`

## Findings

Issue count: **3**

| id | displayName | issue | proposed rename (PROPOSAL) | status |
| -- | ----------- | ----- | -------------------------- | ------ |
| `18-hazari` | 18-hazari | displayName not Title Case | DISPLAY_NAME_PROPOSAL: `18-Hazari` | REQUIRE_PRODUCT_DECISION |
| `46-adda` | 46-adda | displayName not Title Case | DISPLAY_NAME_PROPOSAL: `46-Adda` | REQUIRE_PRODUCT_DECISION |
| `kingri-pirjo-goth` | Kingri (pirjo Goth) | parentheses in displayName | DISPLAY_NAME_PROPOSAL: `Kingri` | REQUIRE_PRODUCT_DECISION |

## Duplicate displayNames in candidate catalog

_None among the 555 candidate catalog cities._

## Unresolved naming decisions

- D-CITY-NAMING: Title Case vs official PBS casing vs bilingual Urdu
- D-CITY-DUPLICATE-ID: district-qualified display names if IDs diverge
- Cantonment display names if ever kept as cities (not recommended)
- Metro display names already clean (`Lahore`, `Karachi`, …) — confirm

