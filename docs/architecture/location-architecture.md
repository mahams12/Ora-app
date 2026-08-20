# ORA — Location Architecture

## GPS Sampling Strategy

| Mode | Interval | Distance Filter | Accuracy | Battery Priority |
|---|---|---|---|---|
| Idle driver (online, no ride) | 5 seconds | 20 meters | BALANCED | LOW |
| Searching (waiting for request) | 5 seconds | 10 meters | BALANCED | LOW |
| En route to pickup | 2 seconds | 5 meters | HIGH | MEDIUM |
| Active trip (driving passenger) | 1 second | 5 meters | BEST | HIGH |
| Background (app not focused) | Transistor BGGeo stationarity-aware | — | — | ADAPTIVE |
| Passenger (reading only) | N/A (RTDB listener) | N/A | N/A | NONE |

## Accuracy Thresholds

| Condition | Action |
|---|---|
| Horizontal accuracy > 50m | Discard fix; do not upload |
| Horizontal accuracy > 20m (active trip) | Upload with `lowAccuracy: true` flag; warn UI |
| Speed > 200 km/h | Flag as suspicious; server validates |
| Heading change > 180° in < 1s | Discard heading; interpolate |
| GPS disabled | Show in-app warning; log `GPS_UNAVAILABLE` event |
| GPS fix age > 15 seconds | Treat as stale; mark `staleLocation: true` |

## Location Update Payload

```json
{
  "rideId": "abc123",
  "driverId": "drv456",
  "locationSeq": 142,
  "locationStreamId": "locstream_01JABC",
  "lat": 31.5204,
  "lng": 74.3587,
  "accuracy": 8.5,
  "heading": 245.0,
  "speed": 35.2,
  "altitude": 217.0,
  "timestamp": "2026-08-18T07:30:00.000Z",
  "provider": "gps"
}
```

## Server-Side Validation

```
POST /v1/location/update

Validation checks:
1. JWT valid (authenticated driver)
2. `locationSeq` > last accepted `locationSeq` for this `rideId + driverId + locationStreamId`
3. timestamp within [now - 15s, now + 5s] (clock skew tolerance)
4. accuracy <= 50m
5. speed <= 200 km/h
6. lat/lng within Pakistan bounding box (soft check; warn on violation)
7. Distance from last point plausible given time elapsed and speed

If all pass:
  → GEOADD redis geo:drivers:{city} {lng} {lat} {driverId}
  → RTDB write: tripLocations/{rideId}/latest = {location}
  → RTDB write: tripLocations/{rideId}/recent/{eventSequence} = {location}  // bounded recent history
  → Update driver's lastLocationTs in Redis

If fail:
  → Log rejection reason with requestId
  → Return 422 with rejection reason
  → Do NOT update GEO index with bad data
```

## Kalman Filter (GPS Smoothing)

Applied client-side in Dart before upload, and server-side for trip reconstruction.

```
// One-dimensional Kalman for lat and lng separately
// State: position
// Measurement noise: accuracy^2 (meters^2)
// Process noise: speed * dt (movement model)

Q = (speed * dt)^2    // process noise
R = accuracy^2        // measurement noise
K = P_prev / (P_prev + R)
position = position_prev + K * (measurement - position_prev)
P = (1 - K) * P_prev + Q
```

This prevents GPS "jumps" from satellite multipath or momentary fix errors.

## Out-of-Order Packet Prevention (Passenger Rendering)

```dart
// In Flutter passenger map widget:
int _lastRenderedLocationSeq = 0;
String? _lastStreamId;

void onLocationUpdate(LocationUpdate update) {
  if (_lastStreamId != null && update.locationStreamId != _lastStreamId) {
    // New accepted stream, reset only after authoritative server transition.
    _lastRenderedLocationSeq = 0;
  }

  if (update.locationSeq <= _lastRenderedLocationSeq) {
    return;
  }

  _lastStreamId = update.locationStreamId;
  _lastRenderedLocationSeq = update.locationSeq;
  _renderDriverMarker(update.lat, update.lng, update.heading);
}
```

**Rule:** Driver marker on passenger map NEVER moves backward.  
**Implementation:** Monotonic GPS sequence enforced per ride-stream on both client and server. This sequence is independent from ride aggregate version and durable event ordering.

## Heading / Marker Animation

```dart
// Smooth car marker rotation
void animateHeading(double fromHeading, double toHeading) {
  // Handle 359° → 1° wrap-around
  double delta = toHeading - fromHeading;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  
  // Animate over 500ms
  _headingController.animateTo(fromHeading + delta, duration: 500ms);
}
```

## Background Location Policy

### Android
- Use `flutter_background_geolocation` (Transistor) or `WorkManager` + `ForegroundService`
- Show persistent notification: "Ora is using your location to navigate"
- REQUEST_BACKGROUND_LOCATION permission (Android 10+)
- Comply with Google Play background location policy (only for driver during active trip)

### iOS
- Core Location `allowsBackgroundLocationUpdates = true`
- `UIBackgroundModes: location` in Info.plist
- Significant location change mode for idle driver
- Full accuracy for active trip
- App Tracking Transparency not required for navigation use case

## Stale Driver Handling (Server)

```
Cloud Scheduler (every 30 seconds):

1. Query Redis: all drivers with lastLocationTs < (now - 15s)
2. For each stale driver:
   a. Mark RTDB driverPresence/{uid}/stale = true
   b. Remove from Redis GEO index
   c. If driver has active ride: log GPS_STALE event; notify passenger
3. After 60s without location: mark driver offline in RTDB
```

## Privacy & Retention

| Data | Retention | Access |
|---|---|---|
| RTDB tripLocations.latest | Deleted after ride completes (server cleanup) | Server + authorized ride participants only |
| RTDB tripLocations.recent | Bounded recent history; deleted after ride completes | Server + authorized ride participants only |
| Redis GEO index | Auto-expires (driver goes offline or staleness sweep) | Server only |
| Firestore rideLocations summary | 7 days | Server + admin |
| Anonymized route analytics | 90 days | Analytics pipeline |
| Driver location history | NEVER stored (real-time only) | N/A |

## Trust Clarification

- Client-provided GPS is untrusted input.
- App Check is not a proof of location honesty.
- Kalman filtering smooths jitter; it is not a security mechanism.
