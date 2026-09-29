# Phase Template

**Status:** CURRENT  
**Use for:** N3, N4, and all later implementation phases.  
**Do not** mark a phase CLOSED without filling Exit Criteria with real proof commands and results.

Copy this file to `docs/implementation/...` (or `docs/implementation/n-series/...`) and fill every section.

---

# Phase

`N3` / `2X` / etc.

## Objective

One sentence: what capability ships.

## Problem

Why this phase exists (user/system failure without it).

## Preconditions

- Prior phases CLOSED (list with evidence links)
- Infra available (Firestore emulator, Redis, etc.)
- Decision freeze path

## Read-Only Audit

What was inspected before coding (routes, collections, conflicting docs).  
List DOCUMENTATION ↔ CODE MISMATCH items found.

## Architecture Decision

Pointers to ADRs / freezes. What is SoT vs projection.

## Frozen Contract

Bullet list that must not change mid-implementation without a new freeze:

- Authz
- Request/response DTOs
- Error codes
- Idempotency
- City / geo rules (if applicable)

## Data Model

Collections/keys written or read. Authoritative vs ephemeral.

## API Contract

Method, path, headers, body, success, errors.

## Implementation Files

Exact paths (do not paste large code).

## Tests

Unit / Vitest paths.

## Live Proof

Command + environment (emulator / Redis). Result: PASS | NOT RUN | BLOCKED | N/A.

## Security

Rules, IDOR, App Check, worker tokens.

## Failure Modes

Dependency down, partial writes, retries.

## Observability

`logSafe` event names.

## Regression

Which prior phase proofs must still pass.

## Known Limitations

Honest gaps.

## Explicit Non-Goals

What this phase must **not** implement.

## Exit Criteria

Checklist that defines CLOSED.

## Next Dependency

Exact next phase name + blockers.

## Failure Entry Points

```text
HTTP xxx
→ layer
→ file
→ test/proof
```
