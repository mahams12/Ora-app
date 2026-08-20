# ORA — Testing Strategy

## Principle

**No feature is marked complete without an executable test proving it.**

Tests are not optional. They are part of the definition of done for every phase.

## Test Pyramid

```
         ┌─────────┐
         │   E2E   │  (2 physical devices — Phase 13)
         │  (few)  │
        ┌┴─────────┴┐
        │Integration │  (Emulator suite — Phase 13)
        │ (moderate) │
       ┌┴───────────┴┐
       │  Unit Tests  │  (Every phase — written alongside code)
       │   (many)     │
       └──────────────┘
```

## Unit Tests

### Fare Engine

```dart
// test/algorithms/fare_engine_test.dart

test('Easy category Lahore — 5.8km, 14min, no demand surge', () {
  final result = FareEngine.calculate(
    distanceKm: 5.8, durationMin: 14, category: Category.easy,
    city: 'lahore', demandMultiplier: 1.0, isNight: false,
    tollsRs: 0, airportFeeRs: 0,
  );
  expect(result.recommendedFare, equals(340));
  expect(result.allowedMin, equals(238));   // 0.70 × 340
  expect(result.allowedMax, equals(850));   // 2.50 × 340
});

test('Night adjustment applies between 23:00 and 05:00', () { ... });
test('Demand multiplier clamped to max 1.8', () { ... });
test('Min fare floor enforced for short trips', () { ... });
test('Fare rounded to nearest Rs 10', () { ... });
test('Airport fee added for airport destination', () { ... });
test('Intercity fare uses flat + per-km (no per-minute)', () { ... });
```

### Ride State Machine

```dart
// test/state_machine/ride_state_machine_test.dart

test('SEARCHING → DRIVER_ASSIGNED allowed', () { ... });
test('RIDE_CLOSED → SEARCHING forbidden', () {
  expect(() => stateMachine.transition(
    from: RideState.completed, to: RideState.searching,
  ), throwsA(isA<ForbiddenTransitionError>()));
});
test('Only server actor can assign driver', () { ... });
test('Version increments on every transition', () { ... });
test('Idempotent transition returns same result', () { ... });
```

### Location Validation

```dart
test('Accuracy > 50m rejected', () { ... });
test('Out-of-order seq discarded', () { ... });
test('Speed > 200 km/h flagged', () { ... });
test('Timestamp > 15s old rejected', () { ... });
test('Kalman filter smooths jumpy GPS', () { ... });
test('Backward marker movement never occurs', () { ... });
```

### Authorization

```dart
test('Passenger cannot write ride state', () { ... });
test('Driver cannot accept unrelated ride', () { ... });
test('Admin can force-transition any ride', () { ... });
test('App Check failure returns 403', () { ... });
test('Expired JWT returns 401', () { ... });
```

### Idempotency

```dart
test('Duplicate accept returns same 409', () { ... });
test('Duplicate create returns same rideId', () { ... });
test('Pending idempotency key returns 202', () { ... });
```

## Integration Tests

Run against Firebase Emulator Suite (Auth, Firestore, RTDB, Pub/Sub emulators).

### Passenger → Request Flow

```
1. Create user with phone OTP
2. POST /pricing/estimate → get pricingSnapshot
3. POST /rides → verify state = SEARCHING
4. Verify ride appears in Firestore
5. Verify dispatch:notified Redis key created
6. Verify RTDB rideRequests/{driverId}/pending/{rideId} written
```

### Driver → Offer Flow

```
1. Create driver (approved)
2. Go online → verify Redis GEO entry
3. Receive ride request (RTDB listener)
4. POST /rides/{id}/offers  (PASSENGER_PRICE_ACCEPTED or DRIVER_COUNTEROFFER)
5. Verify offer PENDING; ride is OFFERS_AVAILABLE; assignedDriverId is null
6. Passenger POST /rides/{id}/offers/{offerId}/select
7. Verify state = DRIVER_ASSIGNED and agreedFareMinor set
8. Verify RTDB remaining pending cards deleted
```

### 3-Driver Offer Test

```dart
test('Three concurrent accepts create three pending offers, not one assignment', () async {
  final rideId = await createRide(passenger: passengerA);
  await notifyDrivers([driverA, driverB, driverC]);

  final results = await Future.wait([
    postOffer(driverId: 'driverA', rideId: rideId),
    postOffer(driverId: 'driverB', rideId: rideId),
    postOffer(driverId: 'driverC', rideId: rideId),
  ]);

  expect(results.where((r) => r.statusCode == 201).length, equals(3));

  final ride = await getRide(rideId);
  expect(ride.assignedDriverId, isNull);
});
```

See `docs/testing/race-condition-tests.md` for concurrent **select** (exactly one assignment).

### Offline / Reconnect Tests

```
test('Passenger reconnects; sees correct DRIVER_EN_ROUTE state')
test('Driver reconnects; ride assignment still valid')
test('RTDB listener reattaches after network loss')
test('Stale ride card disappears on reconnect')
test('No duplicate offer after reconnect')
```

### GPS Failure Tests

```
test('GPS disabled — driver shown warning; not forced offline')
test('GPS inaccurate (>50m) — updates rejected; last good position used')
test('GPS stale (>8s) — passenger shown warning')
test('GPS resumes — marker updates correctly')
test('Out-of-order GPS packets — marker never moves backward')
```

## End-to-End Tests (2 Physical Devices)

### Device Matrix

| Device | Role | OS |
|---|---|---|
| Device A | Passenger | Android (Pixel 7) |
| Device B | Driver | Android (Samsung A-series, mid-range) |
| Optional C | Second driver for race test | Any Android |

### E2E Test Suite

```
Scenario 1: Happy Path
  1. Passenger creates account (OTP)
  2. Driver creates account; completes onboarding
  3. Admin approves driver documents
  4. Passenger requests ride (Easy, Rs 340)
  5. Driver receives request on Device B ← verify with eyes
  6. Driver accepts
  7. Passenger sees "Moin Sultan, 4 min away" ← verify
  8. Driver drives to pickup (simulated GPS path)
  9. Driver taps Arrived
  10. Passenger sees "Driver arrived" notification
  11. Passenger boards; driver taps Start Ride
  12. Live map shows driver moving ← verify marker movement
  13. Driver arrives at destination; taps End Ride
  14. Receipt shown on both devices ← verify totals match
  15. Both rate each other
  
Scenario 2: 3-Driver Race
  Device A = Passenger
  Devices B, C, D = 3 Drivers
  All 3 simultaneously tap Accept
  Expected: exactly 1 driver assigned; others see "Taken"
  
Scenario 3: Driver Cancellation
  Driver cancels post-assignment
  Passenger sees cancellation notification
  Ride returns to SEARCHING (if within re-search window)
  
Scenario 4: Passenger Cancellation
  Passenger cancels during DRIVER_EN_ROUTE
  Driver sees cancellation notification
  Cancellation fee calculated correctly
  
Scenario 5: Network Loss — Passenger
  Passenger loses internet during DRIVER_EN_ROUTE
  Passenger reconnects: sees correct driver position
  No duplicate state shown
  
Scenario 6: Network Loss — Driver
  Driver loses internet during RIDE_STARTED
  Driver reconnects: trip still active
  GPS resumes; passenger sees updated position
  
Scenario 7: Expired Ride
  Passenger creates ride at 11 PM in low-demand area
  No drivers available
  After 5 minutes: ride expires
  Passenger sees "No drivers found"
```

## Failure Test Checklist

```
□ Passenger loses internet (SEARCHING)
□ Passenger loses internet (DRIVER_EN_ROUTE)
□ Driver loses internet (DRIVER_EN_ROUTE)
□ App backgrounded during RIDE_STARTED
□ App killed; relaunched; shows correct state
□ GPS disabled — driver side
□ GPS inaccurate (50m+ error)
□ Duplicate accept from same driver (network retry)
□ Simultaneous accept from 3 drivers
□ Stale accept (driver accepts 1 second after assignment)
□ Delayed FCM message (FCM arrives 30s late)
□ Out-of-order GPS packet
□ Duplicate FCM message
□ Server timeout during accept
□ Redis unavailable — assignment still correct via Firestore
□ Cloud Run cold start during peak
□ Firestore reconnect after 30s offline
□ RTDB reconnect after 30s offline
□ Payment failure — cash fallback
□ Driver and passenger cancel simultaneously
□ Ride expires while passenger is offline
□ Driver no-show timer fires
□ Pricing snapshot expires before ride creation
□ Invalid fare offer (too low, too high)
```

## Coverage Targets

| Area | Target |
|---|---|
| Fare engine | ≥ 95% branch coverage |
| Ride state machine | 100% transition coverage |
| Authorization logic | 100% rule coverage |
| Location validation | ≥ 90% branch coverage |
| API endpoint handlers | ≥ 80% line coverage |
| Flutter widgets | ≥ 70% (golden tests for critical screens) |
