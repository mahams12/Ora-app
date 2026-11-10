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
    String? as,
  }) {
    return _remote.listRides(
      limit: limit,
      cursor: cursor,
      status: status,
      serviceType: serviceType,
      as: as,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<DriverInvitePage> listInvited() {
    return _remote.listInvited(context: _apiClient.newContext());
  }

  @override
  Future<String> acceptInvite({
    required String rideId,
    required String waveId,
  }) {
    // Server uses a deterministic internal idempotency key
    // (invite_accept_{waveId}_{driverId}) — no client nonce needed.
    return _remote.acceptInvite(
      rideId: rideId,
      waveId: waveId,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<void> declineInvite({
    required String rideId,
    required String waveId,
  }) {
    return _remote.declineInvite(
      rideId: rideId,
      waveId: waveId,
      context: _apiClient.newContext(),
    );
  }

  @override
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
    String? serviceType,
    String? category,
  }) {
    return _remote.listOpenRides(
      limit: limit,
      cursor: cursor,
      serviceType: serviceType,
      category: category,
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
    String? otp,
    String? pickupPhotoUrl,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_STARTED',
      run: (nonce) => _remote.startRide(
        rideId: rideId,
        body: {
          ..._versionBody(expectedVersion),
          if (otp != null) 'otp': otp,
          if (pickupPhotoUrl != null) 'pickupPhotoUrl': pickupPhotoUrl,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_COMPLETED',
      run: (nonce) => _remote.completeRide(
        rideId: rideId,
        body: {
          ..._versionBody(expectedVersion),
          if (otp != null) 'otp': otp,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> failDelivery({
    required String rideId,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'DELIVERY_FAILED',
      run: (nonce) => _remote.failDelivery(
        rideId: rideId,
        body: {
          ..._versionBody(expectedVersion),
          'reason': reason,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> retryDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RIDE_STARTED',
      run: (nonce) => _remote.retryDelivery(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> startReturn({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RETURNING',
      run: (nonce) => _remote.startReturn(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> completeReturn({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.state == 'RETURNED',
      run: (nonce) => _remote.completeReturn(
        rideId: rideId,
        body: {
          ..._versionBody(expectedVersion),
          if (otp != null) 'otp': otp,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  // ── Ora Courier v2 ──────────────────────────────────────────────────

  @override
  Future<Ride> arriveStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: _stopMoved,
      run: (nonce) => _remote.arriveStop(
        rideId: rideId,
        seq: seq,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> confirmStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    int? purchaseTotalMinor,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: _stopMoved,
      run: (nonce) => _remote.confirmStop(
        rideId: rideId,
        seq: seq,
        body: {
          ..._versionBody(expectedVersion),
          if (purchaseTotalMinor != null)
            'purchaseTotalMinor': purchaseTotalMinor,
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> failStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: _stopMoved,
      run: (nonce) => _remote.failStop(
        rideId: rideId,
        seq: seq,
        body: {..._versionBody(expectedVersion), 'reason': reason},
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> submitStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required List<Map<String, Object?>> items,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: _stopMoved,
      run: (nonce) => _remote.submitStopQuote(
        rideId: rideId,
        seq: seq,
        body: {..._versionBody(expectedVersion), 'items': items},
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> respondToStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required bool approve,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: _stopMoved,
      run: (nonce) => _remote.respondToStopQuote(
        rideId: rideId,
        seq: seq,
        body: {
          ..._versionBody(expectedVersion),
          'decision': approve ? 'APPROVE' : 'REJECT',
        },
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> reportSettlement({
    required String rideId,
    int? expectedVersion,
    required String status,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) =>
          (ride.settlement?['driverReportedStatus'] as String?) == status,
      run: (nonce) => _remote.reportSettlement(
        rideId: rideId,
        body: {..._versionBody(expectedVersion), 'status': status},
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> acknowledgeDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.evidence?['customerAckAt'] != null,
      run: (nonce) => _remote.acknowledgeDelivery(
        rideId: rideId,
        body: _versionBody(expectedVersion),
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Ride> createDispute({
    required String rideId,
    required String category,
    required String message,
    required String operationKey,
  }) {
    return _withNonce(
      operationKey: operationKey,
      isTerminalSuccess: (ride) => ride.disputeId != null,
      run: (nonce) => _remote.createDispute(
        rideId: rideId,
        body: {'category': category, 'message': message},
        context: _apiClient.newContext(idempotencyKey: nonce),
      ),
    );
  }

  @override
  Future<Map<String, Object?>> getDeliveryConfig() {
    return _remote.getDeliveryConfig(context: _apiClient.newContext());
  }

  /// Any stop progressed beyond PENDING — covers arrive/confirm/fail/quote/
  /// quote-response replays (the returned doc is already post-mutation).
  bool _stopMoved(Ride ride) {
    final list = ride.stops;
    if (list == null) return true; // legacy/v1 — response accepted as-is
    return list.any((s) => s.status != 'PENDING');
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
