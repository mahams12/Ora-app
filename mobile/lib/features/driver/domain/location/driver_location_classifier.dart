import 'driver_location_fix.dart';

/// Same bounds as `backend/auth-service/src/location/validation.ts`.
///
/// `MAX_ACCURACY_M = 50`, `MAX_SPEED_KMH = 200`,
/// stale when `timestamp < now - 15s`, future when `timestamp > now + 5s`.
const double kDriverLocationMaxAccuracyMeters = 50;
const double kDriverLocationMaxSpeedKmh = 200;
const Duration kDriverLocationMaxAge = Duration(seconds: 15);
const Duration kDriverLocationMaxFutureSkew = Duration(seconds: 5);

enum DriverLocationClass {
  accepted,
  invalid,
  poorAccuracy,
  impossibleSpeed,
  stale,
  future,
  duplicate;

  /// Stable diagnostic token. Not shown in the UI.
  String get logName => switch (this) {
    DriverLocationClass.accepted => 'ACCEPTED',
    DriverLocationClass.invalid => 'INVALID',
    DriverLocationClass.poorAccuracy => 'POOR_ACCURACY',
    DriverLocationClass.impossibleSpeed => 'IMPOSSIBLE_SPEED',
    DriverLocationClass.stale => 'STALE',
    DriverLocationClass.future => 'FUTURE',
    DriverLocationClass.duplicate => 'DUPLICATE',
  };
}

/// Which field failed when [DriverLocationClass.invalid] is returned.
enum DriverLocationInvalidDetail { latitude, longitude, accuracy, speed }

class DriverLocationVerdict {
  const DriverLocationVerdict(this.classification, {this.detail});

  final DriverLocationClass classification;
  final DriverLocationInvalidDetail? detail;
}

/// Deterministic checks. First failure wins, in server-validation order:
/// coordinates, accuracy, speed, timestamp, then duplicate of the last
/// accepted fix.
///
/// Does not apply teleport distance, Kalman smoothing, heading spikes,
/// or a 20 m warning band.
class DriverLocationClassifier {
  const DriverLocationClassifier();

  DriverLocationVerdict classify(
    DriverLocationFix fix, {
    required DateTime now,
    DriverLocationFix? lastAccepted,
  }) {
    if (!fix.latitude.isFinite || fix.latitude < -90 || fix.latitude > 90) {
      return const DriverLocationVerdict(
        DriverLocationClass.invalid,
        detail: DriverLocationInvalidDetail.latitude,
      );
    }
    if (!fix.longitude.isFinite ||
        fix.longitude < -180 ||
        fix.longitude > 180) {
      return const DriverLocationVerdict(
        DriverLocationClass.invalid,
        detail: DriverLocationInvalidDetail.longitude,
      );
    }
    if (!fix.accuracyMeters.isFinite || fix.accuracyMeters < 0) {
      return const DriverLocationVerdict(
        DriverLocationClass.invalid,
        detail: DriverLocationInvalidDetail.accuracy,
      );
    }
    if (fix.accuracyMeters > kDriverLocationMaxAccuracyMeters) {
      return const DriverLocationVerdict(DriverLocationClass.poorAccuracy);
    }
    if (!fix.speedKmh.isFinite || fix.speedKmh < 0) {
      return const DriverLocationVerdict(
        DriverLocationClass.invalid,
        detail: DriverLocationInvalidDetail.speed,
      );
    }
    if (fix.speedKmh > kDriverLocationMaxSpeedKmh) {
      return const DriverLocationVerdict(DriverLocationClass.impossibleSpeed);
    }

    final age = now.difference(fix.timestamp);
    if (age > kDriverLocationMaxAge) {
      return const DriverLocationVerdict(DriverLocationClass.stale);
    }
    final ahead = fix.timestamp.difference(now);
    if (ahead > kDriverLocationMaxFutureSkew) {
      return const DriverLocationVerdict(DriverLocationClass.future);
    }

    if (lastAccepted != null && fix.isDuplicateOf(lastAccepted)) {
      return const DriverLocationVerdict(DriverLocationClass.duplicate);
    }

    return const DriverLocationVerdict(DriverLocationClass.accepted);
  }
}
