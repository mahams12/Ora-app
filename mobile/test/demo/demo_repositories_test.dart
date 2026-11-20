import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/network/api_client.dart';
import 'package:ora/core/network/auth_token_provider.dart';
import 'package:ora/core/network/network_config.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/core/storage/secure_storage.dart';
import 'package:ora/demo/demo_auth_repository.dart';
import 'package:ora/demo/demo_driver_onboarding.dart';
import 'package:ora/demo/demo_marketplace_api.dart';
import 'package:ora/demo/demo_ride_repository.dart';
import 'package:ora/demo/demo_session_store.dart';
import 'package:ora/demo/demo_wallet_api.dart';
import 'package:ora/features/auth/domain/entities/otp_session.dart';
import 'package:ora/features/auth/domain/entities/phone_verification_result.dart';
import 'package:ora/features/driver/domain/driver_onboarding_application.dart';

const _ctx = RequestContext(requestId: 'test');

DemoSessionStore _store() => DemoSessionStore(InMemorySecureStorage());

void main() {
  group('DemoAuthRepository', () {
    test('requestOtp returns a sent session for any phone', () async {
      final repo = DemoAuthRepository(_store());
      final result = await repo.requestOtp(phoneE164: '+923001234567');
      expect(result, isA<PhoneCodeSent>());
      expect(
        (result as PhoneCodeSent).session.otpState,
        OtpState.otpSent,
      );
    });

    test('verifyOtp accepts 000000 and signs in a fresh passenger', () async {
      final repo = DemoAuthRepository(_store());
      final sent =
          (await repo.requestOtp(phoneE164: '+923009998877'))
              as PhoneCodeSent;
      final user = await repo.verifyOtp(
        session: sent.session,
        otpCode: '000000',
      );
      expect(user.uid, DemoSessionStore.uidForPhone('+923009998877'));
      expect(await repo.getCurrentUser(), isNotNull);
      final profile = await repo.getUserProfile(uid: user.uid);
      expect(profile.profileComplete, isFalse);
    });

    test('verifyOtp rejects any other code with InvalidOtp', () async {
      final repo = DemoAuthRepository(_store());
      final sent =
          (await repo.requestOtp(phoneE164: '+923001234567'))
              as PhoneCodeSent;
      await expectLater(
        repo.verifyOtp(session: sent.session, otpCode: '123456'),
        throwsA(isA<InvalidOtpFailure>()),
      );
    });

    test('vendor application auto-approves (demo only)', () async {
      final repo = DemoAuthRepository(_store());
      final sent =
          (await repo.requestOtp(phoneE164: '+923001234567'))
              as PhoneCodeSent;
      await repo.verifyOtp(session: sent.session, otpCode: '000000');
      for (final type in const ['cargo', 'rental', 'service']) {
        final profile = await repo.submitVendorApplication(type: type);
        expect(profile.isApprovedVendor(type), isTrue);
      }
    });

    test('driver onboarding via demo repo approves + unlocks driver mode',
        () async {
      final store = _store();
      final repo = DemoAuthRepository(store);
      final sent =
          (await repo.requestOtp(phoneE164: '+923001234567'))
              as PhoneCodeSent;
      await repo.verifyOtp(session: sent.session, otpCode: '000000');

      // Not a driver yet — mode switch is gated exactly like production.
      await expectLater(
        repo.switchMode(mode: 'driver'),
        throwsA(isA<AppFailure>()),
      );

      final onboarding = DemoDriverOnboardingRepository(store);
      final result = await onboarding.submit(
        const DriverOnboardingApplication(
          fullName: 'Demo Driver',
          cnicNumber: '3520212345671',
          homeCity: 'Lahore',
          licenseNumber: 'LHR-1234',
          licenseExpiry: '2030-01-01',
          vehicleCategory: 'car',
          vehicleMake: 'Toyota',
          vehicleModel: 'Corolla',
          vehicleYear: 2022,
          vehicleColor: 'White',
          plateNumber: 'LEA-1234',
        ),
      );
      expect(result.approved, isTrue);
      expect(result.driverStatus, 'approved');

      final profile = await repo.getUserProfile(uid: 'x');
      expect(profile.isApprovedDriver, isTrue);
      final switched = await repo.switchMode(mode: 'driver');
      expect(switched.activeMode, 'driver');
    });

    test('session persists + restores; logout clears it', () async {
      final storage = InMemorySecureStorage();
      final store1 = DemoSessionStore(storage);
      final repo1 = DemoAuthRepository(store1);
      final sent =
          (await repo1.requestOtp(phoneE164: '+923001234567'))
              as PhoneCodeSent;
      await repo1.verifyOtp(session: sent.session, otpCode: '000000');
      await repo1.submitVendorApplication(type: 'rental');

      // New store over the same storage = simulated app restart.
      final repo2 = DemoAuthRepository(DemoSessionStore(storage));
      final restored = await repo2.restoreSession();
      expect(restored, isNotNull);
      final profile = await repo2.getUserProfile(uid: 'x');
      expect(profile.isApprovedVendor('rental'), isTrue);

      await repo2.logout();
      expect(await repo2.getCurrentUser(), isNull);
      final repo3 = DemoAuthRepository(DemoSessionStore(storage));
      expect(await repo3.restoreSession(), isNull);
    });
  });

  group('DemoMarketplaceApi', () {
    Future<DemoMarketplaceApi> api() async {
      final store = _store();
      await store.createForPhone('+923001234567');
      return DemoMarketplaceApi(_deadClient(), store);
    }

    test('seeds published listings for all verticals', () async {
      final a = await api();
      for (final type in const ['service', 'rental', 'cargo']) {
        final list = await a.publishedListings(type: type, context: _ctx);
        expect(list, isNotEmpty, reason: type);
      }
    });

    test('vendor create/update/delete flows through myListings', () async {
      final a = await api();
      final created = await a.createListing(
        body: const {
          'type': 'service',
          'categoryId': 'home_services',
          'subcategoryId': 'painter',
          'title': 'Demo Painter',
          'price': 2000,
          'priceUnit': 'Per visit',
          'location': 'Lahore',
        },
        context: _ctx,
      );
      var mine = await a.myListings(type: 'service', context: _ctx);
      expect(mine.any((l) => l.listingId == created.listingId), isTrue);

      await a.updateListing(
        listingId: created.listingId,
        patch: const {'status': 'paused'},
        context: _ctx,
      );
      mine = await a.myListings(type: 'service', context: _ctx);
      expect(
        mine.firstWhere((l) => l.listingId == created.listingId).status,
        'paused',
      );
      // Paused listings drop out of customer discovery.
      expect(
        (await a.publishedListings(type: 'service', context: _ctx))
            .any((l) => l.listingId == created.listingId),
        isFalse,
      );

      await a.deleteListing(listingId: created.listingId, context: _ctx);
      mine = await a.myListings(type: 'service', context: _ctx);
      expect(mine.any((l) => l.listingId == created.listingId), isFalse);
    });

    test('booking workflow: request → quote → accept → complete', () async {
      final a = await api();
      final listing = (await a.publishedListings(
        type: 'service',
        context: _ctx,
      ))
          .firstWhere((l) => l.vendorId != 'demo_vendor');

      var booking = await a.createBooking(
        listingId: listing.listingId,
        request: const {'contactName': 'Boss'},
        context: _ctx,
      );
      expect(booking.status, 'requested');

      booking = await a.vendorAction(
        bookingId: booking.bookingId,
        action: 'quote',
        amount: 5000,
        context: _ctx,
      );
      expect(booking.status, 'quoted');
      expect(booking.quote?.amount, 5000);

      booking = await a.customerAction(
        bookingId: booking.bookingId,
        action: 'accept',
        context: _ctx,
      );
      expect(booking.status, 'accepted');

      booking = await a.vendorAction(
        bookingId: booking.bookingId,
        action: 'complete',
        context: _ctx,
      );
      expect(booking.status, 'completed');

      final mine = await a.bookings(role: 'customer', context: _ctx);
      expect(mine.any((b) => b.bookingId == booking.bookingId), isTrue);
    });
  });

  group('DemoRideRepository', () {
    Future<DemoRideRepository> repo() async {
      final store = _store();
      await store.createForPhone('+923001234567');
      return DemoRideRepository(store);
    }

    test('seeds driver invites, open rides and history', () async {
      final r = await repo();
      expect((await r.listInvited()).items, isNotEmpty);
      expect((await r.listOpenRides()).rides, isNotEmpty);
      expect((await r.listRides(as: 'driver')).rides, isNotEmpty);
    });

    test('createRide lands SEARCHING with seeded driver offers', () async {
      final r = await repo();
      final ride = await r.createRide(
        body: const {'passengerOfferMinor': 50000},
        operationKey: 'k1',
      );
      expect(ride.state, 'SEARCHING');
      final offers = await r.listOffers(ride.rideId);
      expect(offers.length, greaterThanOrEqualTo(2));
    });

    test('acceptInvite produces an assigned ride in driver history',
        () async {
      final r = await repo();
      final invite = (await r.listInvited()).items.first;
      await r.acceptInvite(rideId: invite.rideId, waveId: invite.waveId);
      final driverRides = await r.listRides(as: 'driver');
      expect(
        driverRides.rides.any(
          (x) => x.rideId == invite.rideId && x.state == 'DRIVER_ASSIGNED',
        ),
        isTrue,
      );
    });

    test('lifecycle transitions progress the ride', () async {
      final r = await repo();
      final invite = (await r.listInvited()).items.first;
      await r.acceptInvite(rideId: invite.rideId, waveId: invite.waveId);

      final enRoute = await r.markEnRoute(
        rideId: invite.rideId,
        operationKey: 'k',
      );
      expect(enRoute.state, 'EN_ROUTE_TO_PICKUP');

      final arrived = await r.markArrived(
        rideId: invite.rideId,
        operationKey: 'k',
      );
      expect(arrived.state, 'ARRIVED_AT_PICKUP');

      final started = await r.startRide(
        rideId: invite.rideId,
        operationKey: 'k',
      );
      expect(started.state, 'IN_PROGRESS');

      final done = await r.completeRide(
        rideId: invite.rideId,
        operationKey: 'k',
      );
      expect(done.state, 'RIDE_COMPLETED');
      expect(done.completedAt, isNotNull);
    });
  });

  group('DemoPartnerWalletApi', () {
    Future<DemoPartnerWalletApi> api() async {
      final store = _store();
      await store.createForPhone('+923001234567');
      await store.approveDriver();
      await store.approveVendor('cargo');
      return DemoPartnerWalletApi(_deadClient(), store);
    }

    test('serves simulated balance, ledger and commission rates', () async {
      final a = await api();
      final w = await a.wallet(context: _ctx);
      expect(w['points'], greaterThan(0));
      expect(w['roles'], containsAll(['driver', 'cargo']));
      expect((await a.transactions(context: _ctx)), isNotEmpty);
    });

    test('top-up lands PENDING — points never credited client-side',
        () async {
      final a = await api();
      final before = (await a.wallet(context: _ctx))['points'];
      final topup = await a.createTopup(
        points: 2000,
        method: 'jazzcash',
        context: _ctx,
      );
      expect(topup.status, 'PENDING');
      expect((await a.wallet(context: _ctx))['points'], before);
      expect((await a.topups(context: _ctx)).first.topupId, topup.topupId);
    });
  });
}

/// Test helper — the demo APIs never invoke the client; a dead-end
/// instance satisfies the constructors.
ApiClient _deadClient() => ApiClient(
      config: const NetworkConfig(
        baseUrl: 'http://demo.invalid',
        connectTimeout: Duration(seconds: 1),
        receiveTimeout: Duration(seconds: 1),
        sendTimeout: Duration(seconds: 1),
        enableRequestLogging: false,
      ),
      authTokenProvider: const NoAuthTokenProvider(),
      logger: ConsoleAppLogger(),
    );
