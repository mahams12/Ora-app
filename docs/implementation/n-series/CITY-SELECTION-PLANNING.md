# City Selection — Product / UI Decision Freeze

**Status:** **PARTIALLY SUPERSEDED** — see [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md)  
**Original freeze date:** 2026-09-21  
**Supersession:** Product requirement is **Pakistan-wide**. The **small Flutter const launch-city catalog** as catalog SoT is **SUPERSEDED**.  

**Still valid from this doc:** explicit user selection; form-scoped; required before submit; bottom-sheet pattern; no GPS/geocode/IP/address parse; send slug as `city`; backend `normalizeCitySlug` authoritative for normalization.

**Updated UX for nationwide:** searchable bottom sheet over **server catalog** (not a tiny closed hardcode) — frozen in Pakistan-wide architecture.

**Do not implement** the selector until the Pakistan-wide catalog/API/validation path is sequenced.

---

## Audit — current Flutter state

| Item | Finding |
| ---- | ------- |
| City field / selector | **Missing** |
| `LatLngPoint` | `lat`, `lng`, `address?` only |
| `RideRequestCapabilities` | pricing + resolved coords — **no city** |
| Compose UI | Pickup/destination `OraTextField`s; decorative `RideLocationPlaceholder` (not GPS) |
| Category selection | `RideCategorySelector` + local const `kRideCategoryOptions` |
| Sheets | `showOraBottomSheet` used for gates / shells |
| Design widgets | `OraTextField`, `OraButton`, `OraCard`, `OraChip`, `OraListRow`, `OraEmptyState`, `OraErrorState`, `OraSectionHeader` |
| Dropdown / searchable package | **None** |
| City catalog in `mobile/` | **None** |
| Backend city list API | **None** |
| `serviceAreas` Firestore | **Schema docs only** — not implemented / not queried by Flutter |

---

## Product meaning (FROZEN)

**Pickup city** = explicit user choice of which Ora service city / GEO shard this ride belongs to.

Not device location. Not inferred from typed landmark text. Not driver `homeCity`. Not account “home”.

One ride → one pickup city → `POST /v1/rides.city` → `normalizeCitySlug` → `rides.city`.

---

## Recommended UX (ORIGINAL — partially superseded)

**Originally chosen: C — closed bottom-sheet list** over a small approved const catalog.

### Nationwide update (authoritative)

**SUPERSEDED membership model.** See [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md):

- Catalog SoT = **server-managed** (not Flutter hardcode)
- UX = **searchable** bottom sheet over active catalog
- Closed tiny list is not Pakistan-wide SoT

### Placement (still valid)

On **compose** (`RideRequestView`), **above** pickup/destination fields:

1. Tappable row / field: label **Pickup city**, value = selected display name or placeholder “Select pickup city”
2. Tap → `showOraBottomSheet` with list of approved cities (OraCard / OraListRow rows, same spirit as `RideCategorySelector`)
3. Select → dismiss sheet → show selection on compose
4. Advance to review / submit **requires** city selected

### Why not A (free text)

Typos produce wrong GEO shards (`lahoree` vs `lahore`) → empty N3/N4. Backend accepts arbitrary slugs (shard selector), so UI must constrain.

### Why not B (searchable package)

No search UI package; small launch list does not need search for MVP. Can add filter later without new packages if list grows.

### Why C fits repo

- `showOraBottomSheet` already used on ride request for gate messages
- Explicit selection pattern already proven via `RideCategorySelector` + const catalog
- Reuses `OraCard` / `OraListRow` / `OraSectionHeader` / `OraButton`

**Do not redesign** the whole ride-request screen. Additive field only.

---

## Decision matrix

| ID | Current | Options | **Chosen** | Reason | Consequence |
| -- | ------- | ------- | ---------- | ------ | ----------- |
| **D-CITY-UI** | None | Text field; searchable; bottom sheet; existing location selector | **Bottom-sheet selector** | Matches Ora sheets + category rows; closed set | Compose + sheet widgets |
| **D-CITY-SOURCE** | None | GPS; geocode; address parse; profile; **explicit select** | **Explicit user selection from catalog** | Only honest source | No invent |
| **D-CITY-LIST** | None | Huge hardcode; backend API; **small approved const** | **Small Flutter const catalog** (like categories); membership = **product-approved** | No API exists; `serviceAreas` unimplemented | List must be approved before code ships |
| **D-CITY-VALUE** | N/A | Display only; slug; both | Send catalog **`id` (slug)** as `city`; keep `displayName` UI-only | Backend `normalizeCitySlug` remains SoT | Body:`city: selected.id` |
| **D-CITY-PERSISTENCE** | N/A | Form only; local default; profile | **Form-scoped only** (`RideRequestUiState`) | Smallest MVP | No profile write |
| **D-CITY-REQUIRED** | N/A | Optional; required | **Required** to leave incomplete / to submit | Backend requires city | New block reason |
| **D-CITY-ERROR** | N/A | Soft warn; hard gate | **Hard gate** client-side; backend 400 still authoritative | Honesty | Gate sheet / disabled CTA |
| **D-CITY-N4-CONTRACT** | Updated | — | UI city → metadata only; N4 uses pickup lat/lng → N3 `geo:drivers` | Matching unblocked without Flutter city | See `N4-dispatch-planning.md` |

---

## D-CITY-LIST — membership (YELLOW)

**Mechanism (FROZEN):** Flutter constant, e.g. conceptual `kOraPickupCityOptions` with:

| Field | Role |
| ----- | ---- |
| `id` | Slug sent as `city` (e.g. `lahore`) — must match driver GEO / `homeCity` slug convention |
| `displayName` | UI only (e.g. `Lahore`) |

**Membership (NOT unilaterally invented here):**

Product must approve the exact launch set **before implementation**. Do not ship an empty catalog. Do not invent a national city database.

Docs/examples often mention Lahore / Karachi / Islamabad — **examples only**, not an approved launch list until product confirms.

**Future slice (SEPARATE):** Backend-readable `serviceAreas` (or dedicated cities API) replaces the Flutter const as SoT. Until then, const is MVP.

---

## D-CITY-VALUE (FROZEN)

```text
User selects city row (id + displayName)
→ Flutter stores selectedCityId on form state
→ POST /v1/rides { ..., city: selectedCityId }
→ backend normalizeCitySlug(city) → rides.city
```

- Prefer sending the catalog **`id`** (already slug-shaped).
- Do **not** require a second Flutter normalizer.
- Backend remains authoritative if casing/whitespace slips through.

---

## D-CITY-PERSISTENCE (FROZEN)

**MVP:** Current ride-request form only.  
No SharedPreferences default. No profile `homeCity`. No cross-session restore required.

---

## D-CITY-REQUIRED + D-CITY-ERROR (FROZEN)

| State | Behavior |
| ----- | -------- |
| No city selected | Cannot treat request as complete; block submit / block advance as designed for incomplete fields |
| City selected + pickup/destination text rules unchanged | Existing compose→review rules remain; city is additional required |
| Capabilities still lack coords/pricing | Existing `locationUnavailable` / `pricingUnavailable` gates unchanged |
| Backend rejects city | Existing API error path (`VALIDATION_ERROR` / failure mapper) — **do not weaken backend** |

Suggested block reason (implementation naming free): `cityMissing` → honest copy: “Select a pickup city to continue.”

---

## Empty / accessibility (FROZEN intent)

- Clear label: **Pickup city**
- Selected vs empty visual state (chip / field value)
- Sheet: cancel/back dismisses without change
- Semantics: button + selected on rows (mirror category selector)
- No remote loading in MVP (local const) → no catalog spinner unless future API

---

## N4 contract (UPDATED — coordinate-primary)

```text
Pickup lat/lng (required for matching)
  → POST /v1/rides (city may still be sent as metadata)
  → (future) N4 dispatch-sweep
  → NearbyDriversService.findNearby({ lat, lng, radiusKm: 10 })
  → geo:drivers
```

City selector (if/when built) feeds **metadata**, not the Redis matching key. See [`N4-dispatch-planning.md`](N4-dispatch-planning.md).

---

## Explicit non-goals

GPS, geolocation packages, geocoding, reverse geocoding, maps, IP location, default Lahore, parsing city from address text, driver homeCity writer, profile home city, multi-city rides, N4, weakening backend validation, backend cities API (future), `serviceAreas` polygons.

---

## Launch-city membership approval gate (SUPERSEDED as final model)

**2026-09-21:** No authoritative tiny launch list in repo.  
**Later same day:** Product clarified **Pakistan-wide** coverage → tiny membership approval is **not** the end architecture.

**Authoritative nationwide model:** [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md).

**PRODUCT APPROVAL REQUIRED** now means: ops/product **populate server catalog** (future slice) — **not** invent a Flutter hardcode list in chat.  

---

## Preconditions for implementation prompt

1. **Product-approved** launch city list (`id` + `displayName`) attached — **not found in repo** (see approval gate above)  
2. This freeze remains authoritative for UX/mechanism  
3. Backend city contract unchanged  
4. No new Flutter packages  

---

## Related

- [`RIDE-CITY-SCHEMA.md`](RIDE-CITY-SCHEMA.md)  
- [`N4-dispatch-planning.md`](N4-dispatch-planning.md)  
- `mobile/.../ride_request_view.dart`, `ride_category_selector.dart`, `ora_bottom_sheet.dart`

---

## Verdict

> Original small-catalog UX freeze is **partially superseded** by Pakistan-wide architecture.  
> **Do not implement** Flutter city selector against a hardcoded launch list.  
> Follow [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md).

