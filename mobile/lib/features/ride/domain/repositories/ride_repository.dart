import '../../domain/entities/ride.dart';

abstract interface class RideRepository {
  Future<Ride> createRide({
    required Map<String, Object?> body,
    required String operationKey,
  });

  Future<Ride> getRide(String rideId);

  Future<RideListPage> listRides({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,

    /// Dual-role accounts (Switch to Driver) pick which history view:
    /// 'passenger' → own bookings, 'driver' → assigned jobs.
    String? as,
  });

  /// Dispatch-wave invitations for this driver (GET /v1/rides/invited).
  Future<DriverInvitePage> listInvited();

  /// Accept an invitation — server creates a PASSENGER_PRICE_ACCEPTED offer
  /// at the passenger's offered amount. Returns the offer id. Server-side
  /// idempotent; safe to retry.
  Future<String> acceptInvite({
    required String rideId,
    required String waveId,
  });

  /// Decline an invitation — durable server-side record, idempotent.
  Future<void> declineInvite({
    required String rideId,
    required String waveId,
  });

  /// Slice M — approved-driver open-ride discovery (GET /v1/rides/open).
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
    String? serviceType,
    String? category,
  });

  Future<List<RideOffer>> listOffers(String rideId);

  Future<RideOffer> createOffer({
    required String rideId,
    required Map<String, Object?> body,
    required String operationKey,
  });

  Future<RideOffer> withdrawOffer({
    required String rideId,
    required String offerId,
    required String operationKey,
  });

  Future<RideAssignment> selectOffer({
    required String rideId,
    required String offerId,
    int? expectedVersion,
    required String operationKey,
  });

  Future<Ride> cancelRide({
    required String rideId,
    String? reason,
    required String operationKey,
  });

  Future<Ride> markEnRoute({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  Future<Ride> markArrived({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  Future<Ride> startRide({
    required String rideId,
    int? expectedVersion,
    String? otp,
    String? pickupPhotoUrl,
    required String operationKey,
  });

  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  });

  /// Ora Courier — report a failed delivery attempt.
  Future<Ride> failDelivery({
    required String rideId,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  });

  /// Ora Courier — retry delivery after a failed attempt.
  Future<Ride> retryDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  /// Ora Courier — start returning the parcel to the sender.
  Future<Ride> startReturn({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  /// Ora Courier — sender confirms the parcel was returned (return code).
  Future<Ride> completeReturn({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  });

  // ── Ora Courier v2 — code-free multi-stop progression ──────────────

  /// Driver marks arrival at stop `seq` (PICKUP | SHOP | DROPOFF).
  Future<Ride> arriveStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String operationKey,
  });

  /// Driver confirms completion of stop `seq` — collected parcel / purchased
  /// items / delivered. `purchaseTotalMinor` is required on SHOP confirms.
  Future<Ride> confirmStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    int? purchaseTotalMinor,
    required String operationKey,
  });

  /// Driver reports a failed stop (`reason` is a server enum string).
  Future<Ride> failStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  });

  /// buy_deliver — driver submits an itemized quote for a SHOP stop.
  /// `items` = [{name, qty, priceMinor}].
  Future<Ride> submitStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required List<Map<String, Object?>> items,
    required String operationKey,
  });

  /// buy_deliver — customer approves or rejects the driver's quote.
  Future<Ride> respondToStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required bool approve,
    required String operationKey,
  });

  /// Driver reports cash collection outcome: PAID | UNPAID | PARTIAL.
  Future<Ride> reportSettlement({
    required String rideId,
    int? expectedVersion,
    required String status,
    required String operationKey,
  });

  /// Customer acknowledges receipt (server records an audit timestamp).
  Future<Ride> acknowledgeDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  /// Either party opens a dispute within the configured window
  /// (post-conclusion only). `category` is a server enum; `message` is
  /// free text up to 1000 chars.
  Future<Ride> createDispute({
    required String rideId,
    required String category,
    required String message,
    required String operationKey,
  });

  /// Client-visible delivery limits/flags (maxStops, budget caps, gates).
  Future<Map<String, Object?>> getDeliveryConfig();

  Future<Ride> closeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    required String operationKey,
  });

  Future<RideRating> getMyRating(String rideId);
}
