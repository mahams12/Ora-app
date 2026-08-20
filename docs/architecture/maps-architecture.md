# ORA — Maps Architecture

## Google APIs Used

| API | Purpose | Called By | Billing Note |
|---|---|---|---|
| Maps SDK (Mobile) | Tile rendering, markers, polylines | Flutter client | Per map load (use map ID to enable billing alerts) |
| Places Autocomplete | Destination search | Flutter client (session token) | Per session; use session tokens to batch |
| Geocoding API | lat/lng ↔ address | Server only | Per request |
| Directions API | Route + polyline | Server (Pricing Service) | Per request |
| Routes API (preferred) | Route + ETA + traffic | Server (Pricing Service) | Per request |
| Distance Matrix API | ETA for multiple drivers | Server (Matching Engine) | Per element |
| Maps Static API | N/A (use Flutter SDK) | N/A | — |

## API Key Security

- Flutter client: Maps SDK key — restricted to `com.ora.app` package + SHA fingerprints + Maps SDK only
- Flutter client: Places key — restricted to `com.ora.app` + Places API only
- Server keys: Full API access — stored in Secret Manager; NEVER in client code
- Keys rotated if ever exposed

## Custom Map Style

Ora uses a custom dark-navy map style matching the app's design system:

```json
// map_style.json — loaded at runtime
[
  { "elementType": "geometry", "stylers": [{ "color": "#1B2340" }] },
  { "elementType": "labels.text.fill", "stylers": [{ "color": "#A8AEBF" }] },
  { "featureType": "road", "elementType": "geometry", "stylers": [{ "color": "#2A334D" }] },
  { "featureType": "road.highway", "elementType": "geometry", "stylers": [{ "color": "#3A4560" }] },
  { "featureType": "water", "stylers": [{ "color": "#0B0F1C" }] },
  { "featureType": "poi", "stylers": [{ "visibility": "off" }] }
]
```

## Polyline Rendering

```dart
// Route polyline — decoded from Google encoded polyline
Set<Polyline> buildPolylines(String encodedPolyline) {
  final points = PolylinePoints().decodePolyline(encodedPolyline)
    .map((p) => LatLng(p.latitude, p.longitude))
    .toList();
    
  return {
    Polyline(
      polylineId: const PolylineId('route'),
      color: const Color(0xFFD4A756), // Ora gold
      width: 4,
      points: points,
      patterns: [], // solid line for active route
    ),
  };
}
```

## ETA Calculation

- Primary: Google Routes API `travelAdvisory.transitFare` + `duration` field
- Traffic-aware: `routingPreference: TRAFFIC_AWARE`
- ETA shown to passenger: dynamic, updated as driver moves
- ETA calculation for matching: Distance Matrix API called server-side for top 5 candidates

## Driver Marker Rendering

```dart
// Custom car marker with heading rotation
Future<BitmapDescriptor> buildCarMarker(double heading) async {
  final icon = await BitmapDescriptor.fromAssetImage(
    ImageConfiguration(size: Size(48, 48)),
    'assets/icons/car_marker.png',
  );
  return icon; // rotation handled via MarkerOptions.rotation
}

Marker driverMarker(DriverLocation loc) {
  return Marker(
    markerId: const MarkerId('driver'),
    position: LatLng(loc.lat, loc.lng),
    rotation: loc.heading,
    anchor: const Offset(0.5, 0.5),
    flat: true, // rotates with map
    icon: _carIcon,
  );
}
```

## Camera Management

```dart
// Auto-zoom to fit both pickup and driver
void fitBounds(LatLng driverPos, LatLng pickupPos) {
  final bounds = LatLngBounds(
    southwest: LatLng(
      min(driverPos.latitude, pickupPos.latitude),
      min(driverPos.longitude, pickupPos.longitude),
    ),
    northeast: LatLng(
      max(driverPos.latitude, pickupPos.latitude),
      max(driverPos.longitude, pickupPos.longitude),
    ),
  );
  _mapController.animateCamera(
    CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding
  );
}
```

## Places Autocomplete Strategy

- Use `flutter_google_places_sdk` with session tokens
- Session token created when user taps destination field
- Session ends when user selects a place (charges one session request, not per keystroke)
- Bias results to current city using `locationBias`
- Cache last 5 results in Hive for offline/retry

## Map Performance

- `lite: false` (full interactive mode required)
- Initial camera position: user's current city (from profile)
- Markers: only driver + pickup + destination (max 3 on home; more for hot zones)
- Avoid rebuilding map widget on every state change — use `GoogleMapController` methods
- Map controller operations on main isolate only
- Map tile caching: default 50MB; consider 100MB for repeat-user battery saving
