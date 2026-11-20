import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/notifications/dispatch_fcm_service.dart';
import '../core/notifications/ride_fcm_nudge.dart';
import '../features/ride/domain/models/resolved_passenger_location.dart';
import '../features/ride/domain/models/trip_location_latest.dart';
import '../features/ride/domain/ports/place_search_port.dart';
import '../features/ride/domain/ports/pricing_estimate_port.dart';
import '../features/ride/domain/ports/trip_location_port.dart';

/// DEMO/REVIEW BUILD ONLY — local ports so every form works offline.

/// Canned Lahore places — powers pickup/destination autocomplete in the
/// request composer without network access.
class DemoPlaceSearch extends PlaceSearchPort {
  static const _places = <({String id, String name, String area, double lat, double lng})>[
    (id: 'pkg', name: 'Packages Mall', area: 'Walton Road, Lahore', lat: 31.4710, lng: 74.3550),
    (id: 'emp', name: 'Emporium Mall', area: 'Johar Town, Lahore', lat: 31.4697, lng: 74.2728),
    (id: 'dha5', name: 'DHA Phase 5', area: 'DHA, Lahore', lat: 31.4520, lng: 74.4040),
    (id: 'dha3', name: 'DHA Phase 3', area: 'DHA, Lahore', lat: 31.4700, lng: 74.3900),
    (id: 'gul3', name: 'Gulberg III', area: 'Gulberg, Lahore', lat: 31.5100, lng: 74.3450),
    (id: 'ftx', name: 'Fortress Stadium', area: 'Cantt, Lahore', lat: 31.5320, lng: 74.3650),
    (id: 'kalma', name: 'Kalma Chowk', area: 'Main Boulevard, Lahore', lat: 31.4980, lng: 74.3150),
    (id: 'jt', name: 'Johar Town', area: 'Johar Town, Lahore', lat: 31.4697, lng: 74.2728),
    (id: 'mt', name: 'Model Town', area: 'Model Town, Lahore', lat: 31.4830, lng: 74.3220),
    (id: 'apt', name: 'Allama Iqbal Intl Airport', area: 'Cantt, Lahore', lat: 31.5216, lng: 74.4036),
    (id: 'badshahi', name: 'Badshahi Mosque', area: 'Walled City, Lahore', lat: 31.5881, lng: 74.3100),
    (id: 'mm', name: 'Mall of Lahore', area: 'Park Lane, Lahore', lat: 31.5540, lng: 74.3290),
  ];

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    final q = query.trim().toLowerCase();
    return [
      for (final p in _places)
        if (q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            p.area.toLowerCase().contains(q))
          PlaceSuggestion(
            placeId: p.id,
            primaryText: p.name,
            secondaryText: p.area,
          ),
    ];
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    final p = _places.firstWhere(
      (x) => x.id == placeId,
      orElse: () => _places.first,
    );
    return ResolvedPassengerLocation(
      lat: p.lat,
      lng: p.lng,
      source: PassengerLocationSource.place,
      address: '${p.name}, ${p.area}',
      placeId: p.id,
      displayName: p.name,
    );
  }

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async => const ResolvedPassengerLocation(
    lat: 31.4700,
    lng: 74.3550,
    source: PassengerLocationSource.gps,
    address: 'Gulberg III, Lahore',
    displayName: 'Gulberg III',
  );
}

/// Deterministic fare estimate — keeps the composer + fare screen fully
/// explorable without the pricing service.
class DemoPricingEstimate extends PricingEstimatePort {
  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    final base = switch (request.serviceType) {
      'intercity' => 95000,
      'courier' || 'move' => 38000,
      'buy_deliver' => 45000,
      _ => 42000,
    };
    final now = DateTime.now().toUtc();
    return PricingEstimate(
      pricingSnapshotId: 'ps_demo_${now.millisecondsSinceEpoch}',
      recommendedFareMinor: base,
      offerBoundMinMinor: (base * 0.75).round(),
      offerBoundMaxMinor: (base * 1.5).round(),
      currency: 'PKR',
      pricingRulesVersion: 'demo-v1',
      computedAt: now.toIso8601String(),
      expiresAt: now.add(const Duration(minutes: 10)).toIso8601String(),
      distanceKm: 6.4,
      durationMin: 18.0,
      category: request.category,
    );
  }
}

/// No live driver tracking in the demo — the map placeholder art shows.
class DemoTripLocation extends TripLocationPort {
  @override
  Stream<TripLocationLatest?> watchLatest(String rideId) =>
      Stream<TripLocationLatest?>.value(null);
}

/// No-op FCM — the demo build never initializes Firebase.
class DemoDispatchFcmService extends DispatchFcmService {
  DemoDispatchFcmService({required super.tokenApi, required super.apiClient});

  @override
  Future<void> init({
    required GoRouter router,
    required WidgetRef ref,
  }) async {}

  @override
  Stream<RideFcmNudge> get rideNudges => const Stream.empty();

  @override
  Future<void> syncDriverTokenRegistration() async {}

  @override
  Future<void> syncPassengerTokenRegistration() async {}

  @override
  Future<void> clearRegisteredToken() async {}
}
