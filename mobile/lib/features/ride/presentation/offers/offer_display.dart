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

/// Whole PKR rupees for an editable offer field (integer major when exact).
String offerRupeesFieldText(int amountMinor) {
  final major = amountMinor / 100.0;
  if (major == major.roundToDouble()) {
    return major.toStringAsFixed(0);
  }
  return major.toStringAsFixed(2);
}

/// Parses passenger/driver-entered whole PKR rupees → paisas.
///
/// Rejects empty, non-integer, and non-positive input. No floating money math.
int? parseOfferRupeesToMinor(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final major = int.tryParse(trimmed);
  if (major == null || major <= 0) return null;
  return major * 100;
}

/// Result of validating a passenger offer draft against snapshot bounds.
enum PassengerOfferParseStatus {
  valid,
  empty,
  malformed,
  belowMinimum,
  aboveMaximum,
}

class PassengerOfferParseResult {
  const PassengerOfferParseResult._({
    required this.status,
    this.amountMinor,
    this.message,
  });

  final PassengerOfferParseStatus status;
  final int? amountMinor;
  final String? message;

  bool get isValid => status == PassengerOfferParseStatus.valid;

  factory PassengerOfferParseResult.valid(int amountMinor) =>
      PassengerOfferParseResult._(
        status: PassengerOfferParseStatus.valid,
        amountMinor: amountMinor,
      );

  factory PassengerOfferParseResult.invalid({
    required PassengerOfferParseStatus status,
    required String message,
  }) =>
      PassengerOfferParseResult._(status: status, message: message);
}

/// Validates draft rupees against server snapshot bounds (authoritative).
///
/// Does **not** clamp — out-of-range stays invalid with a message.
PassengerOfferParseResult validatePassengerOfferRupees({
  required String text,
  required int offerBoundMinMinor,
  required int offerBoundMaxMinor,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return PassengerOfferParseResult.invalid(
      status: PassengerOfferParseStatus.empty,
      message: 'Enter your offer amount in PKR.',
    );
  }
  final minor = parseOfferRupeesToMinor(trimmed);
  if (minor == null) {
    return PassengerOfferParseResult.invalid(
      status: PassengerOfferParseStatus.malformed,
      message: 'Enter a whole PKR amount (no decimals or letters).',
    );
  }
  if (minor < offerBoundMinMinor) {
    return PassengerOfferParseResult.invalid(
      status: PassengerOfferParseStatus.belowMinimum,
      message:
          'Offer is below the minimum ${formatOfferAmountMinor(offerBoundMinMinor, 'PKR')}.',
    );
  }
  if (minor > offerBoundMaxMinor) {
    return PassengerOfferParseResult.invalid(
      status: PassengerOfferParseStatus.aboveMaximum,
      message:
          'Offer is above the maximum ${formatOfferAmountMinor(offerBoundMaxMinor, 'PKR')}.',
    );
  }
  return PassengerOfferParseResult.valid(minor);
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
