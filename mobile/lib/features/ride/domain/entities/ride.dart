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
    this.assignedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.closedAt,
    this.cancelledBy,
    this.cancellationReason,
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
