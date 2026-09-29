# Duplicate Canonical ID Resolution (Slice 2C)

**Status:** All collisions remain **REQUIRE_PRODUCT_DECISION** — no silent suffixes.

`normalizeCitySlug` = trim + lowercase. Multi-word shaping: spaces→hyphens then normalize.

## `sahiwal`

**Summary:** Sahiwal MetCorp (Sahiwal District) vs Sahiwal MC (Sargodha District)

| PBS source | District | Pop 2023 | Prior | Display |
| ---------- | -------- | -------- | ----- | ------- |
| SAHIWAL METROPOLITAN CORPORATION | SAHIWAL DISTRICT | 538,344 | DIRECT | Sahiwal |
| SAHIWAL MC | SARGODHA DISTRICT | 57,374 | DIRECT | Sahiwal |

**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.

**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.

**Deterministic strategy (PROPOSAL ONLY — not approved):**
1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.
2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.
3. **Forbidden:** transform-time silent arbitrary suffixes without policy.

**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)

## `khanpur`

**Summary:** Khanpur MC (Rahim Yar Khan) vs Khanpur TC (Shikarpur)

| PBS source | District | Pop 2023 | Prior | Display |
| ---------- | -------- | -------- | ----- | ------- |
| KHANPUR MC | RAHIM YAR KHAN DISTRICT | 247,170 | DIRECT | Khanpur |
| KHANPUR TC | SHIKARPUR DISTRICT | 18,052 | DIRECT | Khanpur |

**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.

**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.

**Deterministic strategy (PROPOSAL ONLY — not approved):**
1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.
2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.
3. **Forbidden:** transform-time silent arbitrary suffixes without policy.

**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)

## `khangarh`

**Summary:** Khangarh TC (Ghotki, Sindh) vs Khangarh MC (Muzaffargarh, Punjab)

| PBS source | District | Pop 2023 | Prior | Display |
| ---------- | -------- | -------- | ----- | ------- |
| KHANGARH TC | GHOTKI DISTRICT | 32,648 | DIRECT | Khangarh |
| KHANGARH MC | MUZAFFARGARH DISTRICT | 32,161 | DIRECT | Khangarh |

**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.

**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.

**Deterministic strategy (PROPOSAL ONLY — not approved):**
1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.
2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.
3. **Forbidden:** transform-time silent arbitrary suffixes without policy.

**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)

## `karampur`

**Summary:** Karampur TC (Vehari, Punjab) vs Karampur TC (Kashmore, Sindh)

| PBS source | District | Pop 2023 | Prior | Display |
| ---------- | -------- | -------- | ----- | ------- |
| KARAMPUR TC | VEHARI DISTRICT | 27,840 | DIRECT | Karampur |
| KARAMPUR TC | KASHMORE DISTRICT | 20,050 | DIRECT | Karampur |

**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.

**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.

**Deterministic strategy (PROPOSAL ONLY — not approved):**
1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.
2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.
3. **Forbidden:** transform-time silent arbitrary suffixes without policy.

**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)

## `hyderabad`

**Summary:** Coalesced Hyderabad Sindh metro (kept in catalog) vs Hyderabad TC (Bhakkar, Punjab)

### Entity A — Sindh metro (currently in candidate catalog as COALESCED)
- Display: Hyderabad
- Population sum: 1,487,098
- Source rows: [29, 31]
- Source names: ['HYDERABAD MUNICIPAL CORPORATION (Part of Latifabad Taluka)', 'HYDERABAD MUNICIPAL CORPORATION (Part of Hyderabad City Taluka)']

### Entity B — Punjab TC (REVIEW_REQUIRED / demoted)
| PBS source | District | Pop 2023 | Prior | Display |
| ---------- | -------- | -------- | ----- | ------- |
| HYDERABAD TC | BHAKKAR DISTRICT | 25,319 | DIRECT | Hyderabad |

**Geographic distinction:** Confirmed distinct districts → distinct passenger-facing places.

**Why same ID:** cleaned base name → same string → `normalizeCitySlug` yields identical id.

**Deterministic strategy (PROPOSAL ONLY — not approved):**
1. Prefer keeping the larger / metro entity on the plain city slug when product agrees.
2. Assign the other entity a **product-defined** unique slug (e.g. district-qualified) via an approved naming table.
3. **Forbidden:** transform-time silent arbitrary suffixes without policy.

**Status:** `REQUIRE_PRODUCT_DECISION` (D-CITY-DUPLICATE-ID)

