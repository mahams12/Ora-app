import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/ride/domain/models/passenger_city.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/presentation/offers/offer_display.dart';

void main() {
  group('passenger city', () {
    test('suggests lahore from Places address', () {
      expect(
        suggestCitySlugFromAddress('Gulberg III, Lahore, Pakistan'),
        'lahore',
      );
    });

    test('prefers destination then pickup', () {
      expect(
        suggestCitySlugFromTrip(
          pickupAddress: 'Somewhere, Karachi',
          destinationAddress: 'Liberty, Lahore',
        ),
        'lahore',
      );
    });

    test('normalize rejects empty / garbage', () {
      expect(normalizePassengerCitySlug(''), isNull);
      expect(normalizePassengerCitySlug('!!!'), isNull);
      expect(normalizePassengerCitySlug('Lahore'), 'lahore');
    });
  });

  group('pricing estimate DTO', () {
    test('parses backend response fields', () {
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
      expect(estimate.pricingSnapshotId, 'ps_abc');
      expect(estimate.recommendedFareMinor, 42000);
    });

    test('request JSON omits fare and snapshot fields', () {
      final json = const PricingEstimateRequest(
        pickupLat: 1,
        pickupLng: 2,
        destinationLat: 3,
        destinationLng: 4,
        category: 'easy',
        city: 'lahore',
      ).toJson();
      expect(json.keys, containsAll(['pickup', 'destination', 'category', 'city', 'serviceType']));
      expect(json.containsKey('distanceKm'), isFalse);
      expect(json.containsKey('pricingSnapshotId'), isFalse);
      expect(json.containsKey('recommendedFareMinor'), isFalse);
    });

    test('expiry detection', () {
      const expired = PricingEstimate(
        pricingSnapshotId: 'ps_x',
        recommendedFareMinor: 1,
        offerBoundMinMinor: 1,
        offerBoundMaxMinor: 1,
        currency: 'PKR',
        pricingRulesVersion: 'v1',
        computedAt: '2020-01-01T00:00:00.000Z',
        expiresAt: '2020-01-01T00:10:00.000Z',
        distanceKm: 1,
        durationMin: 1,
        category: 'easy',
      );
      expect(expired.isExpiredAt(DateTime.utc(2021)), isTrue);
    });
  });

  group('PKR display', () {
    test('formats minor units via existing helper', () {
      expect(formatOfferAmountMinor(42000, 'PKR'), 'Rs 420');
      expect(formatOfferAmountMinor(30000, 'PKR'), 'Rs 300');
      expect(formatOfferAmountMinor(75000, 'PKR'), 'Rs 750');
    });
  });
}
