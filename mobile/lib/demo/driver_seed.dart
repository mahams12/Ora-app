// Shared demo seed — fixed view-model states for driver screenshots and the
// driver demo app (video capture). No flutter_test imports so it can run in
// a normal debug app too. Dev-only; nothing ships.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/features/auth/domain/entities/user_profile.dart';
import 'package:ora/features/driver/domain/driver_earnings_summary.dart';
import 'package:ora/features/driver/domain/location/driver_location_status.dart';
import 'package:ora/features/driver/presentation/location/driver_location_session.dart';
import 'package:ora/features/driver/presentation/view_models/driver_assigned_ride_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_assigned_rides_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_availability_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_earnings_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_invites_view_model.dart';
import 'package:ora/features/driver/presentation/view_models/driver_open_rides_view_model.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';

// ---------------------------------------------------------------------------
// Fixed-state view models — build() returns seeded UI state and every public
// method is a no-op so no DI/use-case/provider chain is ever touched.
// ---------------------------------------------------------------------------

class FakeOpenRidesVm extends DriverOpenRidesViewModel {
  FakeOpenRidesVm(this._s);
  final DriverOpenRidesUiState _s;

  @override
  DriverOpenRidesUiState build() => _s;

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> retry() async {}

  @override
  void dismissRideLocally(String rideId) {}

  @override
  Future<void> setServiceTypeFilter(String? value) async {}

  @override
  Future<void> setCategoryFilter(String? value) async {}

  @override
  Future<void> clearFilters() async {}

  @override
  Future<void> submitOffer({
    required OpenRide ride,
    required String type,
    required int amountMinor,
  }) async {}
}

class FakeInvitesVm extends DriverInvitesViewModel {
  FakeInvitesVm(this._s);
  final DriverInvitesUiState _s;

  @override
  DriverInvitesUiState build() => _s;

  @override
  Future<void> refresh() async {}

  @override
  void tickCountdown() {}

  @override
  Duration remainingFor(DriverInvite invite) => const Duration(seconds: 14);

  @override
  bool isLocallyExpired(DriverInvite invite) => !invite.isActionable;

  @override
  Future<void> accept(DriverInvite invite) async {}

  @override
  Future<void> decline(DriverInvite invite) async {}
}

class FakeAssignedVm extends DriverAssignedRidesViewModel {
  FakeAssignedVm(this._s);
  final DriverAssignedRidesUiState _s;

  @override
  DriverAssignedRidesUiState build() => _s;

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> setStatus(String status) async {}

  @override
  Future<void> setServiceType(String? serviceType) async {}

  @override
  Future<void> retry() async {}
}

class FakeEarningsVm extends DriverEarningsViewModel {
  FakeEarningsVm(this._s);
  final DriverEarningsUiState _s;

  @override
  DriverEarningsUiState build() => _s;

  @override
  Future<void> loadInitial() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}

  @override
  Future<void> retry() async {}
}

class FakeAvailability extends DriverAvailabilityController {
  @override
  DriverAvailabilityUiState build() => const DriverAvailabilityUiState(
    availabilityState: 'online',
    loaded: true,
  );

  @override
  Future<void> refresh() async {}

  @override
  Future<void> toggle() async {}
}

class FakePresence extends DriverPresenceController {
  @override
  bool build() => false;

  @override
  void onAppLifecycle(bool resumed) {}

  @override
  void onSignedOut() {}
}

class FakeAssignedRideVm extends DriverAssignedRideViewModel {
  FakeAssignedRideVm(this._s);
  final DriverAssignedRideUiState _s;

  @override
  DriverAssignedRideUiState build(String arg) => _s;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh({bool isInitial = false, bool force = false}) async {}

  @override
  void pausePolling() {}

  @override
  Future<void> resumePolling() async {}

  @override
  Future<void> runPrimaryAction() async {}

  @override
  Future<void> markEnRoute() async {}

  @override
  Future<void> markArrived() async {}

  @override
  Future<void> startRide({String? otp, String? pickupPhotoUrl}) async {}

  @override
  Future<void> completeRide({String? otp}) async {}

  @override
  Future<void> cancel({String? reason}) async {}

  @override
  Future<void> closeRide() async {}

  @override
  Future<void> failDelivery({required String reason}) async {}

  @override
  Future<void> retryDelivery() async {}

  @override
  Future<void> startReturn() async {}

  @override
  Future<void> completeReturn({String? otp}) async {}
}

class FakeLocationSession extends DriverLocationSession {
  @override
  DriverLocationStatusKind build(String arg) => DriverLocationStatusKind.ready;

  @override
  void onAppLifecycle(AppLifecycleState lifecycle) {}

  @override
  void onSignedOut() {}

  @override
  Future<void> onUserRecoveryAction() async {}
}

// ---------------------------------------------------------------------------
// Seeded entities
// ---------------------------------------------------------------------------

const demoProfile = UserProfile(
  uid: 'drv_shot',
  phoneNumber: '+923001234567',
  displayName: 'Ahmed',
  role: 'driver',
  driverStatus: 'approved',
  activeMode: 'driver',
  profileComplete: true,
);

/// Approved logistics partner — cargo vendor capability, no driver grant.
const demoLogisticsProfile = UserProfile(
  uid: 'lgv_shot',
  phoneNumber: '+923001234567',
  displayName: 'Ahmed',
  role: 'passenger',
  activeMode: 'passenger',
  profileComplete: true,
  vendorApplications: {'cargo': 'approved'},
);

OpenRide demoOpenRide(
  String id,
  String pickup,
  String dest,
  int fareMinor, {
  double? km,
  int? mins,
  String serviceType = 'ride',
}) {
  return OpenRide(
    rideId: id,
    state: 'SEARCHING',
    requestVersion: 1,
    category: 'economy',
    serviceType: serviceType,
    pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
    destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
    recommendedFareMinor: fareMinor,
    passengerOfferMinor: fareMinor,
    paymentMethod: 'CASH',
    passengerCount: 1,
    distanceKm: km,
    estimatedDurationMin: mins,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-11-16T08:00:00.000Z',
  );
}

DriverInvite demoInvite(
  String id,
  String pickup,
  String dest,
  int fareMinor, {
  String serviceType = 'ride',
}) {
  return DriverInvite(
    rideId: id,
    waveId: 'wave_$id',
    waveNumber: 1,
    status: 'ACTIVE',
    pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
    destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
    passengerOfferMinor: fareMinor,
    currency: 'PKR',
    serviceType: serviceType,
    category: 'economy',
    passengerCount: 1,
    inviteExpiresAt: DateTime.now().add(const Duration(seconds: 14)),
    distanceKm: 3.4,
  );
}

Ride demoRide(
  String id,
  String state,
  String pickup,
  String dest,
  int fareMinor, {
  String? completedAt,
  String serviceType = 'ride',
}) {
  return Ride(
    rideId: id,
    passengerId: 'p_$id',
    assignedDriverId: 'drv_shot',
    state: state,
    version: 2,
    requestVersion: 1,
    category: 'economy',
    serviceType: serviceType,
    pickup: LatLngPoint(lat: 31.47, lng: 74.27, address: pickup),
    destination: LatLngPoint(lat: 31.52, lng: 74.36, address: dest),
    pricingSnapshotId: 'snap_$id',
    recommendedFareMinor: fareMinor,
    passengerOfferMinor: fareMinor,
    agreedFareMinor: fareMinor,
    driverPayoutMinor: (fareMinor * 0.85).round(),
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-11-16T08:00:00.000Z',
    updatedAt: '2026-11-16T08:30:00.000Z',
    completedAt: completedAt,
  );
}

const demoEarningsSummary = DriverEarningsSummary(
  completedRideCount: 24,
  ridesWithFare: 24,
  ridesWithPayout: 20,
  ridesMissingFare: 0,
  today: DriverEarningsPeriod(
    rideCount: 4,
    faresMinor: 152000,
    currency: 'PKR',
    payoutRideCount: 4,
    payoutMinor: 129200,
    fareOnlyMinor: 0,
  ),
  last7Days: DriverEarningsPeriod(
    rideCount: 14,
    faresMinor: 486000,
    currency: 'PKR',
    payoutRideCount: 12,
    payoutMinor: 413100,
    fareOnlyMinor: 35000,
  ),
  allTime: DriverEarningsPeriod(
    rideCount: 24,
    faresMinor: 912000,
    currency: 'PKR',
    payoutRideCount: 20,
    payoutMinor: 775200,
    fareOnlyMinor: 62000,
  ),
);

List<Override> driverDemoOverrides({String serviceType = 'ride'}) {
  final invites = DriverInvitesUiState(
    phase: DriverInvitesPhase.ready,
    items: [
      demoInvite(
        'inv-1',
        'DHA Phase 5, Lahore',
        'Packages Mall',
        42000,
        serviceType: serviceType,
      ),
      demoInvite(
        'inv-2',
        'Gulberg III',
        'Emporium Mall',
        35500,
        serviceType: serviceType,
      ),
    ],
  );
  return [
    driverInvitesViewModelProvider.overrideWith(() => FakeInvitesVm(invites)),
    driverOpenRidesViewModelProvider.overrideWith(
      () => FakeOpenRidesVm(
        DriverOpenRidesUiState(
          phase: DriverOpenRidesPhase.ready,
          rides: [
            demoOpenRide(
              'open-1',
              'Johar Town, Lahore',
              'DHA Phase 3',
              31000,
              km: 5.2,
              mins: 14,
              serviceType: serviceType,
            ),
            demoOpenRide(
              'open-2',
              'Model Town Link Rd',
              'Fortress Stadium',
              48500,
              km: 8.7,
              mins: 21,
              serviceType: serviceType,
            ),
            demoOpenRide(
              'open-3',
              'Faisal Town',
              'Kalma Chowk',
              24000,
              km: 2.1,
              mins: 8,
              serviceType: serviceType,
            ),
          ],
        ),
      ),
    ),
    driverAssignedRidesViewModelProvider.overrideWith(
      () => FakeAssignedVm(
        DriverAssignedRidesUiState(
          phase: DriverAssignedRidesPhase.ready,
          rides: [
            demoRide(
              'book-1',
              'DRIVER_ASSIGNED',
              'DHA Phase 5, Lahore',
              'Packages Mall',
              42000,
              serviceType: serviceType,
            ),
            demoRide(
              'book-2',
              'EN_ROUTE_TO_PICKUP',
              'Gulberg III',
              'Emporium Mall',
              35500,
              serviceType: serviceType,
            ),
            demoRide(
              'book-3',
              'RIDE_COMPLETED',
              'Faisal Town',
              'Kalma Chowk',
              24000,
              completedAt: '2026-11-15T19:20:00.000Z',
              serviceType: serviceType,
            ),
          ],
        ),
      ),
    ),
    driverEarningsViewModelProvider.overrideWith(
      () => FakeEarningsVm(
        DriverEarningsUiState(
          phase: DriverEarningsPhase.ready,
          summary: demoEarningsSummary,
          rides: [
            demoRide(
              'earn-1',
              'RIDE_COMPLETED',
              'DHA Phase 5',
              'Packages Mall',
              42000,
              completedAt: '2026-11-16T10:15:00.000Z',
              serviceType: serviceType,
            ),
            demoRide(
              'earn-2',
              'RIDE_COMPLETED',
              'Gulberg III',
              'Emporium Mall',
              35500,
              completedAt: '2026-11-16T08:45:00.000Z',
              serviceType: serviceType,
            ),
            demoRide(
              'earn-3',
              'RIDE_COMPLETED',
              'Model Town',
              'Fortress Stadium',
              48500,
              completedAt: '2026-11-15T18:05:00.000Z',
              serviceType: serviceType,
            ),
          ],
        ),
      ),
    ),
    driverAvailabilityProvider.overrideWith(() => FakeAvailability()),
    driverPresenceProvider.overrideWith(() => FakePresence()),
    driverAssignedRideViewModelProvider.overrideWith(
      () => FakeAssignedRideVm(
        DriverAssignedRideUiState(
          phase: DriverAssignedRidePhase.active,
          ride: demoRide(
            'book-1',
            'DRIVER_ASSIGNED',
            'DHA Phase 5, Lahore',
            'Packages Mall',
            42000,
            serviceType: serviceType,
          ),
        ),
      ),
    ),
    driverLocationSessionProvider.overrideWith(() => FakeLocationSession()),
    activeRideMapsEnabledProvider.overrideWithValue(false),
  ];
}
