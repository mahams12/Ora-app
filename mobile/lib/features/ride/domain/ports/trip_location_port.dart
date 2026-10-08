import '../models/trip_location_latest.dart';

/// Read-only live trip location (RTDB `tripLocations/{rideId}/latest`).
///
/// Implementations must NEVER write to RTDB.
abstract class TripLocationPort {
  /// Emits validated [TripLocationLatest] updates for [rideId].
  ///
  /// - `null` means the node is missing / cleared (waiting or cleaned up).
  /// - Malformed snapshots are skipped (no emission).
  /// - Permission denied / transport errors complete the stream softly
  ///   (callers treat as unavailable — never crash).
  Stream<TripLocationLatest?> watchLatest(String rideId);
}
