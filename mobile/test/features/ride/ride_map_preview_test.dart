import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/presentation/models/ride_map_preview_model.dart';
import 'package:ora/features/ride/presentation/utils/encoded_polyline_decoder.dart';
import 'package:ora/features/ride/presentation/utils/ride_map_camera_policy.dart';
import 'package:ora/features/ride/presentation/widgets/ride_map_preview.dart';
import 'package:flutter/material.dart';

void main() {
  const pickup = ResolvedPassengerLocation(
    lat: 31.520400,
    lng: 74.358700,
    source: PassengerLocationSource.gps,
    address: 'Pickup',
  );
  const destination = ResolvedPassengerLocation(
    lat: 31.510580,
    lng: 74.344450,
    source: PassengerLocationSource.place,
    address: 'Liberty',
  );

  /// Classic Google sample polyline → three known points.
  const samplePolyline = '_p~iF~ps|U_ulLnnqC_mqNvxq`@';

  group('EncodedPolylineDecoder', () {
    test('decodes valid Google sample polyline', () {
      final points = EncodedPolylineDecoder.decode(samplePolyline);
      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 0.0001));
      expect(points[0].longitude, closeTo(-120.2, 0.0001));
      expect(points[2].latitude, closeTo(43.252, 0.001));
      expect(points[2].longitude, closeTo(-126.453, 0.001));
    });

    test('invalid/missing polyline returns empty (no throw)', () {
      expect(EncodedPolylineDecoder.decode(null), isEmpty);
      expect(EncodedPolylineDecoder.decode(''), isEmpty);
      expect(EncodedPolylineDecoder.decode('   '), isEmpty);
      expect(EncodedPolylineDecoder.decode('!!!'), isEmpty);
    });
  });

  group('RideMapCameraPolicy', () {
    test('fits bounds for distant points', () {
      const a = LatLng(31.52, 74.35);
      const b = LatLng(31.51, 74.34);
      expect(RideMapCameraPolicy.areExtremelyClose(a, b), isFalse);
      final update = RideMapCameraPolicy.cameraUpdate(
        pickup: a,
        destination: b,
      );
      expect(update, isNotNull);
    });

    test('close coordinates use fallback zoom path', () {
      const a = LatLng(31.5200, 74.3587);
      const b = LatLng(31.52005, 74.35872);
      expect(RideMapCameraPolicy.areExtremelyClose(a, b), isTrue);
      final update = RideMapCameraPolicy.cameraUpdate(
        pickup: a,
        destination: b,
      );
      expect(update, isNotNull);
    });

    test('single point centers', () {
      final update = RideMapCameraPolicy.cameraUpdate(
        pickup: const LatLng(31.52, 74.35),
        destination: null,
      );
      expect(update, isNotNull);
    });

    test('no points returns null', () {
      expect(
        RideMapCameraPolicy.cameraUpdate(pickup: null, destination: null),
        isNull,
      );
    });
  });

  group('RideMapPreviewModel', () {
    PricingEstimate estimate({String? polyline}) => PricingEstimate(
          pricingSnapshotId: 'ps_map1',
          recommendedFareMinor: 42000,
          offerBoundMinMinor: 30000,
          offerBoundMaxMinor: 75000,
          currency: 'PKR',
          pricingRulesVersion: 'v1',
          computedAt: '2026-01-01T00:00:00.000Z',
          expiresAt: '2099-01-01T00:00:00.000Z',
          distanceKm: 3.6,
          durationMin: 12,
          category: 'easy',
          encodedPolyline: polyline,
        );

    test('renders real pickup/destination markers from resolved coords', () {
      final model = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate(polyline: samplePolyline),
        hasUsablePricing: true,
      );
      expect(model.pickup!.latitude, pickup.lat);
      expect(model.pickup!.longitude, pickup.lng);
      expect(model.destination!.latitude, destination.lat);
      expect(model.destination!.longitude, destination.lng);
      expect(model.hasRouteLine, isTrue);
      expect(model.status, RideMapPreviewStatus.ready);
    });

    test('missing polyline keeps markers and omits route', () {
      final model = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate(),
        hasUsablePricing: true,
      );
      expect(model.hasPickup, isTrue);
      expect(model.hasDestination, isTrue);
      expect(model.hasRouteLine, isFalse);
    });

    test('invalid polyline does not crash and omits route', () {
      final model = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate(polyline: 'not-a-polyline'),
        hasUsablePricing: true,
      );
      expect(model.hasRouteLine, isFalse);
    });

    test('coordinate change invalidates route identity / stale polyline', () {
      final first = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate(polyline: samplePolyline),
        hasUsablePricing: true,
      );
      const movedDestination = ResolvedPassengerLocation(
        lat: 31.5600,
        lng: 74.3500,
        source: PassengerLocationSource.place,
        address: 'New dest',
      );
      final second = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: movedDestination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.idle,
        pricingEstimate: null,
        hasUsablePricing: false,
      );
      expect(first.routeIdentity, isNot(second.routeIdentity));
      expect(second.hasRouteLine, isFalse);
      expect(second.destination!.latitude, movedDestination.lat);
    });

    test('route unavailable still shows markers', () {
      final model = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.routeUnavailable,
        pricingEstimate: null,
        hasUsablePricing: false,
      );
      expect(model.status, RideMapPreviewStatus.routeUnavailable);
      expect(model.hasPickup, isTrue);
      expect(model.hasDestination, isTrue);
      expect(model.hasRouteLine, isFalse);
    });
  });

  group('RideMapPreview widget', () {
    testWidgets('map failure / disabled maps does not block UI shell',
        (tester) async {
      final model = RideMapPreviewModel.fromRideRequest(
        confirmedPickup: pickup,
        confirmedDestination: destination,
        proposedPickup: null,
        proposedDestination: null,
        pricingStatus: PricingStatus.success,
        pricingEstimate: const PricingEstimate(
          pricingSnapshotId: 'ps_map1',
          recommendedFareMinor: 42000,
          offerBoundMinMinor: 30000,
          offerBoundMaxMinor: 75000,
          currency: 'PKR',
          pricingRulesVersion: 'v1',
          computedAt: '2026-01-01T00:00:00.000Z',
          expiresAt: '2099-01-01T00:00:00.000Z',
          distanceKm: 3.6,
          durationMin: 12,
          category: 'easy',
          encodedPolyline: samplePolyline,
        ),
        hasUsablePricing: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RideMapPreview(
              model: model,
              enableMaps: false,
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.text('Map preview'), findsOneWidget);
      expect(find.textContaining('confirmed'), findsOneWidget);
      expect(find.byType(GoogleMap), findsNothing);
    });
  });

  group('PricingEstimate polyline field', () {
    test('parses optional encodedPolyline', () {
      final estimate = PricingEstimate.fromJson({
        'pricingSnapshotId': 'ps_abc',
        'recommendedFareMinor': 42000,
        'offerBoundMinMinor': 30000,
        'offerBoundMaxMinor': 75000,
        'currency': 'PKR',
        'pricingRulesVersion': 'v1',
        'computedAt': '2026-01-01T00:00:00.000Z',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'distanceKm': 3.6,
        'durationMin': 12,
        'category': 'easy',
        'encodedPolyline': samplePolyline,
      });
      expect(estimate.encodedPolyline, samplePolyline);
      expect(estimate.hasUsableEncodedPolyline, isTrue);
    });

    test('omitted polyline remains optional', () {
      final estimate = PricingEstimate.fromJson({
        'pricingSnapshotId': 'ps_abc',
        'recommendedFareMinor': 42000,
        'offerBoundMinMinor': 30000,
        'offerBoundMaxMinor': 75000,
        'currency': 'PKR',
        'pricingRulesVersion': 'v1',
        'computedAt': '2026-01-01T00:00:00.000Z',
        'expiresAt': '2099-01-01T00:00:00.000Z',
        'distanceKm': 3.6,
        'durationMin': 12,
        'category': 'easy',
      });
      expect(estimate.encodedPolyline, isNull);
      expect(estimate.hasUsableEncodedPolyline, isFalse);
    });
  });
}
