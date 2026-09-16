import '../../domain/entities/ride.dart';

/// Passenger-facing ride status copy — driven only by server [Ride.state].
String activeRideTitle(String state) {
  return switch (state.toUpperCase()) {
    'DRIVER_ASSIGNED' => 'Driver assigned',
    'DRIVER_EN_ROUTE' => 'Driver on the way',
    'DRIVER_ARRIVED' => 'Driver has arrived',
    'RIDE_STARTED' => 'Ride in progress',
    'RIDE_COMPLETED' => 'Ride completed',
    'RIDE_CLOSED' => 'Ride closed',
    'CANCELLED' => 'Ride cancelled',
    'EXPIRED' => 'Request expired',
    'NO_SHOW' => 'No-show recorded',
    'SEARCHING' || 'OFFERS_AVAILABLE' => 'Looking for offers',
    _ => 'Ride update',
  };
}

String activeRideMessage(String state) {
  return switch (state.toUpperCase()) {
    'DRIVER_ASSIGNED' =>
      'A driver is assigned on Ora\'s servers. Live location and ETA are not '
          'available in this build.',
    'DRIVER_EN_ROUTE' =>
      'The assigned driver is marked en route by the server. Ora is not '
          'showing a fake map or invented ETA.',
    'DRIVER_ARRIVED' =>
      'The driver has arrived according to the server. Waiting time below uses '
          'the real arrivedAt timestamp when present.',
    'RIDE_STARTED' =>
      'Your ride has started on the server. Route progress requires location '
          'services that are not in this build.',
    'RIDE_COMPLETED' =>
      'The ride is completed on the server. Closing the ride is the next '
          'passenger step. You can rate after completion or close.',
    'RIDE_CLOSED' =>
      'This ride aggregate is closed. You can submit a stars-only rating '
          'from the rate screen.',
    'CANCELLED' => 'This ride was cancelled on Ora\'s servers.',
    'EXPIRED' =>
      'This request expired on the server. Offers are no longer available.',
    'NO_SHOW' =>
      'The server recorded a no-show. No fees or penalties are invented here.',
    'SEARCHING' || 'OFFERS_AVAILABLE' =>
      'This ride is still in the offers marketplace.',
    _ =>
      'Ora received an unrecognized ride state. Showing server data safely.',
  };
}

bool isActiveRidePollingState(String state) {
  final s = state.toUpperCase();
  return s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED' ||
      s == 'RIDE_COMPLETED';
}

bool isActiveRideTerminalState(String state) {
  final s = state.toUpperCase();
  return s == 'CANCELLED' ||
      s == 'EXPIRED' ||
      s == 'NO_SHOW' ||
      s == 'RIDE_CLOSED';
}

/// Passenger may cancel through RIDE_STARTED (server-enforced).
bool passengerCanCancel(String state) {
  final s = state.toUpperCase();
  return s == 'SEARCHING' ||
      s == 'OFFERS_AVAILABLE' ||
      s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED';
}

bool passengerCanClose(String state) =>
    state.toUpperCase() == 'RIDE_COMPLETED';

bool isMarketplaceRideState(String state) {
  final s = state.toUpperCase();
  return s == 'SEARCHING' || s == 'OFFERS_AVAILABLE';
}

/// Apply only if [incoming] is not stale vs [current] (version / requestVersion).
bool shouldAcceptRideSnapshot(Ride incoming, Ride? current) {
  if (current == null) return true;
  if (incoming.rideId != current.rideId) return false;
  if (incoming.version > current.version) return true;
  if (incoming.version < current.version) return false;
  if (incoming.requestVersion > current.requestVersion) return true;
  if (incoming.requestVersion < current.requestVersion) return false;
  // Same versions: still accept to refresh timestamps / identical snapshot.
  return true;
}

/// UI-relevant ride fields for Offers + Active Ride (Slice K no-op skip).
///
/// Does **not** replace [shouldAcceptRideSnapshot]. Call only after the
/// version gate accepts the snapshot.
bool isRideUiEquivalent(Ride? a, Ride b) {
  if (a == null) return false;
  return a.rideId == b.rideId &&
      a.state == b.state &&
      a.version == b.version &&
      a.requestVersion == b.requestVersion &&
      a.assignedDriverId == b.assignedDriverId &&
      a.agreedFareMinor == b.agreedFareMinor &&
      a.agreedOfferId == b.agreedOfferId &&
      a.agreedFareCurrency == b.agreedFareCurrency &&
      a.category == b.category &&
      a.serviceType == b.serviceType &&
      a.passengerOfferMinor == b.passengerOfferMinor &&
      a.arrivedAt == b.arrivedAt &&
      a.assignedAt == b.assignedAt &&
      a.startedAt == b.startedAt &&
      a.completedAt == b.completedAt &&
      a.closedAt == b.closedAt &&
      a.cancelledBy == b.cancelledBy &&
      a.cancellationReason == b.cancellationReason &&
      a.updatedAt == b.updatedAt &&
      a.pickup.lat == b.pickup.lat &&
      a.pickup.lng == b.pickup.lng &&
      a.pickup.address == b.pickup.address &&
      a.destination.lat == b.destination.lat &&
      a.destination.lng == b.destination.lng &&
      a.destination.address == b.destination.address;
}

/// Offer list fields that Offers Inbox actually renders/selects on.
bool isOfferUiEquivalent(RideOffer a, RideOffer b) {
  return a.offerId == b.offerId &&
      a.rideId == b.rideId &&
      a.status == b.status &&
      a.amountMinor == b.amountMinor &&
      a.currency == b.currency &&
      a.type == b.type &&
      a.requestVersion == b.requestVersion &&
      a.expiresAt == b.expiresAt &&
      a.selectedAt == b.selectedAt &&
      a.withdrawnAt == b.withdrawnAt &&
      a.driverId == b.driverId &&
      _driverSnapshotUiEqual(a.driverSnapshot, b.driverSnapshot);
}

bool areOfferListsUiEquivalent(List<RideOffer> a, List<RideOffer> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!isOfferUiEquivalent(a[i], b[i])) return false;
  }
  return true;
}

bool _driverSnapshotUiEqual(
  Map<String, Object?>? a,
  Map<String, Object?>? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}

/// Wait duration from real [Ride.arrivedAt] only — never invents arrival.
String? arrivedWaitLabel(Ride ride, DateTime now) {
  final raw = ride.arrivedAt;
  if (raw == null || raw.isEmpty) return null;
  final arrived = DateTime.tryParse(raw);
  if (arrived == null) return null;
  final elapsed = now.difference(arrived.toLocal());
  if (elapsed.isNegative) return null;
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;
  if (minutes <= 0) {
    return 'Waiting ${seconds}s';
  }
  return 'Waiting ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
}

String? formatAgreedFare(Ride ride) {
  final minor = ride.agreedFareMinor;
  if (minor == null) return null;
  final currency = ride.agreedFareCurrency ?? 'PKR';
  final major = minor / 100.0;
  final whole = major == major.roundToDouble()
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
  if (currency.toUpperCase() == 'PKR') return 'Rs $whole';
  return '$whole $currency';
}
