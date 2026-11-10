/// Ride domain entities — Phase 2E/2F/2G (API projection only; server is authoritative).
library;

class LatLngPoint {
  const LatLngPoint({
    required this.lat,
    required this.lng,
    this.address,
  });

  final double lat;
  final double lng;
  final String? address;
}

/// Ora Courier v2 — one ordered itinerary stop (server projection).
class RideStop {
  const RideStop({
    required this.seq,
    required this.type,
    required this.location,
    required this.status,
    this.label,
    this.instructions,
    this.items,
    this.shopBudgetMinor,
    this.arrivedAt,
    this.doneAt,
    this.failedAt,
    this.failureReason,
    this.confirmedNearMeters,
    this.quote,
    this.purchase,
  });

  final int seq;

  /// PICKUP | SHOP | DROPOFF.
  final String type;
  final LatLngPoint location;

  /// PENDING | ARRIVED | WAITING_APPROVAL | DONE | FAILED | SKIPPED.
  final String status;
  final String? label;
  final String? instructions;

  /// buy_deliver — customer shopping list on SHOP stops.
  final List<Map<String, Object?>>? items;
  final int? shopBudgetMinor;
  final String? arrivedAt;
  final String? doneAt;
  final String? failedAt;
  final String? failureReason;
  final int? confirmedNearMeters;

  /// buy_deliver — driver quote: {items, totalMinor, quotedAt, approvedAt, rejectedAt}.
  final Map<String, Object?>? quote;

  /// buy_deliver — confirmed purchase: {totalMinor, confirmedAt}.
  final Map<String, Object?>? purchase;

  bool get isDone => status == 'DONE';
  bool get isFailed => status == 'FAILED' || status == 'SKIPPED';
  bool get awaitingApproval => status == 'WAITING_APPROVAL';
}

/// Immutable ride snapshot from GET/POST ride APIs.
class Ride {
  const Ride({
    required this.rideId,
    required this.passengerId,
    required this.state,
    required this.version,
    required this.requestVersion,
    required this.category,
    required this.serviceType,
    required this.pickup,
    required this.destination,
    required this.pricingSnapshotId,
    required this.recommendedFareMinor,
    required this.passengerOfferMinor,
    required this.paymentMethod,
    required this.passengerCount,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.assignedDriverId,
    this.agreedFareMinor,
    this.agreedOfferId,
    this.agreedFareCurrency,
    this.driverPayoutMinor,
    this.platformFeeMinor,
    this.payoutCurrency,
    this.feePolicyResolution,
    this.assignedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.closedAt,
    this.cancelledBy,
    this.cancellationReason,
    this.parcel,
    this.otpCodes,
    this.pickupPhotoUrl,
    this.deliveryFailedAt,
    this.deliveryFailedReason,
    this.returnStartedAt,
    this.returnedAt,
    this.courierProtocolVersion,
    this.stops,
    this.currentStopIndex,
    this.shopping,
    this.settlement,
    this.evidence,
    this.partialFulfillment,
    this.disputeStatus,
    this.disputeId,
  });

  final String rideId;
  final String passengerId;
  final String? assignedDriverId;
  final String state;
  final int version;
  final int requestVersion;
  final String category;
  final String serviceType;
  final LatLngPoint pickup;
  final LatLngPoint destination;
  final String pricingSnapshotId;
  final int recommendedFareMinor;
  final int passengerOfferMinor;
  final int? agreedFareMinor;
  final String? agreedOfferId;
  final String? agreedFareCurrency;

  /// Server-derived payout snapshot (immutable, set at offer selection).
  /// Null on rides selected before the payout model or when the policy
  /// resolution was UNAVAILABLE — earnings falls back to [agreedFareMinor]
  /// labelled "trip fare" in that case. Never trusted from client input.
  final int? driverPayoutMinor;
  final int? platformFeeMinor;
  final String? payoutCurrency;
  final String? feePolicyResolution;
  final String paymentMethod;
  final int passengerCount;
  final String expiresAt;
  final String? assignedAt;
  final String? arrivedAt;
  final String? startedAt;
  final String? completedAt;
  final String? closedAt;
  final String? cancelledBy;
  final String? cancellationReason;
  final String createdAt;
  final String updatedAt;

  /// Ora Courier — parcel manifest (present only when
  /// [serviceType] == 'courier'). Raw server projection.
  final Map<String, Object?>? parcel;

  /// Ora Courier — confirmation codes, exposed to the passenger only.
  /// Keys: pickup, delivery, return, expiresAt, pickupUsedAt,
  /// deliveryUsedAt, returnUsedAt.
  final Map<String, Object?>? otpCodes;

  /// Ora Courier — optional condition photo taken at pickup.
  final String? pickupPhotoUrl;

  /// Ora Courier — delivery failure bookkeeping.
  final String? deliveryFailedAt;
  final String? deliveryFailedReason;

  /// Ora Courier — return-to-sender bookkeeping.
  final String? returnStartedAt;
  final String? returnedAt;

  /// Ora Courier v2 — 1 = OTP-era, 2 = code-free stops protocol.
  final int? courierProtocolVersion;

  /// Ora Courier v2 — ordered itinerary (present on v2 bookings).
  final List<RideStop>? stops;
  final int? currentStopIndex;

  /// buy_deliver — {totalBudgetMinor, approvedTotalMinor, spentMinor,
  /// serviceFeeMinor, paymentArrangement, attestationAcceptedAt}.
  final Map<String, Object?>? shopping;

  /// Ora Courier v2 — server-computed cash breakdown + driver-reported status.
  final Map<String, Object?>? settlement;

  /// Ora Courier v2 — {confirms: [...], customerAckAt}.
  final Map<String, Object?>? evidence;
  final bool? partialFulfillment;
  final String? disputeStatus;
  final String? disputeId;

  bool get isCourier => serviceType == 'courier';
  bool get isBuyDeliver => serviceType == 'buy_deliver';
  bool get isDelivery => isCourier || isBuyDeliver;

  /// True when this booking uses the code-free v2 protocol.
  bool get isCourierV2 => courierProtocolVersion == 2 && stops != null;

  /// The next actionable stop, if any.
  RideStop? get currentStop {
    final idx = currentStopIndex;
    final list = stops;
    if (idx == null || list == null || idx < 0 || idx >= list.length) {
      return null;
    }
    return list[idx];
  }
}

/// Paginated ride history page from GET /v1/rides.
class RideListPage {
  const RideListPage({
    required this.rides,
    this.nextCursor,
  });

  final List<Ride> rides;
  final String? nextCursor;
}

/// Privacy-minimized open-ride discovery projection from GET /v1/rides/open.
///
/// Distinct from [Ride] — omits passenger/assignment internals. Do not parse
/// open discovery responses with the full ride mapper.
class OpenRide {
  const OpenRide({
    required this.rideId,
    required this.state,
    required this.requestVersion,
    required this.category,
    required this.serviceType,
    required this.pickup,
    required this.destination,
    required this.recommendedFareMinor,
    required this.passengerOfferMinor,
    required this.paymentMethod,
    required this.passengerCount,
    required this.expiresAt,
    required this.createdAt,
    this.distanceKm,
    this.estimatedDurationMin,
    this.parcel,
    this.stops,
    this.shopping,
  });

  final String rideId;
  final String state;
  final int requestVersion;
  final String category;
  final String serviceType;
  final LatLngPoint pickup;
  final LatLngPoint destination;
  final int recommendedFareMinor;
  final int passengerOfferMinor;
  final String paymentMethod;
  final int passengerCount;
  final double? distanceKm;
  final int? estimatedDurationMin;
  final String expiresAt;
  final String createdAt;

  /// Ora Courier — non-contact parcel summary on open discovery.
  final Map<String, Object?>? parcel;

  /// Ora Courier v2 — itinerary summary for driver offer evaluation.
  final List<RideStop>? stops;
  final Map<String, Object?>? shopping;
}

/// Paginated open-ride discovery page from GET /v1/rides/open.
class OpenRideListPage {
  const OpenRideListPage({
    required this.rides,
    this.nextCursor,
  });

  final List<OpenRide> rides;
  final String? nextCursor;
}

/// Driver invitation item from GET /v1/rides/invited.
///
/// The invitation is backed by a dispatch wave — `inviteExpiresAt` is the
/// single server-authoritative countdown deadline. `status` is the
/// server-computed classification: ACTIVE, EXPIRED, RESPONDED_ACCEPTED,
/// RESPONDED_DECLINED or CLOSED.
class DriverInvite {
  const DriverInvite({
    required this.rideId,
    required this.waveId,
    required this.waveNumber,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.passengerOfferMinor,
    required this.currency,
    required this.serviceType,
    required this.category,
    required this.passengerCount,
    this.inviteExpiresAt,
    this.respondedAt,
    this.offerId,
    this.distanceKm,
    this.parcel,
    this.stops,
    this.shopping,
  });

  final String rideId;
  final String waveId;
  final int waveNumber;
  final String status;
  final LatLngPoint pickup;
  final LatLngPoint destination;
  final int passengerOfferMinor;
  final String currency;
  final String serviceType;
  final String category;
  final int passengerCount;
  final DateTime? inviteExpiresAt;
  final String? respondedAt;
  final String? offerId;
  final double? distanceKm;

  /// Ora Courier — driver-visible parcel summary (no contact info).
  final Map<String, Object?>? parcel;

  /// Ora Courier v2 — itinerary + shopping budget for invite evaluation.
  final List<RideStop>? stops;
  final Map<String, Object?>? shopping;

  bool get isActionable => status == 'ACTIVE';
}

class DriverInvitePage {
  const DriverInvitePage({
    required this.items,
    required this.serverNowMs,
  });

  final List<DriverInvite> items;
  /// Server wall-clock at response time — used to offset client clock skew
  /// so countdowns stay consistent across devices/restarts.
  final int serverNowMs;
}

class RideOffer {
  const RideOffer({
    required this.offerId,
    required this.rideId,
    required this.driverId,
    required this.amountMinor,
    required this.currency,
    required this.type,
    required this.status,
    required this.requestVersion,
    required this.expiresAt,
    required this.createdAt,
    this.selectedAt,
    this.withdrawnAt,
    this.driverSnapshot,
  });

  final String offerId;
  final String rideId;
  final String driverId;
  final int amountMinor;
  final String currency;
  final String type;
  final String status;
  final int requestVersion;
  final String expiresAt;
  final String createdAt;
  final String? selectedAt;
  final String? withdrawnAt;
  final Map<String, Object?>? driverSnapshot;
}

class RideAssignment {
  const RideAssignment({
    required this.rideId,
    required this.state,
    required this.version,
    required this.assignedDriverId,
    required this.agreedFareMinor,
    required this.agreedOfferId,
    required this.currency,
  });

  final String rideId;
  final String state;
  final int version;
  final String assignedDriverId;
  final int agreedFareMinor;
  final String agreedOfferId;
  final String currency;
}

/// Phase 2N — caller's own rating from POST/GET /v1/rides/:rideId/ratings.
class RideRating {
  const RideRating({
    required this.ratingId,
    required this.rideId,
    required this.raterId,
    required this.ratedId,
    required this.ratingType,
    required this.stars,
    required this.createdAt,
  });

  final String ratingId;
  final String rideId;
  final String raterId;
  final String ratedId;
  final String ratingType;
  final int stars;
  final String createdAt;
}
