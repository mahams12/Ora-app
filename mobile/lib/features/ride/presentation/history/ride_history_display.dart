/// Ride history presentation helpers — server state only, no invented filters.
library;

const rideHistoryStatusFilters = ['all', 'completed', 'cancelled'];

const rideHistoryServiceTypes = ['ride', 'courier', 'intercity', 'move'];

const rideHistoryDefaultLimit = 10;

/// Where a history row should navigate based on authoritative [state].
enum RideHistoryDestination {
  offers,
  active,
  detail,
}

RideHistoryDestination rideHistoryDestinationFor(String state) {
  final s = state.toUpperCase();
  if (s == 'SEARCHING' || s == 'OFFERS_AVAILABLE') {
    return RideHistoryDestination.offers;
  }
  if (s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED' ||
      s == 'RIDE_COMPLETED') {
    return RideHistoryDestination.active;
  }
  // CANCELLED, EXPIRED, NO_SHOW, RIDE_CLOSED, unknown → detail
  return RideHistoryDestination.detail;
}

bool isHistoryTerminalState(String state) {
  final s = state.toUpperCase();
  return s == 'CANCELLED' ||
      s == 'EXPIRED' ||
      s == 'NO_SHOW' ||
      s == 'RIDE_CLOSED';
}

String historyStatusFilterLabel(String status) {
  return switch (status.toLowerCase()) {
    'all' => 'All',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    _ => status,
  };
}

String historyServiceTypeLabel(String? serviceType) {
  if (serviceType == null || serviceType.isEmpty) return 'Any service';
  return switch (serviceType.toLowerCase()) {
    'ride' => 'Ride',
    'courier' => 'Courier',
    'intercity' => 'Intercity',
    'move' => 'Move',
    _ => serviceType,
  };
}

/// Short title from server state — does not invent “Past”.
String historyRideTitle(String state) {
  return switch (state.toUpperCase()) {
    'SEARCHING' => 'Searching',
    'OFFERS_AVAILABLE' => 'Offers available',
    'DRIVER_ASSIGNED' => 'Driver assigned',
    'DRIVER_EN_ROUTE' => 'Driver en route',
    'DRIVER_ARRIVED' => 'Driver arrived',
    'RIDE_STARTED' => 'In progress',
    'RIDE_COMPLETED' => 'Completed',
    'RIDE_CLOSED' => 'Closed',
    'CANCELLED' => 'Cancelled',
    'EXPIRED' => 'Expired',
    'NO_SHOW' => 'No-show',
    _ => state,
  };
}

String? formatMinorFare(int? minor, String? currency) {
  if (minor == null) return null;
  final code = currency ?? 'PKR';
  final major = minor / 100.0;
  final whole = major == major.roundToDouble()
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
  if (code.toUpperCase() == 'PKR') return 'Rs $whole';
  return '$whole $code';
}

String? formatHistoryTimestamp(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final local = parsed.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}
