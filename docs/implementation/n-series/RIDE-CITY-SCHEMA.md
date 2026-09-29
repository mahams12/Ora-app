# Ride City Schema (`rides.city` metadata)

**Status:** **ARCHITECTURE FROZEN** + **IMPLEMENTED** (backend create path) — 2026-09-21  
**Resync:** 2026-09-21 — coordinate-primary matching means this field is **not** an N4/N3 matching prerequisite ([`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md), [`N4-dispatch-planning.md`](N4-dispatch-planning.md)).  
**Scope:** `rides.city` create/storage/API exposure. **N4 NOT IMPLEMENTED.**  
**Authority:** Code + this freeze.

---

## Audit summary

| Finding | Evidence |
| ------- | -------- |
| No `city` on `RideDoc` before this change | `rides/types.ts`, `createRide` |
| Pickup is `{ lat, lng, address? }` only | `parseLatLng` |
| No geocoder / reverse geocoder in auth-service | repo search |
| Driver `homeCity` is ops-seeded, not ride source | N1/N2C; no writer API |
| Flutter create body has no city | `ride_request_view_model.dart` |
| Shared normalizer | `normalizeCitySlug` in `redis/types.ts` (trim + lowercase) |

**Historical note:** Field was introduced when N4 planning assumed city-sharded GEO. **Matching is now coordinate-primary** (`geo:drivers` via pickup lat/lng). Keep `rides.city` as create metadata until a separate API soft-deprecation slice.

---

## Decision matrix

| ID | Decision | Chosen |
| -- | -------- | ------ |
| **D-CITY-SOURCE** | Where city comes from | **Client body field `city`** on `POST /v1/rides`. Not geocode, not address parse, not `homeCity`, not IP. |
| **D-CITY-FIELD** | Firestore | **`rides/{rideId}.city: string`** (normalized slug) |
| **D-CITY-NORMALIZATION** | How | **Reuse `normalizeCitySlug` only** — trim + lowercase; non-string/empty → reject. No second normalizer. |
| **D-CITY-REQUIRED** | New creates (current API) | **Required** on create path today (`VALIDATION_ERROR` 400). Soft-deprecation to optional is a **future** API slice — not this freeze. |
| **D-HISTORICAL-RIDES** | Old docs | **No automatic backfill**. Old rides may omit `city`. |
| **D-CITY-EXPOSURE** | API | Include on **`publicRide`**. **Omit** from M0 `publicOpenRide`. |
| **D-CITY-MATCHING** | N3 / N4 | **NOT a matching gate.** Spatial input = pickup lat/lng → `geo:drivers`. Missing `rides.city` **must not** exclude a ride from dispatch solely for that reason. |

### Trust model (UPDATED)

- City is **optional product/ops metadata** relative to matching (coordinate-primary).
- It is **not** authorization to assign.
- It is **not** the Redis GEO shard selector for N3/N4 after the cutover.
- Create API may still require the field until a dedicated soft-deprecation slice.
- Catalog allowlist validation remains a **future** UX/ops slice — not a matching prerequisite.

### Flutter

**2026-09-21:** No city selector in `mobile/`. Flutter city UI is **not** an N4 matching blocker (pickup coordinates are). Catalog/selector remains future UX work — [`PAKISTAN-CITY-ARCHITECTURE.md`](PAKISTAN-CITY-ARCHITECTURE.md).

---

## API contract (current create path)

```text
POST /v1/rides
body.city: string (currently required by API)
→ normalizeCitySlug(city)
→ store rides.city
→ publicRide includes city
```

N4 dispatch spatial contract:

```text
pickup.lat + pickup.lng → N3 findNearby → geo:drivers
(rides.city ignored for matching)
```

---

## N3 / N4 compatibility

Same slug normalizer may still be used if city metadata is present. **Matching does not use city.** See [`N4-dispatch-planning.md`](N4-dispatch-planning.md) D-CANDIDATE-SOURCE.

---

## Related

- [`N4-dispatch-planning.md`](N4-dispatch-planning.md)  
- [`CITY-PARTITION-STRATEGY-DECISION.md`](CITY-PARTITION-STRATEGY-DECISION.md)  
- `normalizeCitySlug` — `backend/auth-service/src/redis/types.ts`
