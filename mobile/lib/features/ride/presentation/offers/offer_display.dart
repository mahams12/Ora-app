import '../../domain/entities/ride.dart';

/// Formats offer amounts from server minor units. Never invents fares.
String formatOfferAmountMinor(int amountMinor, String currency) {
  final major = amountMinor / 100.0;
  final whole = major == major.roundToDouble()
      ? major.toStringAsFixed(0)
      : major.toStringAsFixed(2);
  if (currency.toUpperCase() == 'PKR') {
    return 'Rs $whole';
  }
  return '$whole $currency';
}

/// Human label for an offer card — only uses real snapshot fields.
///
/// Backend currently seeds `driverSnapshot: { displayName: null, role: 'driver' }`.
/// When displayName is null we do **not** invent a name or rating.
String offerDriverLabel(RideOffer offer) {
  final snap = offer.driverSnapshot;
  final raw = snap?['displayName'];
  if (raw is String) {
    final name = raw.trim();
    if (name.isNotEmpty) return name;
  }
  return 'Driver offer';
}

bool isOfferSelectable(RideOffer offer) =>
    offer.status.toUpperCase() == 'PENDING';

bool isMarketplaceOpen(String rideState) {
  final s = rideState.toUpperCase();
  return s == 'SEARCHING' || s == 'OFFERS_AVAILABLE';
}

bool isAssignedOrBeyond(String rideState) {
  final s = rideState.toUpperCase();
  return s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED' ||
      s == 'RIDE_COMPLETED' ||
      s == 'RIDE_CLOSED';
}

bool isTerminalRideState(String rideState) {
  final s = rideState.toUpperCase();
  return s == 'CANCELLED' ||
      s == 'EXPIRED' ||
      s == 'NO_SHOW' ||
      s == 'RIDE_CLOSED' ||
      s == 'RIDE_COMPLETED';
}

/// Merge poll results by offerId (server wins). Preserves list order from server.
List<RideOffer> mergeOffersById(List<RideOffer> incoming) {
  final seen = <String>{};
  final out = <RideOffer>[];
  for (final o in incoming) {
    if (seen.add(o.offerId)) {
      out.add(o);
    }
  }
  return out;
}
