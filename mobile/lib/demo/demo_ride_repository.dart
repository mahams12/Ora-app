import '../core/errors/app_failure.dart';
import '../features/ride/domain/entities/ride.dart';
import '../features/ride/domain/repositories/ride_repository.dart';
import 'demo_session_store.dart';

/// DEMO/REVIEW BUILD ONLY — in-memory [RideRepository].
///
/// Seeds realistic Lahore rides so every ride screen has content, and
/// applies the real state machine locally so Accept / En route / Arrived /
/// Start / Complete progress the active-ride screens exactly like the live
/// app. Nothing leaves the device; the production `RideRepositoryImpl` is
/// untouched.
class DemoRideRepository implements RideRepository {
  DemoRideRepository(this._session);

  final DemoSessionStore _session;

  final List<Ride> _rides = [];
  final List<OpenRide> _openRides = [];
  final List<DriverInvite> _invites = [];
  final Map<String, List<RideOffer>> _offers = {};
  var _seeded = false;
  var _counter = 0;

  String get _uid => _session.profile?.uid ?? 'demo_user';

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    _rides.addAll([
      _ride(
        'hist-1',
        'RIDE_COMPLETED',
        'DHA Phase 5, Lahore',
        'Packages Mall',
        42000,
        completedAt: _iso(-26),
      ),
      _ride(
        'hist-2',
        'RIDE_COMPLETED',
        'Gulberg III',
        'Emporium Mall',
        35500,
        completedAt: _iso(-49),
      ),
      _ride('book-1', 'DRIVER_ASSIGNED', 'DHA Phase 5', 'Packages Mall', 42000),
      _ride(
        'book-2',
        'EN_ROUTE_TO_PICKUP',
        'Gulberg III',
        'Emporium Mall',
        35500,
      ),
      _ride(
        'book-3',
        'RIDE_COMPLETED',
        'Faisal Town',
        'Kalma Chowk',
        24000,
        completedAt: _iso(-21),
      ),
    ]);
    _openRides.addAll([
      _open('open-1', 'Johar Town, Lahore', 'DHA Phase 3', 31000),
      _open('open-2', 'Model Town Link Rd', 'Fortress Stadium', 48500),
      _open('open-3', 'Faisal Town', 'Kalma Chowk', 24000),
    ]);
    _invites.addAll([
      _invite('inv-1', 'DHA Phase 5, Lahore', 'Packages Mall', 42000),
      _invite('inv-2', 'Gulberg III', 'Emporium Mall', 35500),
    ]);
  }

  static String _iso(int hoursAgo) =>
      DateTime.now().add(Duration(hours: hoursAgo)).toUtc().toIso8601String();

  Ride _ride(
    String id,
    String state,
    String pickup,
    String dest,
    int fareMinor, {
    String? completedAt,
    String? passengerId,
    String serviceType = 'ride',
  }) => Ride(
    rideId: id,
    passengerId: passengerId ?? 'demo_passenger',
    assignedDriverId: state == 'SEARCHING' ? null : _uid,
    state: state,
    version: 2,
    requestVersion: 1,
    category: 'economy',
    serviceType: serviceType,
    pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
    destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
    pricingSnapshotId: 'ps_$id',
    recommendedFareMinor: fareMinor,
    passengerOfferMinor: fareMinor,
    agreedFareMinor: state == 'SEARCHING' ? null : fareMinor,
    driverPayoutMinor: state == 'SEARCHING'
        ? null
        : (fareMinor * 0.85).round(),
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: _iso(-3),
    updatedAt: _iso(-1),
    completedAt: completedAt,
    assignedAt: state == 'SEARCHING' ? null : _iso(-2),
  );

  OpenRide _open(String id, String pickup, String dest, int fareMinor) =>
      OpenRide(
        rideId: id,
        state: 'SEARCHING',
        requestVersion: 1,
        category: 'economy',
        serviceType: 'ride',
        pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
        destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
        recommendedFareMinor: fareMinor,
        passengerOfferMinor: fareMinor,
        paymentMethod: 'CASH',
        passengerCount: 1,
        distanceKm: 4.8,
        estimatedDurationMin: 16,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: _iso(-1),
      );

  DriverInvite _invite(String id, String pickup, String dest, int fare) =>
      DriverInvite(
        rideId: id,
        waveId: 'wave_$id',
        waveNumber: 1,
        status: 'ACTIVE',
        pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
        destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
        passengerOfferMinor: fare,
        currency: 'PKR',
        serviceType: 'ride',
        category: 'economy',
        passengerCount: 1,
        inviteExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        distanceKm: 3.4,
      );

  Ride _find(String rideId) {
    for (final r in _rides) {
      if (r.rideId == rideId) return r;
    }
    throw const AppFailure.notFound(message: 'Demo ride not found.');
  }

  void _replace(Ride updated) {
    final i = _rides.indexWhere((r) => r.rideId == updated.rideId);
    if (i >= 0) {
      _rides[i] = updated;
    } else {
      _rides.add(updated);
    }
  }

  Ride _at(String rideId, String state, {Map<String, Object?> extra = const {}}) {
    final r = _find(rideId);
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = Ride(
      rideId: r.rideId,
      passengerId: r.passengerId,
      assignedDriverId: r.assignedDriverId,
      state: state,
      version: r.version + 1,
      requestVersion: r.requestVersion,
      category: r.category,
      serviceType: r.serviceType,
      pickup: r.pickup,
      destination: r.destination,
      pricingSnapshotId: r.pricingSnapshotId,
      recommendedFareMinor: r.recommendedFareMinor,
      passengerOfferMinor: r.passengerOfferMinor,
      agreedFareMinor: r.agreedFareMinor,
      agreedOfferId: r.agreedOfferId,
      agreedFareCurrency: r.agreedFareCurrency,
      driverPayoutMinor: r.driverPayoutMinor,
      platformFeeMinor: r.platformFeeMinor,
      payoutCurrency: r.payoutCurrency,
      feePolicyResolution: r.feePolicyResolution,
      paymentMethod: r.paymentMethod,
      passengerCount: r.passengerCount,
      expiresAt: r.expiresAt,
      assignedAt: r.assignedAt,
      arrivedAt: state == 'ARRIVED_AT_PICKUP' ? now : r.arrivedAt,
      startedAt: state == 'IN_PROGRESS' ? now : r.startedAt,
      completedAt: state == 'RIDE_COMPLETED' ? now : r.completedAt,
      closedAt: state == 'RIDE_CLOSED' ? now : r.closedAt,
      cancelledBy:
          (extra['cancelledBy'] as String?) ?? r.cancelledBy,
      cancellationReason:
          (extra['cancellationReason'] as String?) ?? r.cancellationReason,
      createdAt: r.createdAt,
      updatedAt: now,
      parcel: r.parcel,
      courierVehicle: r.courierVehicle,
      otpCodes: r.otpCodes,
      pickupPhotoUrl: r.pickupPhotoUrl,
      deliveryFailedAt:
          (extra['deliveryFailedAt'] as String?) ?? r.deliveryFailedAt,
      deliveryFailedReason:
          (extra['deliveryFailedReason'] as String?) ??
          r.deliveryFailedReason,
      returnStartedAt:
          (extra['returnStartedAt'] as String?) ?? r.returnStartedAt,
      returnedAt: (extra['returnedAt'] as String?) ?? r.returnedAt,
      courierProtocolVersion: r.courierProtocolVersion,
      stops: r.stops,
      currentStopIndex: r.currentStopIndex,
      shopping: r.shopping,
      settlement: r.settlement,
      evidence: r.evidence,
      partialFulfillment: r.partialFulfillment,
      disputeStatus:
          (extra['disputeStatus'] as String?) ?? r.disputeStatus,
      disputeId: (extra['disputeId'] as String?) ?? r.disputeId,
    );
    _replace(updated);
    return updated;
  }

  // ── Passenger ─────────────────────────────────────────────────────────

  @override
  Future<Ride> createRide({
    required Map<String, Object?> body,
    required String operationKey,
  }) async {
    _seed();
    final pickupMap = body['pickup'] as Map<String, Object?>? ?? const {};
    final destMap = body['destination'] as Map<String, Object?>? ?? const {};
    final fare =
        (body['passengerOfferMinor'] as num?)?.toInt() ??
        (body['recommendedFareMinor'] as num?)?.toInt() ??
        45000;
    final ride = Ride(
      rideId: 'demo-ride-${++_counter}',
      passengerId: _uid,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category: body['category'] as String? ?? 'economy',
      serviceType: body['serviceType'] as String? ?? 'ride',
      pickup: LatLngPoint(
        lat: (pickupMap['lat'] as num?)?.toDouble() ?? 31.47,
        lng: (pickupMap['lng'] as num?)?.toDouble() ?? 74.27,
        address: pickupMap['address'] as String? ?? 'Demo pickup, Lahore',
      ),
      destination: LatLngPoint(
        lat: (destMap['lat'] as num?)?.toDouble() ?? 31.52,
        lng: (destMap['lng'] as num?)?.toDouble() ?? 74.36,
        address: destMap['address'] as String? ?? 'Demo drop-off, Lahore',
      ),
      pricingSnapshotId: 'ps_demo_${++_counter}',
      recommendedFareMinor: fare,
      passengerOfferMinor: fare,
      paymentMethod: 'CASH',
      passengerCount: (body['passengerCount'] as num?)?.toInt() ?? 1,
      expiresAt: '2099-01-01T00:00:00.000Z',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    _rides.insert(0, ride);

    // Seed two incoming driver offers so the "ride requested" screen shows
    // the same live-offer UI as production.
    _offers[ride.rideId] = [
      _offer(ride.rideId, 'offer-a', fare + 5000),
      _offer(ride.rideId, 'offer-b', fare + 10000),
    ];
    return ride;
  }

  @override
  Future<Ride> getRide(String rideId) async {
    _seed();
    return _find(rideId);
  }

  @override
  Future<RideListPage> listRides({
    int? limit,
    String? cursor,
    String? status,
    String? serviceType,
    String? as,
  }) async {
    _seed();
    Iterable<Ride> list = _rides;
    if (as == 'driver') {
      list = list.where((r) => r.assignedDriverId == _uid);
    } else {
      list = list.where((r) => r.passengerId == _uid || r.passengerId == 'demo_passenger');
    }
    if (status != null && status.isNotEmpty) {
      final wanted = status.split(',');
      list = list.where((r) => wanted.contains(r.state));
    }
    if (serviceType != null) {
      list = list.where((r) => r.serviceType == serviceType);
    }
    final items = list.take(limit ?? 50).toList();
    return RideListPage(rides: items);
  }

  // ── Driver dispatch ───────────────────────────────────────────────────

  @override
  Future<DriverInvitePage> listInvited() async {
    _seed();
    return DriverInvitePage(
      items: List.of(_invites),
      serverNowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<String> acceptInvite({
    required String rideId,
    required String waveId,
  }) async {
    _seed();
    final i = _invites.indexWhere((v) => v.rideId == rideId);
    if (i < 0) throw const AppFailure.notFound(message: 'Demo invite gone.');
    final invite = _invites[i];
    _invites[i] = DriverInvite(
      rideId: invite.rideId,
      waveId: invite.waveId,
      waveNumber: invite.waveNumber,
      status: 'RESPONDED_ACCEPTED',
      pickup: invite.pickup,
      destination: invite.destination,
      passengerOfferMinor: invite.passengerOfferMinor,
      currency: invite.currency,
      serviceType: invite.serviceType,
      category: invite.category,
      passengerCount: invite.passengerCount,
      inviteExpiresAt: invite.inviteExpiresAt,
      distanceKm: invite.distanceKm,
    );
    _replace(
      _ride(
        rideId,
        'DRIVER_ASSIGNED',
        invite.pickup.address ?? 'Pickup',
        invite.destination.address ?? 'Drop-off',
        invite.passengerOfferMinor,
        serviceType: invite.serviceType,
      ),
    );
    return 'offer_$rideId';
  }

  @override
  Future<void> declineInvite({
    required String rideId,
    required String waveId,
  }) async {
    _seed();
    _invites.removeWhere((v) => v.rideId == rideId);
  }

  @override
  Future<OpenRideListPage> listOpenRides({
    int? limit,
    String? cursor,
    String? serviceType,
    String? category,
  }) async {
    _seed();
    var list = _openRides.where((r) => r.state == 'SEARCHING');
    if (serviceType != null) {
      list = list.where((r) => r.serviceType == serviceType);
    }
    if (category != null) {
      list = list.where((r) => r.category == category);
    }
    return OpenRideListPage(rides: list.take(limit ?? 50).toList());
  }

  // ── Offers ────────────────────────────────────────────────────────────

  RideOffer _offer(String rideId, String offerId, int amountMinor) =>
      RideOffer(
        offerId: offerId,
        rideId: rideId,
        driverId: 'demo_driver_$offerId',
        amountMinor: amountMinor,
        currency: 'PKR',
        type: 'DRIVER_COUNTER',
        status: 'ACTIVE',
        requestVersion: 1,
        expiresAt: '2099-01-01T00:00:00.000Z',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        driverSnapshot: const {
          'displayName': 'Demo Driver',
          'rating': 4.8,
          'vehicleModel': 'Toyota Corolla',
          'plateNumber': 'LEA-1234',
        },
      );

  @override
  Future<List<RideOffer>> listOffers(String rideId) async {
    _seed();
    return List.of(_offers[rideId] ?? const []);
  }

  @override
  Future<RideOffer> createOffer({
    required String rideId,
    required Map<String, Object?> body,
    required String operationKey,
  }) async {
    _seed();
    final amount =
        (body['amountMinor'] as num?)?.toInt() ??
        (_find(rideId).passengerOfferMinor);
    final offer = _offer(rideId, 'demo-offer-${++_counter}', amount);
    _offers.putIfAbsent(rideId, () => []).add(offer);
    return offer;
  }

  @override
  Future<RideOffer> withdrawOffer({
    required String rideId,
    required String offerId,
    required String operationKey,
  }) async {
    _seed();
    final offers = _offers[rideId] ?? [];
    final i = offers.indexWhere((o) => o.offerId == offerId);
    if (i < 0) throw const AppFailure.notFound();
    final o = offers[i];
    final withdrawn = RideOffer(
      offerId: o.offerId,
      rideId: o.rideId,
      driverId: o.driverId,
      amountMinor: o.amountMinor,
      currency: o.currency,
      type: o.type,
      status: 'WITHDRAWN',
      requestVersion: o.requestVersion,
      expiresAt: o.expiresAt,
      createdAt: o.createdAt,
      driverSnapshot: o.driverSnapshot,
    );
    offers[i] = withdrawn;
    return withdrawn;
  }

  @override
  Future<RideAssignment> selectOffer({
    required String rideId,
    required String offerId,
    int? expectedVersion,
    required String operationKey,
  }) async {
    _seed();
    final offers = _offers[rideId] ?? [];
    final offer = offers.firstWhere(
      (o) => o.offerId == offerId,
      orElse: () => throw const AppFailure.notFound(),
    );
    final r = _find(rideId);
    final updated = _at(rideId, 'DRIVER_ASSIGNED');
    _replace(
      Ride(
        rideId: updated.rideId,
        passengerId: updated.passengerId,
        assignedDriverId: offer.driverId,
        state: updated.state,
        version: updated.version,
        requestVersion: updated.requestVersion,
        category: updated.category,
        serviceType: updated.serviceType,
        pickup: updated.pickup,
        destination: updated.destination,
        pricingSnapshotId: updated.pricingSnapshotId,
        recommendedFareMinor: updated.recommendedFareMinor,
        passengerOfferMinor: updated.passengerOfferMinor,
        agreedFareMinor: offer.amountMinor,
        agreedOfferId: offer.offerId,
        driverPayoutMinor: (offer.amountMinor * 0.85).round(),
        paymentMethod: updated.paymentMethod,
        passengerCount: updated.passengerCount,
        expiresAt: updated.expiresAt,
        assignedAt: DateTime.now().toUtc().toIso8601String(),
        createdAt: updated.createdAt,
        updatedAt: updated.updatedAt,
        parcel: updated.parcel,
        courierVehicle: updated.courierVehicle,
        stops: updated.stops,
        shopping: updated.shopping,
      ),
    );
    return RideAssignment(
      rideId: r.rideId,
      state: 'DRIVER_ASSIGNED',
      version: updated.version,
      assignedDriverId: offer.driverId,
      agreedFareMinor: offer.amountMinor,
      agreedOfferId: offer.offerId,
      currency: 'PKR',
    );
  }

  // ── Lifecycle transitions ─────────────────────────────────────────────

  @override
  Future<Ride> cancelRide({
    required String rideId,
    String? reason,
    required String operationKey,
  }) async => _at(
    rideId,
    'RIDE_CANCELLED',
    extra: {'cancelledBy': 'PASSENGER', 'cancellationReason': reason},
  );

  @override
  Future<Ride> markEnRoute({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, 'EN_ROUTE_TO_PICKUP');

  @override
  Future<Ride> markArrived({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, 'ARRIVED_AT_PICKUP');

  @override
  Future<Ride> startRide({
    required String rideId,
    int? expectedVersion,
    String? otp,
    String? pickupPhotoUrl,
    required String operationKey,
  }) async => _at(rideId, 'IN_PROGRESS');

  @override
  Future<Ride> completeRide({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  }) async => _at(rideId, 'RIDE_COMPLETED');

  @override
  Future<Ride> failDelivery({
    required String rideId,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  }) async => _at(
    rideId,
    'DELIVERY_FAILED',
    extra: {
      'deliveryFailedAt': DateTime.now().toUtc().toIso8601String(),
      'deliveryFailedReason': reason,
    },
  );

  @override
  Future<Ride> retryDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, 'IN_PROGRESS');

  @override
  Future<Ride> startReturn({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(
    rideId,
    'RETURN_IN_PROGRESS',
    extra: {'returnStartedAt': DateTime.now().toUtc().toIso8601String()},
  );

  @override
  Future<Ride> completeReturn({
    required String rideId,
    int? expectedVersion,
    String? otp,
    required String operationKey,
  }) async => _at(
    rideId,
    'RIDE_COMPLETED',
    extra: {'returnedAt': DateTime.now().toUtc().toIso8601String()},
  );

  @override
  Future<Ride> arriveStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> confirmStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    int? purchaseTotalMinor,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> failStop({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required String reason,
    required String operationKey,
  }) async => _at(
    rideId,
    'DELIVERY_FAILED',
    extra: {
      'deliveryFailedAt': DateTime.now().toUtc().toIso8601String(),
      'deliveryFailedReason': reason,
    },
  );

  @override
  Future<Ride> submitStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required List<Map<String, Object?>> items,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> respondToStopQuote({
    required String rideId,
    required int seq,
    int? expectedVersion,
    required bool approve,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> reportSettlement({
    required String rideId,
    int? expectedVersion,
    required String status,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> acknowledgeDelivery({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, _find(rideId).state);

  @override
  Future<Ride> createDispute({
    required String rideId,
    required String category,
    required String message,
    required String operationKey,
  }) async => _at(
    rideId,
    _find(rideId).state,
    extra: {'disputeStatus': 'OPEN', 'disputeId': 'demo-dispute-1'},
  );

  @override
  Future<Map<String, Object?>> getDeliveryConfig() async => const {
    'protocolVersion': 1,
    'demo': true,
  };

  @override
  Future<Ride> closeRide({
    required String rideId,
    int? expectedVersion,
    required String operationKey,
  }) async => _at(rideId, 'RIDE_CLOSED');

  @override
  Future<RideRating> submitRating({
    required String rideId,
    required int stars,
    required String operationKey,
  }) async => RideRating(
    ratingId: 'demo-rating-${++_counter}',
    rideId: rideId,
    raterId: _uid,
    ratedId: 'demo_partner',
    ratingType: 'PASSENGER_TO_DRIVER',
    stars: stars,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );

  @override
  Future<RideRating> getMyRating(String rideId) async =>
      throw const AppFailure.notFound();
}
