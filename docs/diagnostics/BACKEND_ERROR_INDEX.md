# Backend Error Index

**Status:** CURRENT  
**Source:** codes thrown/sent under `backend/auth-service/src` (extracted 2026-09-21).  
**Planning-only codes** in `docs/api/error-codes.md` that are **not** in this table are aspirational.

Diagnostic companion: [`BACKEND_TROUBLESHOOTING.md`](BACKEND_TROUBLESHOOTING.md)

| Error | HTTP | Origin | Meaning | Diagnostic | Test / Proof |
| ----- | ---: | ------ | ------- | ---------- | ------------ |
| `UNAUTHENTICATED` | 401 | `middleware/auth.ts`, routers | Missing/invalid Bearer | Auth token | `security_phase2b.test.ts` |
| `APP_CHECK_REQUIRED` | 401 | `middleware/auth.ts` | App Check header required | Env `REQUIRE_APP_CHECK` | security_phase2b |
| `APP_CHECK_INVALID` | 401 | `middleware/auth.ts` | App Check verify failed | Client attestation | security_phase2b |
| `RATE_LIMITED` | 429 | `rate_limit_middleware.ts` | Too many requests | Limiter window | security_phase2b |
| `USER_NOT_FOUND` | 404 | `routes/auth.ts` | No users/{uid} | Call register | auth/profile tests |
| `ACCOUNT_DISABLED` | 403 | auth + eligibility | banned / inactive | users flags | auth + rides |
| `FORBIDDEN` | 403 | many | Authz / worker / online gate | Context-specific | domain tests |
| `IDEMPOTENCY_KEY_REQUIRED` | 400 | `routes/auth.ts` (+ rides require key helpers) | Missing Idempotency-Key | Header | auth / rides |
| `IDEMPOTENCY_KEY_REUSED` | 409 | `ride_service.ts` | Same key different hash / actor | Idempotency record | rides proofs |
| `VALIDATION_ERROR` | 400 | auth, rides, list/open query, money, internal | Bad body/query | Payload | unit tests |
| `NOT_FOUND` | 404 | `app.ts` | Unknown route | Route registration | — |
| `INTERNAL` | 500/503 | http helpers / worker | Unexpected / worker misconfig | Logs | — |
| `DEPENDENCY_ERROR` | 503 | `NearbyDriversService` / N3 Redis fail-closed | Redis unset/down / command failure | Redis + N3 | `nearby.test.ts`, n3 proofs |
| `DRIVER_NOT_APPROVED` | 403 | drivers + location | Not approved driver | users.driverStatus | N1/N2A proofs |
| `DRIVER_NOT_ELIGIBLE` | 403/422 | eligibility / offer create | Not approved **or** already DRIVER_ASSIGNED | Actor / active ride | rides / open discovery |
| `INVALID_LOCATION` | 422 | `location/validation.ts` | GPS payload invalid | Accuracy/speed/coords | N2A proof |
| `STALE_LOCATION` | 422 | `location/validation.ts` | Timestamp window | Clock skew | N2A proof |
| `SEQUENCE_VIOLATION` | 422 | `location_update_service.ts` | Stream/seq rules | locationStreams | N2A proof |
| `RIDE_NOT_FOUND` | 404 | `ride_service.ts` | Unknown rideId | Path param | rides |
| `OFFER_NOT_FOUND` | 404 | `ride_service.ts` | Unknown offer | Path | rides |
| `ALREADY_ASSIGNED` | 409 | `ride_service.ts` | Ride has driver / offer blocked | ride.assignedDriverId | rides concurrency |
| `STATE_CONFLICT` | 409 | state_machine + ride_service | Illegal transition / window | Ride state | rides / 2G–2M |
| `VERSION_CONFLICT` | 409 | `ride_service.ts` | Optimistic version mismatch | ride.version | rides |
| `OFFER_STALE` | 422 | `ride_service.ts` | requestVersion mismatch | Ride requestVersion | rides |
| `OFFER_ALREADY_EXISTS` | 409 | `ride_service.ts` | Live offer exists | rideOffers | rides |
| `OFFER_AMOUNT_MISMATCH` | 422 | `ride_service.ts` | Accept ≠ passengerOfferMinor | Amount | rides |
| `OFFER_EXPIRED` | 422 | `offer_lifecycle.ts` | Offer TTL elapsed | expiresAt | 2K proofs |
| `OFFER_NOT_SELECTABLE` | 422 | `offer_lifecycle.ts` | Not PENDING | status | rides |
| `FARE_OUT_OF_BOUNDS` | 422 | `pricing_snapshot.ts` | Outside snapshot bounds | pricingSnapshots | rides |
| `PRICING_SNAPSHOT_EXPIRED` | 422 | pricing + ride_service | Missing/expired snapshot | pricingSnapshots | rides |
| `ALREADY_RATED` | 409 | `ride_service.ts` | Rating doc exists | ratings collection | 2N proofs |
| `RATING_NOT_FOUND` | 404 | `ride_service.ts` | No own rating | GET ratings | 2N proofs |

Location soft-warn (not an HTTP error): log `location_soft_bbox_warn`.
