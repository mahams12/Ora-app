import '../models/trip_location_latest.dart';

/// Freshness bands for display-only driver location (MAP-2A).
enum TripLocationFreshness {
  /// ≤20s — treat as live.
  fresh,

  /// >20s and ≤45s — dim / "Location updating…".
  stale,

  /// >45s and ≤120s — degraded; keep last known, never invent motion.
  degraded,

  /// >120s — hide / strongly de-emphasize driver marker.
  expired,

  /// No usable fix.
  missing,
}

/// Injectable-clock freshness classifier.
class TripLocationFreshnessPolicy {
  const TripLocationFreshnessPolicy({
    this.freshMax = const Duration(seconds: 20),
    this.staleMax = const Duration(seconds: 45),
    this.expiredAfter = const Duration(seconds: 120),
  });

  final Duration freshMax;
  final Duration staleMax;
  final Duration expiredAfter;

  /// Classifies [latest] relative to [now].
  ///
  /// Prefer `acceptedAt` (server) when parseable; fall back to `ts` (client ms).
  /// Clamps future skew so a bad clock cannot keep markers "fresh" forever.
  TripLocationFreshness classify(
    TripLocationLatest? latest, {
    required DateTime now,
  }) {
    if (latest == null || !latest.hasValidCoordinates) {
      return TripLocationFreshness.missing;
    }

    final age = _age(latest, now: now);
    if (age == null) return TripLocationFreshness.missing;
    if (age <= freshMax) return TripLocationFreshness.fresh;
    if (age <= staleMax) return TripLocationFreshness.stale;
    if (age <= expiredAfter) return TripLocationFreshness.degraded;
    return TripLocationFreshness.expired;
  }

  /// Whether the driver marker should be drawn (non-expired usable fix).
  bool shouldShowDriverMarker(TripLocationFreshness band) {
    switch (band) {
      case TripLocationFreshness.fresh:
      case TripLocationFreshness.stale:
      case TripLocationFreshness.degraded:
        return true;
      case TripLocationFreshness.expired:
      case TripLocationFreshness.missing:
        return false;
    }
  }

  Duration? _age(TripLocationLatest latest, {required DateTime now}) {
    final utcNow = now.toUtc();
    DateTime? accepted;
    final parsed = DateTime.tryParse(latest.acceptedAt);
    if (parsed != null) accepted = parsed.toUtc();

    DateTime? fromTs;
    if (latest.ts > 0) {
      fromTs = DateTime.fromMillisecondsSinceEpoch(latest.ts, isUtc: true);
    }

    // Prefer server accept time; fall back to client fix ts.
    final stamp = accepted ?? fromTs;
    if (stamp == null) return null;

    var age = utcNow.difference(stamp);
    // Future skew (device clock behind server): treat as zero age, not negative.
    if (age.isNegative) age = Duration.zero;
    return age;
  }
}
