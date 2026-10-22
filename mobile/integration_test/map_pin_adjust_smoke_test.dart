// On-device smoke: MAP-PIN-ADJUST set-point-on-map flow.
// Pumps the real RideRequestView with a fake GPS fix; placeSearchPortProvider
// stays REAL so the live path runs — Places (billing-blocked → fails) then the
// native Android Geocoder fallback. Taps the actual MapLibre map surface.
// No backend/staging needed — create is never invoked.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/features/ride/domain/models/resolved_passenger_location.dart';
import 'package:ora/features/ride/domain/ports/device_location_port.dart';
import 'package:ora/features/ride/presentation/view_models/ride_request_view_model.dart';
import 'package:ora/features/ride/presentation/views/ride_request_view.dart';

class _FakeDeviceLocation implements DeviceLocationPort {
  @override
  Future<ResolvedPassengerLocation> getCurrentLocation() async =>
      const ResolvedPassengerLocation(
        lat: 31.46,
        lng: 74.26,
        source: PassengerLocationSource.gps,
      );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Adjust on map → real map tap sets pickup proposal with mapPin source',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceLocationPortProvider
                .overrideWithValue(_FakeDeviceLocation()),
          ],
          child: const MaterialApp(home: RideRequestView()),
        ),
      );

      // Style load + tile network can take a while — bounded pump loop.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // ignore: avoid_print
      print(
        'STAGE=mounted map=${tester.any(find.byType(MapLibreMap))}',
      );

      final element = tester.element(find.byType(RideRequestView));
      final container = ProviderScope.containerOf(element);
      final vm =
          container.read(rideRequestViewModelProvider.notifier);

      // Real naming path can hang on Places HTTP (billing-blocked project)
      // before the device geocoder runs — bound it so the test can proceed.
      await vm
          .useCurrentLocationForPickup()
          .timeout(const Duration(seconds: 45), onTimeout: () {
        // ignore: avoid_print
        print('STAGE=gps_name_lookup_timed_out');
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      // ignore: avoid_print
      print(
        'STAGE=proposal proposed=${container.read(rideRequestViewModelProvider).proposedPickup?.displayLabel}',
      );

      final adjust = find.text('Adjust on map');
      expect(adjust, findsOneWidget);
      await tester.ensureVisible(adjust);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(adjust);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(
        container.read(rideRequestViewModelProvider).pinAdjustTarget,
        LocationField.pickup,
      );

      final mapFinder = find.byType(MapLibreMap);
      // If the style/key failed to load the shell is a soft-fail — record
      // rather than fabricate.
      if (tester.any(mapFinder)) {
        // Tap off-center so the pickup symbol does not consume the gesture.
        final center = tester.getCenter(mapFinder);
        await tester.tapAt(
          Offset(center.dx + 55, center.dy - 80),
        );
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      final s = container.read(rideRequestViewModelProvider);
      final p = s.proposedPickup;
      // ignore: avoid_print
      print(
        'PIN_ADJUST_RESULT source=${p?.source} lat=${p?.lat} lng=${p?.lng} '
        'label="${p?.displayLabel}" unresolved=${s.pickupNameUnresolved} '
        'mapMounted=${tester.any(mapFinder)}',
      );
      expect(p, isNotNull);
      expect(p!.source, PassengerLocationSource.mapPin);
      expect(p.lat.abs(), lessThanOrEqualTo(90));
      expect(p.lng.abs(), lessThanOrEqualTo(180));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
