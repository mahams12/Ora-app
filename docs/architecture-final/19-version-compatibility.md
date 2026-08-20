# Version Compatibility & Schema Evolution

Authoritative sources:
- `docs/api/api-contract.md` (versioning + schema)
- `docs/architecture-review/event-contracts.md` (schemaVersion in envelope)
- `docs/operations/disaster-recovery.md` (feature flags + minimum_app_version)
- `docs/architecture-review/outbox-design.md` (outbox event schemaVersion)

## Version Dimensions

1. **Mobile app version**
   - Sent via `X-Client-Version`.
   - Used to gate features via remote config (minimum_app_version).

2. **API version**
   - Canonical base: `/v1` (and `/v2`).
   - Backward compatibility: old endpoints must remain until deprecation window ends.

3. **Event schema version**
   - Every outbox durable event includes `schemaVersion`.
   - Clients must ignore unknown payload fields and rely on `eventType` + version ordering.

4. **Database schema version**
   - Firestore schema changes must be rolled out in backward-compatible manner:
     - write new fields server-side
     - keep old fields until all clients are updated
     - add indexes with rollout plan

5. **Feature flag version**
   - Remote config values can change behavior without app update.

## Old Client Behaviour

- REST: tolerate unknown fields; do not assume presence of new response fields.
- Realtime: treat out-of-date events as stale via aggregateVersion/eventSequence rules.
- Safety/Payment: never trust “success” based on partial UI; always rely on authoritative Firestore reads.

## Compatibility Rules (Contract)

1. Never remove fields used by old clients until the deprecation window completes.
2. Never change meaning of canonical identifiers (rideId, driverId, offerId).
3. Any semantic change in event payload must bump `schemaVersion` and keep older decoding paths until retirement.

## Phase 1.6 Freeze

Detailed event-schema compatibility behavior is now frozen in:
`docs/architecture-final/24-phase-1.6-condition-closure.md` section 9.

Key rule:
- unknown higher event schema versions must fail safe and trigger authoritative read-repair instead of blindly applying projection data.

