/// Open-ride discovery presentation helpers — server fields only.
library;

import '../../ride/domain/entities/ride.dart';
import '../../ride/presentation/history/ride_history_display.dart';
import '../../ride/presentation/offers/offer_display.dart';

const openRidesDefaultLimit = 10;

/// Verified Ora ride-money currency (not inferred from open DTO fields).
///
/// Evidence:
/// - `backend/.../money.ts` `assertCurrency` accepts only `PKR`
/// - pricing snapshots require `currency === 'PKR'`
/// - offer create persists `currency: 'PKR'`
/// - `docs/api/ride-api.md`: amounts are integer minor units (paisas)
///
/// Open-ride DTO omits `currency`, but `passengerOfferMinor` /
/// `recommendedFareMinor` are the same PKR-paisa amounts as the rest of the
/// ride money contract. Display must reuse [formatOfferAmountMinor], not a
/// bespoke `/100` helper.
const oraRideMoneyCurrencyCode = 'PKR';

String openRideStateLabel(String state) {
  return switch (state.toUpperCase()) {
    'SEARCHING' => 'Searching',
    'OFFERS_AVAILABLE' => 'Offers available',
    _ => state,
  };
}

String openRideServiceLine(OpenRide ride) {
  return [
    historyServiceTypeLabel(ride.serviceType),
    '·',
    ride.category,
  ].join(' ');
}

/// Location line — real address when present; never invents place names.
///
/// Does not expose raw coordinates to normal users. Legacy GPS placeholder
/// `"Current location"` maps to [fallback] (typically "Location selected").
String openRideLocationLabel(LatLngPoint point, {required String fallback}) {
  final address = point.address?.trim();
  if (address == null || address.isEmpty) return fallback;
  if (address.toLowerCase() == 'current location') return fallback;
  return address;
}

/// Formats open-ride fare minors via the canonical offer money formatter.
String formatOpenRideFareMinor(int minor) =>
    formatOfferAmountMinor(minor, oraRideMoneyCurrencyCode);

/// Driver offer sheet entry — whole PKR rupees when exact, else 2 decimals.
String openRideOfferRupeesFieldText(int amountMinor) {
  final major = amountMinor / 100.0;
  if (major == major.roundToDouble()) {
    return major.toStringAsFixed(0);
  }
  return major.toStringAsFixed(2);
}

/// Parses driver-entered PKR rupees to server minor units (paisas).
int? parseOpenRideOfferRupeesToMinor(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final major = int.tryParse(trimmed);
  if (major == null || major <= 0) return null;
  return major * 100;
}

String? formatOpenRideDistanceKm(double? km) {
  if (km == null) return null;
  final whole = km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1);
  return '$whole km (server)';
}

String? formatOpenRideDurationMin(int? minutes) {
  if (minutes == null) return null;
  return '$minutes min (server)';
}

String? openRideExpiresLabel(String expiresAt, {DateTime? now}) {
  final parsed = DateTime.tryParse(expiresAt);
  if (parsed == null) return null;
  final clock = now ?? DateTime.now();
  final delta = parsed.difference(clock);
  if (delta.isNegative) return 'Expired on server';
  final mins = delta.inMinutes;
  if (mins < 1) return 'Expires in under 1 min';
  if (mins < 60) return 'Expires in $mins min';
  return 'Expires ${formatHistoryTimestamp(expiresAt) ?? expiresAt}';
}
