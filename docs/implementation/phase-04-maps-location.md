# Phase 4 — Maps & Location

**Status:** NOT STARTED (full Maps polish) — **4A IN PROGRESS / shipping**  
**Dependencies:** Auth/ride baseline CLOSED; see CURRENT_STATE  
**Decision freeze (authoritative):** [`phase-4-5-location-pricing-decision.md`](phase-4-5-location-pricing-decision.md)

> **2026-09-22:** **Phase 4A** = passenger GPS + Places search + confirm → real lat/lng in Ride Request capabilities. Map-pin / Maps SDK / Routes / pricing are **out of scope** for 4A.

## Phase 4A — GCP / build setup (required for device Places)

1. Google Cloud project (same as Firebase `ora-app` if possible).
2. Enable **Places API (New)** only for 4A (not Routes yet).
3. Create an API key restricted to **Places API (New)**.
   - For Flutter HTTP Places calls, Android package+SHA restriction does **not** apply the same way as native Maps SDK keys. Prefer API restriction + monitor quotas; rotate if leaked.
4. Build / run with:
   ```bash
   flutter run --dart-define=ORA_GOOGLE_PLACES_API_KEY=YOUR_KEY \
     --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8080/v1 \
     --dart-define=ORA_ALLOW_HTTP_API=true
   ```
5. Android permissions: `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` (manifest).
6. Do **not** put Routes/server keys in the Flutter app.

## Objectives

Google Maps rendering, GPS, autocomplete, route polylines, ETA, driver heading.

## Key Implementation Points

- Maps SDK initialized only when entering map screen (deferred)
- Custom dark map style loaded from `assets/map_style.json`
- API keys in `google-services.json` / `GoogleService-Info.plist` only; restricted by package + API
- Geocoding and Routes calls: server-side only
- Autocomplete: Places SDK with session tokens
- GPS: geolocator + Transistor BGGeo for background
- Kalman filter in Dart isolate for GPS smoothing
- Sequence number on every location update
- Location update sent to `POST /v1/location/update` (driver only)
- Passenger reads driver location from RTDB (never writes to RTDB)

## Acceptance Criteria

- [ ] Map renders in < 1.5s on mid-range Android
- [ ] User location shown with correct marker
- [ ] Custom dark map style applied
- [ ] Autocomplete returns results; session token used
- [ ] Route polyline renders between two points
- [ ] ETA displayed from Google Routes API response
- [ ] Driver marker rotates with heading
- [ ] GPS updates at correct intervals (foreground: 2s; idle driver: 5s)
- [ ] Stale location detection (> 8s without update) shows warning
- [ ] GPS accuracy > 50m → update rejected
- [ ] Out-of-order GPS packet test: marker never moves backward
- [ ] Battery test: < 5% per hour in idle mode (on real device)
- [ ] Integration test: stale location detection
- [ ] Integration test: accuracy rejection
