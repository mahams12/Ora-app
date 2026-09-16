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
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides',
      queryParameters: {
        if (limit != null) 'limit': limit,
        if (cursor != null) 'cursor': cursor,
        if (status != null) 'status': status,
        if (serviceType != null) 'serviceType': serviceType,
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
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/rides/open',
      queryParameters: {
        if (limit != null) 'limit': limit,
        if (cursor != null) 'cursor': cursor,
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
      estimatedDurationMin: json['estimatedDurationMin'] as int?,
      expiresAt: json['expiresAt'] as String,
      createdAt: json['createdAt'] as String,
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
