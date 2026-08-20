# ADR-012: API and Event Contract Versioning

## Status
Accepted / Locked.

## Decision
HTTP API is versioned via URL prefix (`/v1/...`).
Durable events embed `schemaVersion` in the outbox envelope.
Clients must ignore unknown fields and reconcile correctness from durable state.

