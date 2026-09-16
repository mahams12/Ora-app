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
  });

  /// Slice M — approved-driver open-ride discovery (GET /v1/rides/open).
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
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
    required String operationKey,
  });

  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  });

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
