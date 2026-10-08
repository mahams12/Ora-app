/// Ride states that allow passenger RTDB live-location listening (MAP-2A).
///
/// MUST stay aligned with backend `LOCATION_PUBLISH_RIDE_STATES` and
/// Flutter `driverLocationShouldWatch`.
bool tripLocationShouldListen(String? rideState) {
  switch (rideState?.toUpperCase()) {
    case 'DRIVER_ASSIGNED':
    case 'DRIVER_EN_ROUTE':
    case 'DRIVER_ARRIVED':
    case 'RIDE_STARTED':
      return true;
    default:
      return false;
  }
}

/// States where the passenger listener must stop (including RIDE_COMPLETED).
///
/// Note: Active Ride HTTP polling may continue through RIDE_COMPLETED for
/// close UX — the RTDB listener still stops here because server cleanup
/// clears `tripLocations` / ACL at completion.
bool tripLocationMustStop(String? rideState) {
  if (rideState == null || rideState.trim().isEmpty) return true;
  if (tripLocationShouldListen(rideState)) return false;
  return true;
}
