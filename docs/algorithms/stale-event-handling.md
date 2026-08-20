# ORA — Stale Event Handling

## Problem

In a distributed realtime system, events can arrive:
- Out of order (network buffering)
- Duplicated (retry on failure)
- Delayed (network congestion)
- After a state transition has already occurred

Applying a stale event can cause:
- Backward marker movement on map
- Wrong state displayed to user
- Duplicate notifications
- Assignment of an already-assigned ride

## Defense Strategy: Sequence Numbers + Version Numbers

### Two separate counters

| Counter | Scope | Increments On | Used For |
|---|---|---|---|
| `rideVersion` | Per ride aggregate | Every authoritative ride state transition | Ride state concurrency and stale rejection |
| `eventSequence` | Per projected signal stream | Every projected durable event | Signal ordering |
| `locationSeq` | Per GPS stream (per driver per ride-stream) | Every location update | Location staleness |

### Rule: Monotonic Discard

A client or server MUST discard any event where:
```
incomingRideVersion < localRideVersion
incomingRideVersion == localRideVersion && incomingEventSequence <= lastAppliedEventSequence
incomingLocationSeq <= lastRenderedLocationSeq
```

### Implementation: GPS Out-of-Order

```dart
// In passenger MapProvider (Riverpod)
class DriverLocationNotifier extends AutoDisposeNotifier<DriverLocation?> {
  int _lastSeq = 0;
  
  void onRtdbUpdate(Map<String, dynamic> rawEvent) {
    final seq = rawEvent['locationSeq'] as int;
    
    if (seq <= _lastSeq) {
      // Stale or duplicate — discard
      debugPrint('[Location] Discarding stale seq $seq (last: $_lastSeq)');
      return;
    }
    
    _lastSeq = seq;
    state = DriverLocation.fromJson(rawEvent);
  }
}
```

### Implementation: Ride State Out-of-Order (Firestore Listener)

Firestore snapshot listeners are authoritative for ride aggregate state.  
If the app reconnects after offline, it receives the latest snapshot and treats it as current truth.

For RTDB signals (which supplement Firestore):

```dart
void onRideSignal(Map<String, dynamic> signal) {
  final incomingVersion = signal['aggregateVersion'] as int;
  final incomingEventSequence = signal['eventSequence'] as int;
  final localVersion = _currentRide?.version ?? 0;
  
  if (incomingVersion < localVersion) {
    return;
  }

  if (incomingVersion == localVersion &&
      incomingEventSequence <= _lastAppliedEventSequence) {
    // Discard — Firestore already has more recent state
    return;
  }
  
  // Signal indicates new state; re-read Firestore for authoritative version
  _rideRepository.refreshRide(rideId);
}
```

Always treat RTDB signals as a **wake-up call** to re-read Firestore, not as the authoritative state.

## Duplicate Event Deduplication

### FCM Duplicate Messages

FCM can deliver a message more than once (best-effort delivery, not exactly-once).

```dart
// In FCM message handler
final Set<String> _processedMessageIds = {};

void onFCMMessage(RemoteMessage message) {
  final messageId = message.messageId;
  if (_processedMessageIds.contains(messageId)) {
    return; // Duplicate FCM message — discard
  }
  _processedMessageIds.add(messageId);
  // Process message...
}
```

Cache is in-memory (ephemeral across restarts — that's acceptable; duplicates within a session are the main concern).

### Duplicate Driver Accept (Idempotency)

```
Driver sends Accept, network drops, driver resends.

Server:
1. Check Redis: idempotency:{rideId}:{driverId}:{nonce}
2. If exists and result = "ASSIGNED": return 200 (idempotent success)
3. If exists and result = "CONFLICT": return 409 (idempotent conflict)
4. If not exists: process normally

Nonce is included in the original request and repeated on retry.
This ensures even multiple retries produce the same logical outcome.
```

## Timestamp Validation

Every location update carries a timestamp. Server validates:

```
abs(update.timestamp - server.now) < 15_000ms

If clock skew > 15s: reject update with 422 INVALID_TIMESTAMP
```

This prevents replayed historical locations.

## Stale Ride Card on Driver Screen

```
Scenario: Driver A is looking at request card for Ride #123.
          Passenger cancels the ride.
          
Server action:
  RTDB: rideRequests/{driverA}/pending/123 = null (DELETE)
  
Driver A's RTDB listener fires:
  Card for Ride #123 is removed from UI
  
If Driver A tries to tap Accept anyway (race condition):
  → POST /rides/123/accept arrives at server
  → Ride state is CANCELLED
  → Server returns 409 CONFLICT (ride no longer accepting)
  → Driver UI shows "This ride is no longer available"
```

## Offline Accumulation

When RTDB listener reconnects after offline period, it receives events accumulated during offline.

```
Scenario: Driver was offline 2 minutes.
          During offline, Ride #123 was assigned to Driver B.
          
On reconnect:
  RTDB listener delivers: rideRequests/{driverA}/pending/123 = null (DELETE)
  Driver A's UI: card was already removed during offline reconnect
  
  Even if RTDB event queue didn't deliver (unlikely but possible):
  Driver A can't successfully accept because:
    Redis lock is already gone (expired)
    Firestore state == DRIVER_ASSIGNED
    Server returns 409
```

## Summary: Defense-in-Depth Against Stale Events

| Layer | Mechanism | Protects Against |
|---|---|---|
| Sequence number (GPS) | Client monotonic discard | Backward marker movement |
| Version number (ride) | Client + server version check | Wrong state applied |
| RTDB DELETE signal | Server fan-out on assign | Stale request cards |
| Redis SETNX | One lock wins | Multiple assignment |
| Firestore transaction | Atomic state assertion | Concurrent writes |
| Idempotency key | Result cache | Duplicate retries |
| Timestamp validation | Server clock check | Replayed old events |
