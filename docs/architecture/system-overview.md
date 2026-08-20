# ORA — System Overview

## Architecture Philosophy

Ora uses a **server-authoritative, event-driven architecture** with a clear separation between:

1. **Flutter client** — MVVM Views render state and send intents; ViewModels call use cases; never owns truth
2. **Cloud Run API** — validates, authorizes, transitions state
3. **Firestore** — durable source of truth for rides, offers, assignment, payments, ledger
4. **RTDB** — ephemeral, high-frequency realtime data (presence, GPS, pending request cards)
5. **Redis** — GEO index, optional select-contention lock, dispatch caches — never assignment authority
6. **Pub/Sub** — async decoupled events (analytics, notifications, background jobs)

Product model: P2P offered-fare marketplace. Recommended fare is guidance. Drivers create offers. Passenger selection assigns. See `docs/algorithms/offer-model.md`.

## Component Interaction Diagram

```
Flutter App
│
├── Firebase Auth SDK → validates with Firebase Auth Service
│
├── HTTPS → Cloud Run API (+ App Check header + JWT Bearer)
│   │
│   ├── → Firestore (Admin SDK — read/write ride documents)
│   ├── → Redis Memorystore (GEO queries, SETNX locks, dedup)
│   ├── → Google Maps APIs (Routes, Geocoding, Distance Matrix)
│   ├── → Pub/Sub (publish ride events)
│   └── → RTDB Admin SDK (presence updates, signal writes)
│
├── Firestore SDK (listener) → receives ride state changes
│
├── RTDB SDK (listener) → receives driver location, assignment signals
│
└── FCM SDK → receives push fallback notifications

Pub/Sub Consumers (Cloud Run):
├── Notification Dispatcher → FCM bulk send
├── Analytics Sink → BigQuery
├── Ride Expiry Worker → scans + expires stale rides
└── Bonus Calculator → periodic earnings computation
```

## Key Design Decisions

### Why Cloud Run over Cloud Functions?
- Predictable latency: Cloud Run supports min-instances (keep-warm)
- Better for long-running HTTP handlers (offer create / passenger select)
- Easier local development and Docker-based testing
- Better cold-start control

### Why RTDB for GPS, not Firestore?
- RTDB supports 1-second update cycles without cost explosion
- RTDB fan-out is faster for single-document high-freq updates
- Firestore 1/s write limit per document is a hard constraint
- RTDB data is ephemeral and doesn't need ACID guarantees

### Why Redis for locking, if Firestore is authoritative?
- Redis `SETNX` is an optional O(1) contention reducer on **passenger select**
- It is **not** taken on driver Accept (Accept is not assignment)
- It does NOT replace Firestore transactional state validation
- Firestore remains the authoritative assignment barrier

### Why Pub/Sub?
- Decouples ride events from notification delivery
- Allows retry of failed FCM sends without blocking the ride flow
- Enables analytics pipeline without synchronous overhead
- Enables future webhook integrations

### Why an outbox?
- Firestore commit is not atomic with RTDB, Pub/Sub, or FCM
- Durable outbox records make side effects retryable and auditable
