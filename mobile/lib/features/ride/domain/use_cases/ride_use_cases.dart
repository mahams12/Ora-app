import '../entities/ride.dart';
import '../repositories/ride_repository.dart';

class CreateRideUseCase {
  const CreateRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required Map<String, Object?> body,
    required String operationKey,
  }) =>
      _repository.createRide(body: body, operationKey: operationKey);
}

class GetRideUseCase {
  const GetRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call(String rideId) => _repository.getRide(rideId);
}

class ListRidesUseCase {
  const ListRidesUseCase(this._repository);

  final RideRepository _repository;

  Future<RideListPage> call({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,
  }) =>
      _repository.listRides(
        limit: limit,
        cursor: cursor,
        status: status,
        serviceType: serviceType,
      );
}

class ListOpenRidesUseCase {
  const ListOpenRidesUseCase(this._repository);

  final RideRepository _repository;

  Future<OpenRideListPage> call({
    int? limit,
    String? cursor,
  }) =>
      _repository.listOpenRides(
        limit: limit,
        cursor: cursor,
      );
}

class ListOffersUseCase {
  const ListOffersUseCase(this._repository);

  final RideRepository _repository;

  Future<List<RideOffer>> call(String rideId) =>
      _repository.listOffers(rideId);
}

class CreateOfferUseCase {
  const CreateOfferUseCase(this._repository);

  final RideRepository _repository;

  Future<RideOffer> call({
    required String rideId,
    required Map<String, Object?> body,
    required String operationKey,
  }) =>
      _repository.createOffer(
        rideId: rideId,
        body: body,
        operationKey: operationKey,
      );
}

class WithdrawOfferUseCase {
  const WithdrawOfferUseCase(this._repository);

  final RideRepository _repository;

  Future<RideOffer> call({
    required String rideId,
    required String offerId,
    required String operationKey,
  }) =>
      _repository.withdrawOffer(
        rideId: rideId,
        offerId: offerId,
        operationKey: operationKey,
      );
}

class SelectOfferUseCase {
  const SelectOfferUseCase(this._repository);

  final RideRepository _repository;

  Future<RideAssignment> call({
    required String rideId,
    required String offerId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.selectOffer(
        rideId: rideId,
        offerId: offerId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class CancelRideUseCase {
  const CancelRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    String? reason,
    required String operationKey,
  }) =>
      _repository.cancelRide(
        rideId: rideId,
        reason: reason,
        operationKey: operationKey,
      );
}

class MarkEnRouteUseCase {
  const MarkEnRouteUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.markEnRoute(
        rideId: rideId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class MarkArrivedUseCase {
  const MarkArrivedUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.markArrived(
        rideId: rideId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class StartRideUseCase {
  const StartRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.startRide(
        rideId: rideId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class CompleteRideUseCase {
  const CompleteRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.completeRide(
        rideId: rideId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class CloseRideUseCase {
  const CloseRideUseCase(this._repository);

  final RideRepository _repository;

  Future<Ride> call({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) =>
      _repository.closeRide(
        rideId: rideId,
        expectedVersion: expectedVersion,
        operationKey: operationKey,
      );
}

class SubmitRatingUseCase {
  const SubmitRatingUseCase(this._repository);

  final RideRepository _repository;

  Future<RideRating> call({
    required String rideId,
    required int stars,
    required String operationKey,
  }) =>
      _repository.submitRating(
        rideId: rideId,
        stars: stars,
        operationKey: operationKey,
      );
}

class GetMyRatingUseCase {
  const GetMyRatingUseCase(this._repository);

  final RideRepository _repository;

  Future<RideRating> call(String rideId) => _repository.getMyRating(rideId);
}
