import '../../../../core/network/api_client.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../domain/entities/ride.dart';
import '../../domain/repositories/ride_repository.dart';
import '../data_sources/ride_remote_data_source.dart';

/// API-only ride repository. Local state is never fabricated for assignment.
class RideRepositoryImpl implements RideRepository {
  RideRepositoryImpl({
    required RideRemoteDataSource remote,
    required ApiClient apiClient,
    required IdempotencyNonceStore nonceStore,
  })  : _remote = remote,
        _apiClient = apiClient,
        _nonceStore = nonceStore;

  final RideRemoteDataSource _remote;
  final ApiClient _apiClient;
  final IdempotencyNonceStore _nonceStore;

  Future<T> _withNonce<T>({
    required String operationKey,
    required Future<T> Function(String nonce) run,
    required bool Function(T result) isTerminalSuccess,
  }) async {
    final nonce = await _nonceStore.getOrCreate(operationKey);
    final result = await run(nonce);
    if (isTerminalSuccess(result)) {
      await _nonceStore.clear(operationKey);
    }
    return result;
  }

  @override
  Future<Ride> createRide({
    required Map<String, Object?> body,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.rideId.isNotEmpty,
      run: (nonce) => _remote.createRide(
        body: body,
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> getRide(String rideId) {
    return _remote.getRide(
      rideId: rideId,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<RideListPage> listRides({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,
  }) {
    return _remote.listRides(
      limit: limit,
      cursor: cursor,
      status: status,
      serviceType: serviceType,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
  }) {
    return _remote.listOpenRides(
      limit: limit,
      cursor: cursor,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<List<RideOffer>> listOffers(String rideId) {
    return _remote.listOffers(
      rideId: rideId,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<RideOffer> createOffer({
    required String rideId,
    required Map<String, Object?> body,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (offer) => offer.offerId.isNotEmpty,
      run: (nonce) => _remote.createOffer(
        rideId: rideId,
        body: body,
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<RideOffer> withdrawOffer({
    required String rideId,
    required String offerId,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (offer) =>
          offer.status == 'WITHDRAWN' || offer.status == 'SELECTED',
      run: (nonce) => _remote.withdrawOffer(
        rideId: rideId,
        offerId: offerId,
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<RideAssignment> selectOffer({
    required String rideId,
    required String offerId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (a) => a.state == 'DRIVER_ASSIGNED',
      run: (nonce) => _remote.selectOffer(
        rideId: rideId,
        offerId: offerId,
        body: {
          if (expectedVersion != null) 'expectedVersion': expectedVersion,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> cancelRide({
    required String rideId,
    String? reason,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'CANCELLED',
      run: (nonce) => _remote.cancelRide(
        rideId: rideId,
        body: {
          if (reason != null) 'reason': reason,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  Map<String, Object?> _versionBody(int? expectedVersion) => {
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
      };

  @override
  Future<Ride> markEnRoute({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'DRIVER_EN_ROUTE',
      run: (nonce) => _remote.markEnRoute(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> markArrived({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'DRIVER_ARRIVED',
      run: (nonce) => _remote.markArrived(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> startRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_STARTED',
      run: (nonce) => _remote.startRide(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_COMPLETED',
      run: (nonce) => _remote.completeRide(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> closeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_CLOSED',
      run: (nonce) => _remote.closeRide(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (rating) => rating.ratingId.isNotEmpty,
      run: (nonce) => _remote.submitRating(
        rideId: rideId,
        stars: stars,
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<RideRating> getMyRating(String rideId) {
    return _remote.getMyRating(
      rideId: rideId,
      context: _apiClient.newContext(),
    );
  }
}
