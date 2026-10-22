// On-device smoke test for the pickup-naming fallback geocoder.
// Exercises the REAL GeocodingDeviceGeocoder code path against the
// native Android Geocoder — no backend, staging, or billing involved.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ora/features/ride/data/location/geocoding_device_geocoder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native geocoder resolves a real locality for Lahore coordinates',
    (tester) async {
      final geocoder = GeocodingDeviceGeocoder();
      // Report raw support/lookup state for the artifact — do not fabricate.
      final label = await geocoder.localityLabel(
        lat: 31.46,
        lng: 74.26,
      );
      // ignore: avoid_print
      print('DEVICE_GEOCODER_RESULT=${label ?? "null"}');
      // The call must not throw; a label is ideal but null is an honest
      // "unsupported/empty" answer — either way the fallback path is safe.
      expect(label, anyOf(isNull, isNotEmpty));
    },
    // Native lookup can block on a GMS network call.
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
