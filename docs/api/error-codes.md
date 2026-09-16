# ORA — Complete Error Code Reference

## Authentication & Authorization

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| UNAUTHENTICATED | 401 | Missing or expired JWT | Refresh token; re-login if refresh fails |
| APP_CHECK_FAILED | 403 | Invalid or missing App Check token | Retry; if persistent: update app |
| UNAUTHORIZED | 403 | User not permitted for this operation | Show permission error; log to analytics |
| ACCOUNT_SUSPENDED | 403 | Account suspended | Show suspension message with contact support |
| DRIVER_NOT_APPROVED | 403 | Driver trying to go online before approval | Show pending approval state |

## Ride Operations

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| RIDE_NOT_FOUND | 404 | Ride ID does not exist | Refresh; navigate to home |
| OFFER_NOT_FOUND | 404 | Offer ID does not exist | Refresh offer inbox |
| RIDE_CONFLICT | 409 | Ride concurrency conflict | Refresh ride |
| ALREADY_ASSIGNED | 409 | Ride already has a driver | Show assigned state; remove pending card |
| STATE_CONFLICT | 409 | Invalid state transition | Refresh ride state from server |
| VERSION_CONFLICT | 409 | Optimistic concurrency failure | Refresh and retry |
| IDEMPOTENCY_KEY_REUSED | 409 | Same idempotency key reused with different payload | Generate a new key; do not retry blindly |
| ALREADY_RATED | 409 | Rating already exists for this ride and direction | Show existing rating; do not overwrite |
| RATING_NOT_FOUND | 404 | Caller has no rating for this ride | Show rate CTA or empty state |
| OFFER_ALREADY_EXISTS | 409 | Driver already has a live offer | Show existing offer; wait for selection |
| INVALID_STATE_TRANSITION | 422 | Cannot go from A to B | Show state error; log |
| PROXIMITY_VIOLATION | 422 | Driver too far from pickup/destination | Show "Please move closer" |
| OFFER_EXPIRED | 422 | Offer TTL elapsed | Hide offer; cannot select |
| OFFER_STALE | 422 | Offer does not match current requestVersion | Refresh offers |
| OFFER_NOT_SELECTABLE | 422 | Offer not PENDING | Refresh offers |
| OFFER_AMOUNT_MISMATCH | 422 | Accept amount ≠ passenger offer | Recreate offer |
| DRIVER_NOT_ELIGIBLE | 403/422 | Driver cannot offer or is no longer eligible at select | Remove card |
| RIDE_EXPIRED | 410 | Ride is expired/cancelled | Remove from UI; show notification |

## Pricing

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| FARE_OUT_OF_BOUNDS | 422 | Offered fare outside allowed range | Show allowed range; ask to adjust |
| PRICING_SNAPSHOT_EXPIRED | 422 | pricingSnapshotId older than 10 min | Re-fetch estimate; re-confirm |
| PRICING_UNAVAILABLE | 503 | Google Routes API temporarily unavailable | Retry after 3s; show loading state |

## Location

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| INVALID_LOCATION | 422 | Location accuracy > 50m or implausible | Show GPS warning; wait for better fix |
| STALE_LOCATION | 422 | Location timestamp too old (> 15s) | Send fresh GPS fix |
| OUT_OF_SERVICE_AREA | 422 | Pickup/destination outside active zones | Show "We don't serve this area yet" |
| SEQUENCE_VIOLATION | 422 | Location seq ≤ last accepted seq | Discard silently; no user action |

## Payment

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| PAYMENT_FAILED | 402 | PSP declined or timed out | Retry; offer cash fallback |
| INSUFFICIENT_BALANCE | 402 | Wallet balance too low | Prompt top-up |
| PAYMENT_METHOD_INVALID | 422 | Payment method not supported | Change payment method |
| DUPLICATE_PAYMENT | 409 | Idempotency key conflict on payment | Return existing payment result |
| RECONCILIATION_REQUIRED | 409 | Payment state unresolved; manual or async recovery required | Show pending resolution state |

## Rate Limiting

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| RATE_LIMITED | 429 | Too many requests | Exponential backoff; show wait message |
| RIDE_CREATION_LIMIT | 429 | Too many ride requests this hour | Show cooldown timer |

## Server

| Code | HTTP | Description | Client Action |
|---|---|---|---|
| SERVER_ERROR | 500 | Unhandled server exception | Retry; if persistent: show error and contact support |
| SERVICE_UNAVAILABLE | 503 | Planned maintenance or dependency down | Show maintenance message; retry after interval from Retry-After header |
| DEPENDENCY_ERROR | 503 | Redis/Firestore/Maps API down | Graceful degradation message |

## Client Recovery Strategies

```
RIDE_CONFLICT / ALREADY_ASSIGNED → if driver: discard pending card; if passenger: show assigned driver
OFFER_EXPIRED / OFFER_STALE / OFFER_NOT_SELECTABLE → refresh offer inbox; do not retry select
VERSION_CONFLICT → GET /rides/{id}; re-render from fresh state
PRICING_SNAPSHOT_EXPIRED → POST /pricing/estimate; present new recommended fare; passenger re-enters offer
UNAUTHENTICATED → call auth.currentUser?.getIdToken(true) → retry
RATE_LIMITED → read Retry-After header; wait; retry
500 SERVER_ERROR → retry with exponential backoff max 3×; then show error UI
```
