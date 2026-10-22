# Ride-State FCM Projector — Scoped Design (NOTIF-RS-PUSH)

**Status:** IMPLEMENTED (backend + client token path) — unit-tested locally;
NOT deployed, no live E2E push verified (staging billing blocked) — 2026-10-19.
**Companion client:** `RideFcmNudge` + `DispatchFcmService.rideNudges` +
`fcmRideNudgeProvider` (Phase 1, shipped) — the client is already lenient and
inert; this design is the minimal backend that activates it.

## Goal

When a ride's server-authoritative state changes, push a **data-only FCM
"nudge"** to the affected passenger/driver device(s) so the open active-ride
screen refreshes immediately instead of waiting for the 3–8s poll.
Push payloads carry **identifiers only** — the client then fetches
authoritative state via `GET /v1/rides/{id}` (existing `refresh()`).

## Reuse of the proven D1 pattern

The dispatch projector (`src/delivery/dispatch_fcm_projector.ts`) already
implements exactly the mechanics needed: outbox scan (PENDING-first +
expired-lease CLAIMED reclaim), (leaseOwner, attemptCount) CAS fencing,
per-recipient durable results, bounded retries + dead-letter, per-token
invalid-token cleanup. The ride-state projector mirrors that shape 1:1 with a
different event allowlist, subscriber id, and recipient resolution.

## Event allowlist (explicit, closed set)

Outbox `eventType` values already emitted by `ride_service.ts` (verified
2026-10-19). Only these map to pushes; all others are skipped.

| eventType | Recipients | Rationale |
|---|---|---|
| `ride.assigned` | passenger + assigned driver | the key transition out of SEARCHING |
| `ride.driver.en_route` | passenger | progress visible on tracking map |
| `ride.driver.arrived` | passenger | wait-clock starts |
| `ride.started` | passenger | ride underway |
| `ride.completed` | passenger + driver | rating prompt |
| `ride.closed` | passenger + driver | terminal |
| `ride.cancelled` | passenger + driver (whoever didn't cancel) | terminal |
| `ride.no_show` | passenger + driver | terminal |
| `ride.expired` | passenger | SEARCHING timeout |
| `ride.offer.received` | passenger | offers inbox count/content |
| `ride.offer.withdrawn` | passenger | offers inbox |
| `ride.offer.expired` | passenger | offers inbox |
| `ride.offer.selected` | offer's driver | driver learns they won |
| `ride.rating.submitted` | *excluded* — not ride-visible |

Deliberately **excluded**: `ride.created` (the creator already navigates),
`ride.dispatch.wave_completed` (D1's own projector), `ride.rating.submitted`
(nothing on screen changes), and any event not listed — the allowlist is a
closed `Set`, not a prefix match.

## Recipient resolution (authorized)

`aggregateId` = rideId; payloads carry only `{offerId, driverId, …}` — **no
passengerId** in most events. Resolution therefore reads `rides/{rideId}`
once per event inside the claim transaction's post-claim phase:

- `passenger` recipient ← `ride.passengerId`
- `driver` recipient ← `ride.assignedDriverId` (or `offer.driverId` for
  `ride.offer.selected`, where `assignedDriverId` may not be set yet —
  resolve via `rides/{id}` first and fall back to `offers/{offerId}.driverId`)
- For `ride.cancelled`: recipient = the *other* party
  (`ride.cancelledBy` comparison) — both parties may also simply be nudged;
  the client dedups and the extra fetch is idempotent, so "notify both" is
  acceptable and simpler.

The ride-doc read also double-checks `state` still warrants a push
(stale-outbox guard): if the event's implied transition is already
superseded (e.g. `en_route` event but ride is `RIDE_STARTED`), the nudge is
still harmless — send it anyway (client fetches current truth), but a
`terminalReached` fast-path may skip mid-transition nudges once the ride is
terminal **and** a terminal push already went out (delivery doc records the
last pushed state).

## Payload (identifiers only — matches client contract)

```json
{
  "type": "RIDE_UPDATE",
  "rideId": "<aggregateId>",
  "eventId": "<outbox eventId>",
  "deliveryEventId": "<outboxDeliveries docId>"
}
```

- `type` is diagnostic only; the client's `RideFcmNudge` needs only `rideId`.
- **Never** put `state`, `fare`, `driverId`, or PII in the payload — FCM is
  not trusted and the client must not consume them.
- Data-only messages (no `notification` block) so the app decides; on tap of
  an OS-shown fallback the client emits the same nudge.

## Idempotency

- Outbox delivery doc id: `${eventId}_fcm_ride_state` (same
  `outboxDeliveryDocId` scheme, `subscriber: 'fcm_ride_state'`).
- Per-recipient `tokenResults` keyed by `tokenResultKey(token)` — a token
  already `SENT` is never resent on retry (H5, same as D1).
- Client side: `eventId` dedup via the existing 200-entry seen-set; id-less
  bursts collapse via the 500ms VM debounce.
- Out-of-order pushes are harmless — every nudge triggers the same
  authoritative `GET /v1/rides/{id}`.

## Required backend work (files)

1. `src/delivery/ride_state_types.ts` — constants (`RS_EVENT_TYPES` allowlist
   set, `RS_SUBSCRIBER='fcm_ride_state'`, `RS_FCM_TYPE='RIDE_UPDATE'`, sweep
   batch/lease/attempt constants reused from `d1_types`).
2. `src/delivery/ride_state_fcm_projector.ts` — `RideStateFcmProjector`
   class: `sweep()` + `processEvent()` cloned from the D1 shape with:
   `eventType ∈ RS_EVENT_TYPES` filter in the scan queries, recipient
   resolution via `rides/{id}` (+ `offers/{id}` for offer.selected),
   `driverResults` renamed `recipientResults` (keyed by uid instead of
   driverId).
3. `src/delivery/user_device_token_service.ts` *(or extend DeviceTokenService)* —
   **blocker found:** `driverDeviceTokens` registration is gated to
   `role=='driver' && driverStatus=='approved'` (`device_token_service.ts:60`).
   Passengers have no token path today. Options:
   a. Generalize to `userDeviceTokens` keyed by uid (migration: none —
      drivers' docs stay in `driverDeviceTokens`, or re-key; simplest is a
      parallel `passengerDeviceTokens` collection reusing the same service
      class with a collection-name parameter). **Recommended:** parameterize
      `DeviceTokenService` with a collection + role-gate so passenger
      registration `POST /v1/device-tokens` (new route, `role=='passenger'`)
      reuses everything.
   b. Alternative: topic-based `topic_ride_<rideId>` — rejected: requires
      client subscribe per ride and gives any subscriber every update for
      that ride (still safe — identifiers only — but per-device tokens are
      the established pattern).
4. `src/routes/internal.ts` — `POST /v1/internal/outbox/ride-state-fcm-sweep`
   (worker-token guarded, same as dispatch sweep) + Cloud Scheduler entry
   (staging cron already exists for the dispatch sweep — same cadence,
   e.g. `*/1 * * * *` since ride transitions are latency-sensitive).
5. `src/routes/drivers.ts` / new passenger route — token register/clear for
   passengers (per option 3a).
6. Client: extend `DriverDeviceTokenRemoteDataSource` → generic
   `DeviceTokenRemoteDataSource` and call it for passengers too (small —
   reuse `dispatch_fcm_service` token sync or add a passenger sync hook in
   `App.init`).

## Tests required

- `src/__tests__/delivery_ride_state.test.ts` mirroring `delivery_d1.test.ts`:
  allowlist membership (non-allowlisted events skipped), recipient
  resolution (passenger-only, driver-only, both, cancelledBy logic),
  offer.selected → offer.driverId path, invalid-token removal, retry →
  dead-letter at max attempts, CAS fencing (stale worker no-op),
  PENDING-first scan ordering.
- Client: existing `ride_fcm_nudge_test` + VM nudge tests already cover the
  consumer contract; add one parse test for `type:'RIDE_UPDATE'`.

## Implementation scope estimate (added 2026-10-19, Phase 3 review)

Rough sizing per work item — assumes the recommended option 3a
(parameterized `DeviceTokenService`) and the closed event allowlist:

| Item | Shape | Est. effort |
| ---- | ----- | ----------- |
| Projector class + types | Near-clone of `dispatch_fcm_projector.ts` with `eventType` filter + dual-recipient resolution | ~1–1.5 days incl. review |
| Token registration (passenger + driver) | Parameterize `DeviceTokenService` (collection name + role gate); add `POST /v1/device-tokens` route for `role=='passenger'`; driver path unchanged | ~0.5–1 day |
| Recipient authorization | `rides/{id}` read per event (already in D1 pattern — Firestore doc read, cached per sweep tick optional); offer.selected fallback via `offers/{id}` | included above |
| Internal sweep route + scheduler | `POST /v1/internal/outbox/ride-state-fcm-sweep` + `*/1 * * * *` scheduler entry (staging only — deployment gated by billing) | ~0.5 day |
| Outbox idempotency/CAS | Reuse — no new mechanism; just constants + tests proving fence | included in projector item |
| Client token sync (passenger) | Generic `DeviceTokenRemoteDataSource` + passenger sync hook; small client diff | ~0.5 day |
| Tests | `delivery_ride_state.test.ts` mirroring `delivery_d1.test.ts` (~10 cases) + 1 client parse test | ~1 day |

**Total: ~3–4 dev-days** plus a staging redeploy once billing is restored.
Hard dependency before any of it runs end-to-end: GCP billing re-link (same
blocker as staging outage — project `ora-app-d8112` `billingEnabled: false`).

## Non-goals / safety

- No ride-state semantics changes; push is a hint, HTTP remains SoT.
- No new paid services — FCM send is already used by D1.
- No background-fetch or payload-driven UI — identifiers only.
- Volume: rides are low-frequency events (≤ ~15 pushes/ride lifecycle ×2
  actors) — negligible vs dispatch invites.

## Implementation record (2026-10-19)

Shipped exactly as designed:

- `src/delivery/ride_state_types.ts` — `RS_EVENT_TYPES` closed Set (13 types),
  `PASSENGER_DEVICE_TOKENS` collection, `RS_SUBSCRIBER='fcm_ride_state'`,
  `rsDeliveryDocId`, `passengerTokenDocId`; reuses D1 lease/attempt constants.
- `src/delivery/ride_state_fcm_projector.ts` — `RideStateFcmProjector` mirrors
  D1 1:1 (PENDING-first scan via `eventType in allowlist`, expired-lease
  reclaim, `(leaseOwner, attemptCount)` CAS fencing on delivery + event docs,
  per-uid/per-token durable results, exponential backoff, dead-letter at 10
  attempts, invalid-token removal). Sends `{type:'RIDE_UPDATE', rideId,
  eventId}` only. Recipients resolved server-side from `rides/{id}`
  (+`rideOffers/{id}` fallback for `offer.selected`); a uid's tokens are the
  union of `driverDeviceTokens` + `passengerDeviceTokens` (store-tagged so
  invalid tokens are deleted from the right collection).
- `src/delivery/device_token_service.ts` — added `registerPassenger` /
  `clearPassenger` / `listTokensForPassenger` / `deletePassengerTokenByValue`
  (gate: `role=='passenger'`; uid from verified caller only). Driver methods
  unchanged.
- `src/routes/device_tokens.ts` + `app.ts` — `POST/DELETE /v1/device-tokens`
  for passengers, behind `requireAuth` + rate limit.
- `src/routes/internal.ts` — `POST /v1/internal/outbox/ride-state-fcm-sweep`,
  same `X-Ora-Worker-Token` middleware + `?limit` shape as dispatch sweep.
- `scripts/wire_staging_cloud_scheduler.sh` — added
  `ora-staging-worker-ride-state-fcm-sweep` + `*/1 * * * *` scheduler entry
  (script edited, **not run** — billing still disabled).
- Client — `DriverDeviceTokenRemoteDataSource.registerPassengerToken` +
  `DispatchFcmService.syncPassengerTokenRegistration` (token-refresh re-uses
  the last role's path), invoked post-frame from `HomeShellView` when
  `profile.role=='passenger'`; cleared on sign-out.

**Tests:** `src/__tests__/delivery_ride_state.test.ts` — 17 cases (passenger
token CRUD + 403 role gates + spoof rejection; assigned→both, arrived→
passenger-only, completed/cancelled→both; offer.selected offer-doc fallback;
non-allowlisted events skipped; no-token → SKIPPED_NO_TOKEN; duplicate →
already_done no resend; non-recipient never receives; invalid_token removed;
transient → retry then only failed token resent; dead-letter at max attempts;
active-lease skip; PENDING-first sweep; endpoint auth 403 + worker 200).
Plus 1 client parse test for the canonical `RIDE_UPDATE` payload.
Backend suite: 457 pass. `tsc --noEmit` clean. `flutter analyze lib/` clean.

**Not done (explicit):** no staging/cloud deploy, no scheduler run, no live
FCM push observed on a device — end-to-end remains unverified until billing
is restored and the service redeploys.
