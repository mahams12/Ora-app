/// Driver earnings summary — pure aggregation over completed rides.
///
/// AUTHORITATIVE-DATA CONTRACT (read before editing):
/// - Preferred field: [Ride.driverPayoutMinor] — the server-derived payout
///   snapshot written atomically at offer selection (launch policy: fee NONE,
///   payout == agreed fare). Labelled "Driver payout" in the UI.
/// - Fallback field: [Ride.agreedFareMinor] — gross trip fare on rides
///   selected before the payout model or whose resolution was UNAVAILABLE.
///   Labelled "Trip fare" — never "net earnings" or "profit".
/// - The two bases are summed separately and never conflated into one total.
/// - Rides completed without either value are counted separately so totals
///   are never silently understated.
library;

import '../../ride/domain/entities/ride.dart';

/// States the backend treats as "completed" (see list_query.dart
/// `completedStates()`): RIDE_COMPLETED and RIDE_CLOSED only.
bool isDriverEarningsCompletedState(String state) {
  final s = state.toUpperCase();
  return s == 'RIDE_COMPLETED' || s == 'RIDE_CLOSED';
}

class DriverEarningsPeriod {
  const DriverEarningsPeriod({
    required this.rideCount,
    required this.faresMinor,
    required this.currency,
    required this.payoutRideCount,
    required this.payoutMinor,
    required this.fareOnlyMinor,
  });

  /// Completed rides in the window (including those without a recorded fare).
  final int rideCount;

  /// Sum of the effective per-ride amount: `driverPayoutMinor` when the
  /// server-derived payout snapshot exists, else `agreedFareMinor`.
  /// Zero when no ride in the window carried a value.
  final int faresMinor;

  /// Currency when all summed values share one code; null when mixed or none.
  final String? currency;

  /// Rides in the window carrying an authoritative `driverPayoutMinor`.
  final int payoutRideCount;

  /// Sum of `driverPayoutMinor` over payout-backed rides only.
  final int payoutMinor;

  /// Sum of `agreedFareMinor` over rides lacking a payout snapshot — the
  /// "trip fare" fallback basis for pre-model rides.
  final int fareOnlyMinor;
}

class DriverEarningsSummary {
  const DriverEarningsSummary({
    required this.completedRideCount,
    required this.ridesWithFare,
    required this.ridesWithPayout,
    required this.ridesMissingFare,
    required this.today,
    required this.last7Days,
    required this.allTime,
  });

  final int completedRideCount;

  /// Rides with a verified `agreedFareMinor`.
  final int ridesWithFare;

  /// Rides with a server-derived `driverPayoutMinor` (payout-backed).
  final int ridesWithPayout;

  /// Completed rides lacking both payout and fare — excluded from totals.
  final int ridesMissingFare;

  /// Completed on the same local calendar day as `now`.
  final DriverEarningsPeriod today;

  /// Completed within the trailing 7×24h window ending at `now`.
  final DriverEarningsPeriod last7Days;

  /// All completed rides in the loaded history.
  final DriverEarningsPeriod allTime;
}

/// Best available completion instant: when the trip actually ended.
/// Falls back to closed/updated/created when a completed stamp is absent —
/// never invents a date.
DateTime? driverEarningsCompletionTime(Ride ride) {
  for (final iso in [
    ride.completedAt,
    ride.closedAt,
    ride.updatedAt,
    ride.createdAt,
  ]) {
    if (iso == null || iso.isEmpty) continue;
    final parsed = DateTime.tryParse(iso);
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

/// Aggregates verified completed-ride fares. [now] is injectable for tests.
DriverEarningsSummary computeDriverEarnings(
  List<Ride> rides, {
  DateTime? now,
}) {
  final effectiveNow = (now ?? DateTime.now()).toLocal();
  final dayStart =
      DateTime(effectiveNow.year, effectiveNow.month, effectiveNow.day);
  final weekStart = effectiveNow.subtract(const Duration(days: 7));

  var completed = 0;
  var withFare = 0;
  var withPayout = 0;
  var missingFare = 0;

  var todayCount = 0;
  var todayMinor = 0;
  var todayPayoutCount = 0;
  var todayPayoutMinor = 0;
  var todayFareOnly = 0;
  var weekCount = 0;
  var weekMinor = 0;
  var weekPayoutCount = 0;
  var weekPayoutMinor = 0;
  var weekFareOnly = 0;
  var allCount = 0;
  var allMinor = 0;
  var allPayoutCount = 0;
  var allPayoutMinor = 0;
  var allFareOnly = 0;

  String? currency;
  var currencyMixed = false;

  for (final ride in rides) {
    if (!isDriverEarningsCompletedState(ride.state)) continue;
    completed++;

    // Effective amount: authoritative payout snapshot when present, else the
    // recorded trip fare. The bases are tracked separately so the UI can
    // label "Driver payout" vs "Trip fare" honestly.
    final payout = ride.driverPayoutMinor;
    final fare = ride.agreedFareMinor;
    final int? effective;
    if (payout != null) {
      effective = payout;
      withPayout++;
      final rideCurrency = ride.payoutCurrency ?? 'PKR';
      if (currency == null) {
        currency = rideCurrency;
      } else if (rideCurrency != currency) {
        currencyMixed = true;
      }
    } else if (fare != null) {
      effective = fare;
      withFare++;
      final rideCurrency = ride.agreedFareCurrency ?? 'PKR';
      if (currency == null) {
        currency = rideCurrency;
      } else if (rideCurrency != currency) {
        currencyMixed = true;
      }
    } else {
      effective = null;
      missingFare++;
    }

    final at = driverEarningsCompletionTime(ride);
    final inToday = at != null && !at.isBefore(dayStart);
    final inWeek = at != null && !at.isBefore(weekStart);

    allCount++;
    if (inWeek) weekCount++;
    if (inToday) todayCount++;
    if (effective != null) {
      allMinor += effective;
      if (payout != null) {
        allPayoutCount++;
        allPayoutMinor += effective;
      } else {
        allFareOnly += effective;
      }
      if (inWeek) {
        weekMinor += effective;
        if (payout != null) {
          weekPayoutCount++;
          weekPayoutMinor += effective;
        } else {
          weekFareOnly += effective;
        }
      }
      if (inToday) {
        todayMinor += effective;
        if (payout != null) {
          todayPayoutCount++;
          todayPayoutMinor += effective;
        } else {
          todayFareOnly += effective;
        }
      }
    }
  }

  final uniform = currencyMixed ? null : currency;
  return DriverEarningsSummary(
    completedRideCount: completed,
    ridesWithFare: withFare,
    ridesWithPayout: withPayout,
    ridesMissingFare: missingFare,
    today: DriverEarningsPeriod(
      rideCount: todayCount,
      faresMinor: todayMinor,
      currency: uniform,
      payoutRideCount: todayPayoutCount,
      payoutMinor: todayPayoutMinor,
      fareOnlyMinor: todayFareOnly,
    ),
    last7Days: DriverEarningsPeriod(
      rideCount: weekCount,
      faresMinor: weekMinor,
      currency: uniform,
      payoutRideCount: weekPayoutCount,
      payoutMinor: weekPayoutMinor,
      fareOnlyMinor: weekFareOnly,
    ),
    allTime: DriverEarningsPeriod(
      rideCount: allCount,
      faresMinor: allMinor,
      currency: uniform,
      payoutRideCount: allPayoutCount,
      payoutMinor: allPayoutMinor,
      fareOnlyMinor: allFareOnly,
    ),
  );
}
