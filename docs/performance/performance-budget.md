# ORA — Performance Budget

## Flutter Anti-Pattern Rules (ENFORCED)

The following are forbidden in production code:

```
❌ Calling API in build()
❌ Synchronous disk I/O on UI isolate
❌ setState() on entire page from child widget
❌ Rebuilding map widget on every GPS update
❌ Using StreamBuilder without distinct filter
❌ Listening to entire Firestore collection without where clause
❌ Polling Firestore in a Timer (use listeners)
❌ Loading all ride history at once (no pagination)
❌ Blocking main isolate with JSON parsing (use compute())
❌ Creating new objects on every build() call
❌ Unbounded ListView without ListView.builder
❌ Expensive operations in initState() without async
```

## Widget Build Budget

| Widget | Max build time | Strategy |
|---|---|---|
| Home screen | < 4ms | Const constructor for static sections |
| Ride category card | < 1ms | `const` widget; no state |
| Driver info card | < 2ms | `select()` on only needed fields |
| Map screen | < 3ms | Separate StatefulWidget; never rebuilt by parent |
| Live trip sheet | < 2ms | `ConsumerWidget` watching `activeRideProvider.select(...)` |
| Driver request card | < 2ms | Const where possible |

## Riverpod Rebuild Control

```dart
// BAD — rebuilds on ANY ride field change
final ride = ref.watch(activeRideProvider);

// GOOD — rebuilds only when state changes
final state = ref.watch(activeRideProvider.select((r) => r?.state));

// GOOD — rebuilds only when driver position changes
final driverLoc = ref.watch(driverLocationProvider);
// (driverLocationProvider is a separate provider from ride state)
```

## Memory Budget

| Item | Budget |
|---|---|
| Images (profile, vehicle) | Loaded on demand; cached 10MB in memory |
| Map tiles | 50MB disk cache (Flutter Google Maps default) |
| Hive local cache | < 5MB (recent rides, saved places, settings) |
| Encrypted store | < 1MB (tokens, emergency contacts) |
| In-memory ride state | < 100KB (one active ride at a time) |

## Battery Budget (per use case)

| Mode | Target battery drain per hour |
|---|---|
| App in background (idle driver) | < 3% per hour |
| Foreground searching | < 5% per hour |
| Active trip (1 hour drive) | < 8% per hour |
| Passenger (not on trip) | < 1% per hour |

Measured on Samsung Galaxy A-series (mid-range, 4000 mAh battery).

## Startup Optimization Checklist

```
□ Deferred imports for heavy screens (intercity, move, driver onboarding)
□ Lazy loading: home screen first; other tabs on demand
□ Firebase initialization: call before runApp(); async
□ Map SDK: initialize only when entering map screen
□ Hive: open boxes in background isolate
□ Token refresh: background; doesn't block splash
□ Fonts: preloaded via pubspec.yaml; no runtime fetch
□ Images: WebP format; 2x only (no 3x for current target devices)
```

## Frame Jank Prevention

```dart
// Route polyline decoding — do NOT do this on main isolate
// BAD:
final points = PolylinePoints().decodePolyline(longPolyline);

// GOOD:
final points = await compute(decodePolyline, longPolyline);

// GPS Kalman filter — use compute() for active computation
final smoothed = await compute(applyKalmanFilter, rawLocations);
```

## Firestore Read Optimization

```
Read budget per cold session: < 20 reads

Caching strategy:
- Pricing rules: cached 1 hour in Hive
- User profile: cached 24 hours; invalidated on profile update
- Saved places: cached 24 hours; invalidated on save/delete
- Active ride: real-time listener (free after first snapshot)
- Ride history: paginated (10 per page); no prefetch

Forbidden:
- Re-reading ride document on every GPS update
- Reading all drivers' profiles during matching
- Fetching full ride history without pagination
```
