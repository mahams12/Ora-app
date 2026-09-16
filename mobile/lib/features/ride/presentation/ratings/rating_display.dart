/// Passenger rating helpers — stars-only Phase 2N contract.
library;

bool isPassengerRatingSoftEligible(String? rideState) {
  final s = rideState?.toUpperCase();
  return s == 'RIDE_COMPLETED' || s == 'RIDE_CLOSED';
}

String ratingIneligibleMessage(String? rideState) {
  final s = rideState?.toUpperCase() ?? '';
  if (s.isEmpty) {
    return 'This ride cannot be rated right now.';
  }
  return 'Ride state $s cannot accept ratings. Only completed or closed '
      'rides can be rated on Ora\'s servers.';
}
