# Phase 9 — Realtime & Atomic Assignment

**Status:** NOT STARTED  
**Dependencies:** Phase 8

## Objectives

Atomic assignment, RTDB invalidation, reconnect handling, stale event rejection.

## Key Implementation Points

- Redis SETNX optional on **select**, not on Accept
- Firestore transaction on selected offer is the assignment barrier
- On assignment: RTDB delete remaining drivers' pending requests
- Passenger Firestore listener fires on ride version change → shows assigned driver
- 3-driver Accept race: 3 pending offers, 0 assignments
- Concurrent select race: exactly 1 assignment
- Duplicate offer create: idempotent
- Select after cancel/expiry: rejected
- Expired offer cannot assign

## Acceptance Criteria

- [ ] **3 concurrent accepts → 3 pending offers, assignedDriverId == null** ← CRITICAL
- [ ] **Concurrent select of two offers, 100 runs × exactly 1 assignment** ← CRITICAL
- [ ] Expired/stale offer select → 422, no assignment
- [ ] Assignment propagates to passenger in < 500ms P95
- [ ] Stale request cards disappear from unselected drivers after assignment
- [ ] 409 ALREADY_ASSIGNED on late offer or losing select
- [ ] Out-of-order GPS packets: marker never moves backward (tested)
- [ ] Passenger reconnects mid-trip: correct state rendered
- [ ] Driver reconnects: RTDB presence re-established in < 5s
- [ ] Offline passenger: sees correct state immediately on reconnect
- [ ] Integration test: duplicate offer same driver (network retry) → idempotent
- [ ] Integration test: offer after ride cancelled → 409 STATE_CONFLICT
