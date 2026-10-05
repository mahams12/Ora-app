import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/driver/domain/location/driver_location_classifier.dart';
import 'package:ora/features/driver/domain/location/driver_location_fix.dart';

void main() {
  const classifier = DriverLocationClassifier();
  final now = DateTime.utc(2026, 10, 5, 12);

  DriverLocationFix fix({
    double latitude = 31.5204,
    double longitude = 74.3587,
    double accuracyMeters = 8,
    double speedKmh = 36,
    DateTime? timestamp,
    double? headingDegrees = 90,
    double? altitudeMeters = 217,
  }) {
    return DriverLocationFix(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      speedKmh: speedKmh,
      timestamp: timestamp ?? now,
      headingDegrees: headingDegrees,
      altitudeMeters: altitudeMeters,
    );
  }

  DriverLocationClass classify(
    DriverLocationFix sample, {
    DriverLocationFix? lastAccepted,
  }) {
    return classifier
        .classify(sample, now: now, lastAccepted: lastAccepted)
        .classification;
  }

  test('thresholds match backend validation.ts', () {
    expect(kDriverLocationMaxAccuracyMeters, 50);
    expect(kDriverLocationMaxSpeedKmh, 200);
    expect(kDriverLocationMaxAge, const Duration(seconds: 15));
    expect(kDriverLocationMaxFutureSkew, const Duration(seconds: 5));
  });

  test('1. valid fix accepted', () {
    expect(classify(fix()), DriverLocationClass.accepted);
  });

  test('2. invalid latitude', () {
    expect(classify(fix(latitude: 90.0001)), DriverLocationClass.invalid);
    expect(classify(fix(latitude: -90.0001)), DriverLocationClass.invalid);
  });

  test('3. invalid longitude', () {
    expect(classify(fix(longitude: 180.0001)), DriverLocationClass.invalid);
    expect(classify(fix(longitude: -180.0001)), DriverLocationClass.invalid);
  });

  test('4. NaN coordinate', () {
    expect(classify(fix(latitude: double.nan)), DriverLocationClass.invalid);
    expect(classify(fix(longitude: double.nan)), DriverLocationClass.invalid);
  });

  test('5. infinite coordinate', () {
    expect(
      classify(fix(latitude: double.infinity)),
      DriverLocationClass.invalid,
    );
    expect(
      classify(fix(longitude: double.negativeInfinity)),
      DriverLocationClass.invalid,
    );
  });

  test('6. accuracy > 50m', () {
    expect(
      classify(fix(accuracyMeters: 50.001)),
      DriverLocationClass.poorAccuracy,
    );
  });

  test('7. negative accuracy', () {
    expect(classify(fix(accuracyMeters: -0.1)), DriverLocationClass.invalid);
  });

  test('8. speed > 200 km/h', () {
    expect(
      classify(fix(speedKmh: 200.001)),
      DriverLocationClass.impossibleSpeed,
    );
  });

  test('9. negative speed', () {
    expect(classify(fix(speedKmh: -1)), DriverLocationClass.invalid);
  });

  test('10. stale timestamp >15s', () {
    expect(
      classify(
        fix(
          timestamp: now.subtract(const Duration(seconds: 15, milliseconds: 1)),
        ),
      ),
      DriverLocationClass.stale,
    );
  });

  test('11. future timestamp >5s', () {
    expect(
      classify(
        fix(timestamp: now.add(const Duration(seconds: 5, milliseconds: 1))),
      ),
      DriverLocationClass.future,
    );
  });

  test('12. duplicate fix', () {
    final sample = fix();
    expect(classify(sample), DriverLocationClass.accepted);
    expect(
      classify(sample, lastAccepted: sample),
      DriverLocationClass.duplicate,
    );
    expect(
      classify(
        fix(timestamp: now.add(const Duration(milliseconds: 1))),
        lastAccepted: sample,
      ),
      DriverLocationClass.accepted,
    );
  });

  test('13. valid boundary values', () {
    expect(
      classify(fix(latitude: 90, longitude: 180)),
      DriverLocationClass.accepted,
    );
    expect(
      classify(fix(latitude: -90, longitude: -180)),
      DriverLocationClass.accepted,
    );
    expect(classify(fix(accuracyMeters: 0)), DriverLocationClass.accepted);
    expect(classify(fix(accuracyMeters: 50)), DriverLocationClass.accepted);
    expect(classify(fix(speedKmh: 0)), DriverLocationClass.accepted);
    expect(classify(fix(speedKmh: 200)), DriverLocationClass.accepted);
  });

  test('14. timestamp boundary behavior', () {
    expect(
      classify(fix(timestamp: now.subtract(const Duration(seconds: 15)))),
      DriverLocationClass.accepted,
    );
    expect(
      classify(fix(timestamp: now.add(const Duration(seconds: 5)))),
      DriverLocationClass.accepted,
    );
  });

  test('non-finite accuracy and speed are invalid', () {
    expect(
      classify(fix(accuracyMeters: double.nan)),
      DriverLocationClass.invalid,
    );
    expect(classify(fix(speedKmh: double.nan)), DriverLocationClass.invalid);
  });

  test('platform speed and heading conversion', () {
    expect(driverLocationSpeedKmhFromMetersPerSecond(10), 36);
    expect(driverLocationSpeedKmhFromMetersPerSecond(-1), -3.6);
    expect(driverLocationHeadingDegrees(-1), isNull);
    expect(driverLocationHeadingDegrees(90), 90);
    expect(driverLocationAltitudeMeters(double.nan), isNull);
    expect(driverLocationAltitudeMeters(217), 217);
  });
}
