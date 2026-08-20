# ORA — Failure Mode Analysis

## Core Systems

| System | Failure Effect | Correctness Risk | Required Recovery |
|---|---|---|---|
| Flutter client | user cannot send/see updates | low by itself | reconnect and read-repair from Firestore |
| Firebase Auth | no new sign-in / refresh issues | medium availability | use valid cached tokens until expiry; block new auth-sensitive flows |
| Firestore | no authoritative ride mutations | high | disable new rides; preserve reconnection path; reconcile after recovery |
| RTDB | no fast projection / live GPS | medium | Firestore remains truth; degraded live experience |
| Redis | no geo index / less efficient locking | medium availability, low correctness if Firestore barrier exists | degraded mode or partial feature shedding |
| Pub/Sub | async consumers stall | high if no outbox | retry from durable outbox |
| Cloud Run | API unavailable | high availability | restart/scale replacement; retries |
| FCM | background delivery degrades | low correctness | rely on foreground listeners and app-open recovery |
| Google Maps / Places / Routes | estimate / map quality degrades | medium availability | reduced UX, retry, cached/saved-place fallback |
| JazzCash / Easypaisa | digital payment blocked or delayed | high financial operations | pending payment state + reconciliation |

## Key Missing Recovery Mechanisms

1. No durable outbox for Firestore success with downstream signal failure.
2. No explicit reconciliation job for payment attempts vs callbacks vs ledger.
3. No formal stream-resume protocol for GPS sequence after app restart.
4. Redis-outage fallback promises rely on undefined durable structures.

## Disaster Questions

### If Redis is unavailable
- Firestore can still protect assignment correctness.
- Nearby lookup becomes degraded or may need temporary feature shedding.

### If RTDB is unavailable
- ride state is still durable in Firestore
- live location and fast invalidation degrade
- clients need Firestore read-repair

### If Firestore is unavailable
- no authoritative ride creation/assignment
- new rides should be blocked

### If Pub/Sub is delayed
- without outbox, side effects may be lost
- with outbox, they are delayed but recoverable

### If payment callback arrives twice
- dedupe by provider event ID before ledger mutation

### If payment callback never arrives
- payment attempt must remain reconcilable and eventually escalated manually or by polling/requery
