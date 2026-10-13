import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/domain/ports/place_search_port.dart';
import 'package:ora/features/ride/domain/ports/pricing_estimate_port.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/utils/ride_request_map_layout.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';
import 'package:ora/features/ride/presentation/widgets/ride_map_preview.dart';

class MockCreateRideUseCase extends Mock implements CreateRideUseCase {}

class _CountingPlaces implements PlaceSearchPort {
  int autocompleteCalls = 0;

  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
  }) async {
    autocompleteCalls += 1;
    return const [];
  }

  @override
  Future<ResolvedPassengerLocation> resolvePlace({
    required String placeId,
    required String sessionToken,
  }) async {
    throw StateError('unexpected resolvePlace');
  }

  @override
  Future<ResolvedPassengerLocation> reverseGeocode({
    required double lat,
    required double lng,
  }) async {
    throw StateError('unexpected reverseGeocode');
  }
}

class _CountingGps implements DeviceLocationPort {
  int locateCalls = 0;

  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async {
    locateCalls += 1;
    throw StateError('unexpected GPS');
  }
}

class _CountingPricing implements PricingEstimatePort {
  int estimateCalls = 0;

  @override
  Future<PricingEstimate> estimate(PricingEstimateRequest request) async {
    estimateCalls += 1;
    throw StateError('unexpected estimate');
  }
}

void main() {
  group('RideRequestMapLayout', () {
    test('compact height is ~45–55% of usable height on normal phones', () {
      const available = 800.0;
      final h = RideRequestMapLayout.compactMapHeight(
        viewportHeight: available,
        keyboardVisible: false,
      );
      expect(h / available, greaterThanOrEqualTo(0.45));
      expect(h / available, lessThanOrEqualTo(0.55));
      expect(h, greaterThanOrEqualTo(RideRequestMapLayout.minCompactHeight));
    });

    test('keyboard reduces compact map so sheet remains usable', () {
      final withKeyboard = RideRequestMapLayout.compactMapHeight(
        viewportHeight: 520,
        keyboardVisible: true,
      );
      final without = RideRequestMapLayout.compactMapHeight(
        viewportHeight: 800,
        keyboardVisible: false,
      );
      expect(withKeyboard, lessThan(without));
    });

    test('expanded height fills viewport', () {
      expect(
        RideRequestMapLayout.expandedMapHeight(viewportHeight: 776),
        776,
      );
    });
  });

  group('RideRequestView map expand/collapse', () {
    late MockCreateRideUseCase createRide;
    late _CountingPlaces places;
    late _CountingGps gps;
    late _CountingPricing pricing;

    setUp(() {
      createRide = MockCreateRideUseCase();
      places = _CountingPlaces();
      gps = _CountingGps();
      pricing = _CountingPricing();
    });

    Future<void> pumpRideRequest(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            createRideUseCaseProvider.overrideWithValue(createRide),
            placeSearchPortProvider.overrideWithValue(places),
            deviceLocationPortProvider.overrideWithValue(gps),
            pricingEstimatePortProvider.overrideWithValue(pricing),
          ],
          child: MaterialApp(
            theme: OraTheme.dark(),
            home: const RideRequestView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens compact with expand control; sheet remains',
        (tester) async {
      await pumpRideRequest(tester);

      expect(find.text('Where to?'), findsOneWidget);
      expect(find.byTooltip('Expand map'), findsOneWidget);
      expect(find.byTooltip('Collapse map'), findsNothing);

      final preview = tester.widget<RideMapPreview>(find.byType(RideMapPreview));
      expect(preview.isExpanded, isFalse);
      final mapBox = tester.getSize(find.byType(RideMapPreview));
      final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(mapBox.height / screenH, greaterThanOrEqualTo(0.40));
      expect(mapBox.height / screenH, lessThanOrEqualTo(0.60));
    });

    testWidgets('expand then collapse restores sheet; no port side effects',
        (tester) async {
      await pumpRideRequest(tester);

      // Seed compose field — expand/collapse must preserve controller text.
      await tester.enterText(find.byType(TextField).at(0), 'Gulberg keep');
      // Let Places debounce settle so expand/collapse is not charged for it.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final beforePlaces = places.autocompleteCalls;
      final beforeGps = gps.locateCalls;
      final beforePricing = pricing.estimateCalls;

      await tester.tap(find.byTooltip('Expand map'));
      await tester.pumpAndSettle();

      var preview = tester.widget<RideMapPreview>(find.byType(RideMapPreview));
      expect(preview.isExpanded, isTrue);
      expect(find.text('Where to?'), findsNothing);
      expect(find.byTooltip('Collapse map'), findsOneWidget);

      await tester.tap(find.byTooltip('Collapse map'));
      await tester.pumpAndSettle();

      preview = tester.widget<RideMapPreview>(find.byType(RideMapPreview));
      expect(preview.isExpanded, isFalse);
      expect(find.text('Where to?'), findsOneWidget);
      expect(find.text('Gulberg keep'), findsOneWidget);

      expect(places.autocompleteCalls, beforePlaces);
      expect(gps.locateCalls, beforeGps);
      expect(pricing.estimateCalls, beforePricing);
      verifyZeroInteractions(createRide);
    });

    testWidgets('system back collapses expanded map before exiting',
        (tester) async {
      await pumpRideRequest(tester);

      await tester.tap(find.byTooltip('Expand map'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RideMapPreview>(find.byType(RideMapPreview)).isExpanded,
        isTrue,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<RideMapPreview>(find.byType(RideMapPreview)).isExpanded,
        isFalse,
      );
      expect(find.text('Where to?'), findsOneWidget);
    });
  });
}
