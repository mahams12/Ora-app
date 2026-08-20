# Phase 4 — Maps & Location

**Status:** NOT STARTED  
**Dependencies:** Phase 3

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
