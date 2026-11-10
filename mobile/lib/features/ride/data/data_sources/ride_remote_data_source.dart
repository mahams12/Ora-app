import '../../../../core/network/api_client.dart';
import '../../../../core/network/request_context.dart';
import '../../domain/entities/ride.dart';

/// HTTP data source for Phase 2E ride APIs. Never talks to Firestore.
class RideRemoteDataSource {
  const RideRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Ride> createRide({
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> getRide({
    required String rideId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/$rideId',
      context: context,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<RideListPage> listRides({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,
    String? as,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides',
      queryParameters: {
        if (limit != null) 'limit': limit,
        if (cursor != null) 'cursor': cursor,
        if (status != null) 'status': status,
        if (serviceType != null) 'serviceType': serviceType,
        if (as != null) 'as': as,
      },
      context: context,
    );
    final data = _unwrapData(response.data);
    final raw = data['rides'];
    final rides = raw is List
        ? raw
            .whereType<Map<Object?, Object?>>()
            .map((e) => _parseRide(Map<String, dynamic>.from(e)))
            .toList()
        : const <Ride>[];
    final next = data['nextCursor'];
    return RideListPage(
      rides: rides,
      nextCursor: next is String ? next : null,
    );
  }

  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
    String? serviceType,
    String? category,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/open',
      queryParameters: {
        if (limit != null) 'limit': limit,
        if (cursor != null) 'cursor': cursor,
        if (serviceType != null) 'serviceType': serviceType,
        if (category != null) 'category': category,
      },
      context: context,
    );
    final data = _unwrapData(response.data);
    final raw = data['rides'];
    final rides = raw is List
        ? raw
            .whereType<Map<Object?, Object?>>()
            .map((e) => _parseOpenRide(Map<String, dynamic>.from(e)))
            .toList()
        : const <OpenRide>[];
    final next = data['nextCursor'];
    return OpenRideListPage(
      rides: rides,
      nextCursor: next is String ? next : null,
    );
  }

  /// GET /v1/rides/invited — dispatch-wave invitations for this driver.
  Future<DriverInvitePage> listInvited({
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/invited',
      context: context,
    );
    final data = _unwrapData(response.data);
    final raw = data['items'];
    final items = raw is List
        ? raw
            .whereType<Map<Object?, Object?>>()
            .map((e) => _parseDriverInvite(Map<String, dynamic>.from(e)))
            .toList()
        : const <DriverInvite>[];
    final serverNow = data['serverNowMs'];
    return DriverInvitePage(
      items: items,
      serverNowMs: serverNow is num ? serverNow.toInt() : 0,
    );
  }

  /// POST /v1/rides/:rideId/invites/:waveId/accept — server creates the
  /// PASSENGER_PRICE_ACCEPTED offer. Returns the offer id (works for both
  /// the 201 created body and the idempotent replay shape).
  Future<String> acceptInvite({
    required String rideId,
    required String waveId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/invites/$waveId/accept',
      context: context,
      idempotent: true,
    );
    final data = _unwrapData(response.data);
    final offerId = data['offerId'];
    return offerId is String ? offerId : '';
  }

  /// POST /v1/rides/:rideId/invites/:waveId/decline — durable, idempotent.
  Future<void> declineInvite({
    required String rideId,
    required String waveId,
    required RequestContext context,
  }) async {
    await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/invites/$waveId/decline',
      context: context,
      idempotent: true,
    );
  }

  Future<List<RideOffer>> listOffers({
    required String rideId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/$rideId/offers',
      context: context,
    );
    final data = _unwrapData(response.data);
    final raw = data['offers'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((e) => _parseOffer(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<RideOffer> createOffer({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/offers',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseOffer(_unwrapData(response.data));
  }

  Future<RideOffer> withdrawOffer({
    required String rideId,
    required String offerId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/offers/$offerId/withdraw',
      context: context,
      idempotent: true,
    );
    return _parseOffer(_unwrapData(response.data));
  }

  Future<RideAssignment> selectOffer({
    required String rideId,
    required String offerId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/offers/$offerId/select',
      data: body,
      context: context,
      idempotent: true,
    );
    final data = _unwrapData(response.data);
    return RideAssignment(
      rideId: data['rideId'] as String,
      state: data['state'] as String,
      version: data['version'] as int,
      assignedDriverId: data['assignedDriverId'] as String,
      agreedFareMinor: data['agreedFareMinor'] as int,
      agreedOfferId: data['agreedOfferId'] as String,
      currency: data['currency'] as String,
    );
  }

  Future<Ride> cancelRide({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/cancel',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> markEnRoute({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/en-route',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> markArrived({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/arrive',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> startRide({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/start',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> completeRide({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/complete',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  /// Ora Courier — driver reports a failed delivery attempt.
  Future<Ride> failDelivery({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/delivery-failed',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  /// Ora Courier — driver retries delivery after a failed attempt.
  Future<Ride> retryDelivery({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/retry-delivery',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  /// Ora Courier — driver begins returning the parcel to the sender.
  Future<Ride> startReturn({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/return-start',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  /// Ora Courier — sender confirms the parcel came back (return code).
  Future<Ride> completeReturn({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/return-complete',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> closeRide({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/close',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  // ── Ora Courier v2 — code-free multi-stop progression ──────────────

  Future<Ride> _stopAction({
    required String rideId,
    required int seq,
    required String action,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/stops/$seq/$action',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> arriveStop({
    required String rideId,
    required int seq,
    required Map<String, Object?> body,
    required RequestContext context,
  }) => _stopAction(
        rideId: rideId,
        seq: seq,
        action: 'arrive',
        body: body,
        context: context,
      );

  Future<Ride> confirmStop({
    required String rideId,
    required int seq,
    required Map<String, Object?> body,
    required RequestContext context,
  }) => _stopAction(
        rideId: rideId,
        seq: seq,
        action: 'confirm',
        body: body,
        context: context,
      );

  Future<Ride> failStop({
    required String rideId,
    required int seq,
    required Map<String, Object?> body,
    required RequestContext context,
  }) => _stopAction(
        rideId: rideId,
        seq: seq,
        action: 'fail',
        body: body,
        context: context,
      );

  Future<Ride> submitStopQuote({
    required String rideId,
    required int seq,
    required Map<String, Object?> body,
    required RequestContext context,
  }) => _stopAction(
        rideId: rideId,
        seq: seq,
        action: 'quote',
        body: body,
        context: context,
      );

  Future<Ride> respondToStopQuote({
    required String rideId,
    required int seq,
    required Map<String, Object?> body,
    required RequestContext context,
  }) => _stopAction(
        rideId: rideId,
        seq: seq,
        action: 'quote-response',
        body: body,
        context: context,
      );

  Future<Ride> reportSettlement({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/settlement',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> acknowledgeDelivery({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/acknowledge',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  Future<Ride> createDispute({
    required String rideId,
    required Map<String, Object?> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/disputes',
      data: body,
      context: context,
      idempotent: true,
    );
    return _parseRide(_unwrapData(response.data));
  }

  /// Client-visible delivery limits/flags (maxStops, budget cap, gates).
  Future<Map<String, Object?>> getDeliveryConfig({
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/delivery-config',
      context: context,
    );
    final data = _unwrapData(response.data);
    return Map<String, Object?>.from(data);
  }

  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/rides/$rideId/ratings',
      data: {'stars': stars},
      context: context,
      idempotent: true,
    );
    return _parseRating(_unwrapData(response.data));
  }

  Future<RideRating> getMyRating({
    required String rideId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/$rideId/ratings',
      context: context,
    );
    return _parseRating(_unwrapData(response.data));
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic>? envelope) {
    if (envelope == null) {
      throw StateError('Empty ride API response');
    }
    final data = envelope['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    // Some clients may already unwrap; accept flat map if rideId present.
    if (envelope.containsKey('rideId') || envelope.containsKey('offerId')) {
      return envelope;
    }
    throw StateError('Ride API envelope missing data');
  }

  List<RideStop>? _parseStops(Object? raw) {
    if (raw is! List) return null;
    return raw.map((e) {
      final s = Map<String, dynamic>.from(e as Map);
      return RideStop(
        seq: (s['seq'] as num).toInt(),
        type: s['type'] as String,
        location:
            _parseLatLng(Map<Object?, Object?>.from(s['location'] as Map)),
        status: s['status'] as String? ?? 'PENDING',
        label: s['label'] as String?,
        instructions: s['instructions'] as String?,
        items: s['items'] is List
            ? (s['items'] as List)
                .map((i) => Map<String, Object?>.from(i as Map))
                .toList()
            : null,
        shopBudgetMinor: s['shopBudgetMinor'] as int?,
        arrivedAt: s['arrivedAt'] as String?,
        doneAt: s['doneAt'] as String?,
        failedAt: s['failedAt'] as String?,
        failureReason: s['failureReason'] as String?,
        confirmedNearMeters: s['confirmedNearMeters'] as int?,
        quote: s['quote'] is Map
            ? Map<String, Object?>.from(s['quote'] as Map)
            : null,
        purchase: s['purchase'] is Map
            ? Map<String, Object?>.from(s['purchase'] as Map)
            : null,
      );
    }).toList();
  }

  Map<String, Object?>? _mapOrNull(Object? raw) =>
      raw is Map ? Map<String, Object?>.from(raw) : null;

  OpenRide _parseOpenRide(Map<String, dynamic> json) {
    return OpenRide(
      rideId: json['rideId'] as String,
      state: json['state'] as String,
      requestVersion: json['requestVersion'] as int,
      category: json['category'] as String,
      serviceType: json['serviceType'] as String,
      pickup: _parseLatLng(Map<Object?, Object?>.from(json['pickup'] as Map)),
      destination: _parseLatLng(
        Map<Object?, Object?>.from(json['destination'] as Map),
      ),
      recommendedFareMinor: json['recommendedFareMinor'] as int,
      passengerOfferMinor: json['passengerOfferMinor'] as int,
      paymentMethod: json['paymentMethod'] as String,
      passengerCount: json['passengerCount'] as int,
      distanceKm: json['distanceKm'] == null
          ? null
          : (json['distanceKm'] as num).toDouble(),
      estimatedDurationMin: _optionalRoundedInt(json['estimatedDurationMin']),
      expiresAt: json['expiresAt'] as String,
      createdAt: json['createdAt'] as String,
      parcel: json['parcel'] is Map
          ? Map<String, Object?>.from(json['parcel'] as Map)
          : null,
      stops: _parseStops(json['stops']),
      shopping: _mapOrNull(json['shopping']),
    );
  }

  DriverInvite _parseDriverInvite(Map<String, dynamic> json) {
    final rawExpiry = json['inviteExpiresAt'];
    return DriverInvite(
      rideId: json['rideId'] as String,
      waveId: json['waveId'] as String,
      waveNumber: (json['waveNumber'] as num).toInt(),
      status: json['status'] as String,
      pickup: _parseLatLng(Map<Object?, Object?>.from(json['pickup'] as Map)),
      destination: _parseLatLng(
        Map<Object?, Object?>.from(json['destination'] as Map),
      ),
      passengerOfferMinor: json['passengerOfferMinor'] as int,
      currency: json['currency'] as String? ?? 'PKR',
      serviceType: json['serviceType'] as String,
      category: json['category'] as String,
      passengerCount: json['passengerCount'] as int,
      inviteExpiresAt:
          rawExpiry is String ? DateTime.tryParse(rawExpiry) : null,
      respondedAt: json['respondedAt'] as String?,
      offerId: json['offerId'] as String?,
      distanceKm: json['distanceKm'] == null
          ? null
          : (json['distanceKm'] as num).toDouble(),
      parcel: json['parcel'] is Map
          ? Map<String, Object?>.from(json['parcel'] as Map)
          : null,
      stops: _parseStops(json['stops']),
      shopping: _mapOrNull(json['shopping']),
    );
  }

  Ride _parseRide(Map<String, dynamic> json) {
    return Ride(
      rideId: json['rideId'] as String,
      passengerId: json['passengerId'] as String,
      assignedDriverId: json['assignedDriverId'] as String?,
      state: json['state'] as String,
      version: json['version'] as int,
      requestVersion: json['requestVersion'] as int,
      category: json['category'] as String,
      serviceType: json['serviceType'] as String,
      pickup: _parseLatLng(Map<Object?, Object?>.from(json['pickup'] as Map)),
      destination: _parseLatLng(
        Map<Object?, Object?>.from(json['destination'] as Map),
      ),
      pricingSnapshotId: json['pricingSnapshotId'] as String,
      recommendedFareMinor: json['recommendedFareMinor'] as int,
      passengerOfferMinor: json['passengerOfferMinor'] as int,
      agreedFareMinor: json['agreedFareMinor'] as int?,
      agreedOfferId: json['agreedOfferId'] as String?,
      agreedFareCurrency: json['agreedFareCurrency'] as String?,
      driverPayoutMinor: json['driverPayoutMinor'] as int?,
      platformFeeMinor: json['platformFeeMinor'] as int?,
      payoutCurrency: json['payoutCurrency'] as String?,
      feePolicyResolution: json['feePolicyResolution'] as String?,
      paymentMethod: json['paymentMethod'] as String,
      passengerCount: json['passengerCount'] as int,
      expiresAt: json['expiresAt'] as String,
      assignedAt: json['assignedAt'] as String?,
      arrivedAt: json['arrivedAt'] as String?,
      startedAt: json['startedAt'] as String?,
      completedAt: json['completedAt'] as String?,
      closedAt: json['closedAt'] as String?,
      cancelledBy: json['cancelledBy'] as String?,
      cancellationReason: json['cancellationReason'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      parcel: json['parcel'] is Map
          ? Map<String, Object?>.from(json['parcel'] as Map)
          : null,
      otpCodes: json['otpCodes'] is Map
          ? Map<String, Object?>.from(json['otpCodes'] as Map)
          : null,
      pickupPhotoUrl: json['pickupPhotoUrl'] as String?,
      deliveryFailedAt: json['deliveryFailedAt'] as String?,
      deliveryFailedReason: json['deliveryFailedReason'] as String?,
      returnStartedAt: json['returnStartedAt'] as String?,
      returnedAt: json['returnedAt'] as String?,
      courierProtocolVersion: json['courierProtocolVersion'] as int?,
      stops: _parseStops(json['stops']),
      currentStopIndex: json['currentStopIndex'] as int?,
      shopping: _mapOrNull(json['shopping']),
      settlement: _mapOrNull(json['settlement']),
      evidence: _mapOrNull(json['evidence']),
      partialFulfillment: json['partialFulfillment'] as bool?,
      disputeStatus: json['disputeStatus'] as String?,
      disputeId: json['disputeId'] as String?,
    );
  }

  RideOffer _parseOffer(Map<String, dynamic> json) {
    return RideOffer(
      offerId: json['offerId'] as String,
      rideId: json['rideId'] as String,
      driverId: json['driverId'] as String,
      amountMinor: json['amountMinor'] as int,
      currency: json['currency'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      requestVersion: json['requestVersion'] as int,
      expiresAt: json['expiresAt'] as String,
      createdAt: json['createdAt'] as String,
      selectedAt: json['selectedAt'] as String?,
      withdrawnAt: json['withdrawnAt'] as String?,
      driverSnapshot: json['driverSnapshot'] is Map
          ? Map<String, Object?>.from(json['driverSnapshot'] as Map)
          : null,
    );
  }

  RideRating _parseRating(Map<String, dynamic> json) {
    return RideRating(
      ratingId: json['ratingId'] as String,
      rideId: json['rideId'] as String,
      raterId: json['raterId'] as String,
      ratedId: json['ratedId'] as String,
      ratingType: json['ratingType'] as String,
      stars: json['stars'] as int,
      createdAt: json['createdAt'] as String,
    );
  }

  LatLngPoint _parseLatLng(Map<Object?, Object?> raw) {
    return LatLngPoint(
      lat: (raw['lat'] as num).toDouble(),
      lng: (raw['lng'] as num).toDouble(),
      address: raw['address'] as String?,
    );
  }
}

int? _optionalRoundedInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}
