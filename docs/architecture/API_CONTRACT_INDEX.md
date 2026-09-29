# API Contract Index

**Status:** CURRENT  
**Generated from registered routes in** `backend/auth-service/src/app.ts` **and routers (2026-09-21).**  
**Do not invent parameters.** For full ride body fields, read parsers in `ride_service.ts`.

Common envelope (rides/drivers/location): `{ data, requestId, timestamp }` via http helpers. Auth `/me` / register may use flat profile shapes — see `routes/auth.ts`.

Auth: Firebase Bearer on `/v1/*` except `/healthz` and `/v1/internal/*` (worker token).

| Method | Route | Auth | Actor | Request (summary) | Success | Key errors | Idempotency | Implementation | Tests / Proof | Phase |
| ------ | ----- | ---- | ----- | ----------------- | ------- | ---------- | ----------- | -------------- | ------------- | ----- |
| GET | `/healthz` | none | — | — | `{ ok, service }` | — | no | `app.ts` | — | infra |
| POST | `/v1/auth/register` | Bearer | any verified | register body + `Idempotency-Key: register_{uid}` | profile | UNAUTHENTICATED, IDEMPOTENCY_KEY_REQUIRED, ACCOUNT_DISABLED, FORBIDDEN | yes | `routes/auth.ts`, `services/users.ts` | auth tests | 2A |
| GET | `/v1/auth/me` | Bearer | self | — | profile | USER_NOT_FOUND, ACCOUNT_DISABLED | no | `routes/auth.ts` | auth/security | 2A |
| PATCH | `/v1/auth/profile` | Bearer | self | `{ displayName }` only | profile | VALIDATION_ERROR, USER_NOT_FOUND | no | `routes/auth.ts`, profile/display_name | profile tests | 2C |
| POST | `/v1/rides` | Bearer | passenger | create body + **`city` (required)** + Idempotency-Key | ride SEARCHING | VALIDATION_ERROR, STATE_CONFLICT, IDEMPOTENCY_* | yes | `rides/routes.ts`, `ride_service.createRide` | rides + ride-proof + ride_city | 2E / city |
| GET | `/v1/rides` | Bearer | owner/assigned | `status`, `serviceType`, `limit`, `cursor` | list page | VALIDATION_ERROR, FORBIDDEN | no | `list_query.ts` | rides + list firestore | 2I |
| GET | `/v1/rides/open` | Bearer | approved driver | `limit`, `cursor` | open rides | DRIVER_NOT_ELIGIBLE, VALIDATION_ERROR | no | `open_discovery_query.ts` | open_discovery + m0 | M0 |
| GET | `/v1/rides/:rideId` | Bearer | participant | — | ride | RIDE_NOT_FOUND, FORBIDDEN | no | `getRide` | rides | 2E |
| GET | `/v1/rides/:rideId/offers` | Bearer | participant | optional `limit` | offers | RIDE_NOT_FOUND, FORBIDDEN | no | `listOffers` | rides | 2F |
| POST | `/v1/rides/:rideId/offers` | Bearer | approved driver | offer body + Idempotency-Key | offer | OFFER_*, STATE_CONFLICT, DRIVER_NOT_ELIGIBLE, … | yes | `createOffer` | rides + offer concurrency | 2F |
| POST | `/v1/rides/:rideId/offers/:offerId/select` | Bearer | passenger | body + Idempotency-Key | assigned ride | ALREADY_ASSIGNED, OFFER_*, STATE_CONFLICT | yes | `selectOffer` | rides concurrency | 2E/2F |
| POST | `/v1/rides/:rideId/offers/:offerId/withdraw` | Bearer | offering driver | Idempotency-Key | offer | OFFER_*, FORBIDDEN | yes | `withdrawOffer` | rides | 2F |
| POST | `/v1/rides/:rideId/cancel` | Bearer | passenger/assigned | body + Idempotency-Key | CANCELLED | STATE_CONFLICT, FORBIDDEN | yes | `cancelRide` | rides | 2E/2G |
| POST | `/v1/rides/:rideId/en-route` | Bearer | assigned driver | Idempotency-Key | DRIVER_EN_ROUTE | STATE_CONFLICT | yes | `markEnRoute` | progression proofs | 2G |
| POST | `/v1/rides/:rideId/arrive` | Bearer | assigned driver | Idempotency-Key | DRIVER_ARRIVED (+ arrivedAt) | STATE_CONFLICT | yes | `markArrived` | 2L proofs | 2G/2L |
| POST | `/v1/rides/:rideId/start` | Bearer | assigned driver | Idempotency-Key | RIDE_STARTED | STATE_CONFLICT | yes | `startRide` | progression | 2G |
| POST | `/v1/rides/:rideId/complete` | Bearer | assigned driver | Idempotency-Key | RIDE_COMPLETED | STATE_CONFLICT | yes | `completeRide` | progression | 2G |
| POST | `/v1/rides/:rideId/close` | Bearer | participant | Idempotency-Key | RIDE_CLOSED | STATE_CONFLICT | yes | `closeRide` | close proofs | 2H |
| POST | `/v1/rides/:rideId/ratings` | Bearer | participant | `{ stars:1-5 }` + Idempotency-Key | 201 rating | ALREADY_RATED, STATE_CONFLICT, FORBIDDEN | yes | `submitRating` | 2N proofs | 2N |
| GET | `/v1/rides/:rideId/ratings` | Bearer | participant | — | own rating | RATING_NOT_FOUND, FORBIDDEN | no | `getMyRating` | 2N | 2N |
| POST | `/v1/drivers/go-online` | Bearer | approved driver | `{}` | availability online | DRIVER_NOT_APPROVED | no | `drivers/*` | N1 proofs | N1 |
| POST | `/v1/drivers/go-offline` | Bearer | approved driver | `{}` | availability offline | DRIVER_NOT_APPROVED | no | `drivers/*` | N1/N2C | N1 |
| POST | `/v1/location/update` | Bearer | approved **online** driver | location packet | accept snapshot | INVALID_LOCATION, STALE_LOCATION, SEQUENCE_VIOLATION, FORBIDDEN | no | `location/*` | N2A/N2C | N2A |
| POST | `/v1/internal/rides/expire-sweep` | worker token | worker | optional `limit` | sweep stats | FORBIDDEN, VALIDATION_ERROR | n/a | `routes/internal.ts` | 2J | 2J |
| POST | `/v1/internal/rides/offer-expire-sweep` | worker token | worker | optional `limit` | sweep stats | FORBIDDEN | n/a | internal | 2K | 2K |
| POST | `/v1/internal/rides/no-show-sweep` | worker token | worker | optional `limit` | sweep stats | FORBIDDEN | n/a | internal | 2M | 2M |
| GET | `/v1/internal/drivers/nearby` | worker token | worker | `lat`, `lng`, optional `city`/`radiusKm`/`limit` | candidates ASC | VALIDATION_ERROR, FORBIDDEN, DEPENDENCY_ERROR | no | `nearby_service.ts`, `routes/internal.ts` | nearby.test + n3 proofs | N3 |
| POST | `/v1/internal/rides/dispatch-sweep` | worker token | worker | optional `limit` | sweep stats | FORBIDDEN, VALIDATION_ERROR | n/a | `dispatch_wave_service.ts`, `routes/internal.ts` | dispatch.test + n4 proofs | N4 |
| POST | `/v1/internal/rides/:rideId/dispatch-tick` | worker token | worker | path `rideId` | tick outcome | FORBIDDEN, RIDE_NOT_FOUND, DEPENDENCY_ERROR | n/a | same | same | N4 |
| POST | `/v1/drivers/device-tokens` | Bearer | approved driver | `{ token }` | `{ driverId, tokenId }` | FORBIDDEN, VALIDATION_ERROR | no | `delivery/device_token_service.ts` | delivery_d1.test | D1 |
| DELETE | `/v1/drivers/device-tokens` | Bearer | approved driver | `{ token }` | `{ driverId, cleared }` | FORBIDDEN, VALIDATION_ERROR | no | same | same | D1 |
| POST | `/v1/internal/outbox/dispatch-fcm-sweep` | worker token | worker | optional `limit` | sweep stats | FORBIDDEN | n/a | `delivery/dispatch_fcm_projector.ts` | delivery_d1 + d1 proofs | D1 |

## Not registered (documented elsewhere — do not call)

| Method | Route | Notes |
| ------ | ----- | ----- |
| GET | `/v1/drivers/nearby` | Architecture-final planning name; **not** N3 MVP path (internal-only) |
| GET | `/v1/location/nearby` | Older backend-architecture.md — **NOT IMPLEMENTED**; do not use |
| POST | `/v1/pricing/estimate` | **IMPLEMENTED (4B/5B)** — auth required; server Google Routes + 5A fare; writes `pricingSnapshots`; see [`phase-05-pricing.md`](../implementation/phase-05-pricing.md) |
| GET | `/v1/pricing/rules` | Planning-only; admin/config — **NOT IMPLEMENTED** |

### Create ride prerequisites (passenger path)

`POST /v1/rides` already requires: pickup/destination `{lat,lng}`, **`city`**, `pricingSnapshotId` (server-issued snapshot must exist), in-bounds `passengerOfferMinor`. **Phase 5C** Flutter wires estimate → snapshot id + city on create (device proof pending).
## Location body fields (N2A)

Required by `parseAndValidateLocationBody`: `locationSeq`, `locationStreamId`, `lat`, `lng`, `accuracy`, `heading`, `speed`, `provider`, `timestamp`; optional `rideId`, `altitude`.
