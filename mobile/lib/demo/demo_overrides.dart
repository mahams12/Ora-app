import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/di/providers.dart';
import '../core/network/auth_token_provider.dart';
import '../core/security/app_check_token_provider.dart';
import '../features/driver/presentation/location/driver_location_session.dart';
import '../features/driver/presentation/view_models/driver_availability_view_model.dart';
import '../features/marketplace/data/marketplace_providers.dart';
import '../features/marketplace/shared/demo/demo_listings.dart';
import '../features/wallet/partner_wallet.dart';
import 'demo_auth_repository.dart';
import 'demo_driver_onboarding.dart';
import 'demo_marketplace_api.dart';
import 'demo_ports.dart';
import 'demo_ride_repository.dart';
import 'demo_session_store.dart';
import 'demo_wallet_api.dart';
import 'driver_seed.dart';

/// DEMO/REVIEW BUILD — provider overrides applied only by `main_demo.dart`.
///
/// Every backend seam gets a local in-memory implementation: auth (OTP
/// `000000`, auto-approved partner roles), ride repository, marketplace API,
/// shared partner wallet, place search, pricing, trip location and FCM.
/// All view models run REAL and interactive — accepting an invite, starting
/// a ride, posting a listing or requesting a top-up mutates the local demo
/// stores, so every screen is fully explorable without a backend.
/// Nothing here is reachable from `lib/main.dart` — the production graph is
/// byte-for-byte unchanged.

/// Single demo account/session — shared by every demo repository so a role
/// approval (or a new listing) is visible everywhere it gates UI.
final demoSessionStoreProvider = Provider<DemoSessionStore>(
  (ref) => DemoSessionStore(ref.watch(secureStorageProvider)),
);

List<Override> oraDemoOverrides() => [
  // ── Auth: local OTP 000000 + auto-approved partner registrations ────
  authRepositoryProvider.overrideWith(
    (ref) => DemoAuthRepository(ref.watch(demoSessionStoreProvider)),
  ),
  driverOnboardingRepositoryProvider.overrideWith(
    (ref) => DemoDriverOnboardingRepository(
      ref.watch(demoSessionStoreProvider),
    ),
  ),

  // ── Backend data: in-memory seeds + local mutations ─────────────────
  rideRepositoryProvider.overrideWith(
    (ref) => DemoRideRepository(ref.watch(demoSessionStoreProvider)),
  ),
  marketplaceApiProvider.overrideWith(
    (ref) => DemoMarketplaceApi(
      ref.watch(apiClientProvider),
      ref.watch(demoSessionStoreProvider),
    ),
  ),
  partnerWalletApiProvider.overrideWith(
    (ref) => DemoPartnerWalletApi(
      ref.watch(apiClientProvider),
      ref.watch(demoSessionStoreProvider),
    ),
  ),
  demoListingsEnabledProvider.overrideWithValue(true),

  // ── Local ports: places, pricing, trip location, push ───────────────
  placeSearchPortProvider.overrideWithValue(DemoPlaceSearch()),
  pricingEstimatePortProvider.overrideWithValue(DemoPricingEstimate()),
  tripLocationPortProvider.overrideWithValue(DemoTripLocation()),
  dispatchFcmServiceProvider.overrideWith(
    (ref) => DemoDispatchFcmService(
      tokenApi: ref.watch(driverDeviceTokenRemoteDataSourceProvider),
      apiClient: ref.watch(apiClientProvider),
    ),
  ),

  // ── Never touch Firebase in the demo build ──────────────────────────
  authTokenProviderProvider.overrideWithValue(const NoAuthTokenProvider()),
  appCheckTokenProviderProvider.overrideWithValue(
    const NoAppCheckTokenProvider(),
  ),
  activeRideMapsEnabledProvider.overrideWithValue(false),

  // ── Local-only hardware/network seams — driver VMs otherwise run real
  // (invites/open/assigned/earnings hit the demo ride repository, so
  // Accept/Decline and ride-progression buttons work end to end).
  driverAvailabilityProvider.overrideWith(() => FakeAvailability()),
  driverPresenceProvider.overrideWith(() => FakePresence()),
  driverLocationSessionProvider.overrideWith(() => FakeLocationSession()),
];
