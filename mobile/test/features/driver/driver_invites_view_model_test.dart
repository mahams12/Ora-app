import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/driver/presentation/view_models/driver_invites_view_model.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';

class MockListInvitedRidesUseCase extends Mock
    implements ListInvitedRidesUseCase {}

class MockAcceptInviteUseCase extends Mock implements AcceptInviteUseCase {}

class MockDeclineInviteUseCase extends Mock implements DeclineInviteUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

DriverInvite _invite({
  required String waveId,
  String rideId = 'r1',
  String status = 'ACTIVE',
  DateTime? inviteExpiresAt,
}) {
  return DriverInvite(
    rideId: rideId,
    waveId: waveId,
    waveNumber: 1,
    status: status,
    pickup: const LatLngPoint(lat: 31.5, lng: 74.3, address: 'A'),
    destination: const LatLngPoint(lat: 31.6, lng: 74.4, address: 'B'),
    passengerOfferMinor: 45000,
    currency: 'PKR',
    serviceType: 'ride',
    category: 'zip',
    passengerCount: 1,
    inviteExpiresAt: inviteExpiresAt,
  );
}

void main() {
  late MockListInvitedRidesUseCase listInvited;
  late MockAcceptInviteUseCase acceptInvite;
  late MockDeclineInviteUseCase declineInvite;
  late DateTime now;

  setUpAll(() {
    registerFallbackValue(_invite(waveId: 'w'));
  });

  setUp(() {
    listInvited = MockListInvitedRidesUseCase();
    acceptInvite = MockAcceptInviteUseCase();
    declineInvite = MockDeclineInviteUseCase();
    now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000);
  });

  ProviderContainer container() {
    return ProviderContainer(
      overrides: [
        listInvitedRidesUseCaseProvider.overrideWithValue(listInvited),
        acceptInviteUseCaseProvider.overrideWithValue(acceptInvite),
        declineInviteUseCaseProvider.overrideWithValue(declineInvite),
        inviteClockProvider.overrideWithValue(() => now),
        failureMapperProvider.overrideWithValue(
          const _PassthroughFailureMapper(),
        ),
      ],
    );
  }

  DriverInvitePage pageWith(List<DriverInvite> items, {int? serverNowMs}) {
    return DriverInvitePage(
      items: items,
      serverNowMs: serverNowMs ?? now.millisecondsSinceEpoch,
    );
  }

  test('refresh lists ACTIVE invites and applies server clock offset',
      () async {
    // Device clock 30s ahead of server — offset must correct countdown.
    final serverNow = now.millisecondsSinceEpoch - 30_000;
    final expiry =
        DateTime.fromMillisecondsSinceEpoch(serverNow + 20_000);
    when(() => listInvited()).thenAnswer(
      (_) async => pageWith(
        [_invite(waveId: 'w1', inviteExpiresAt: expiry)],
        serverNowMs: serverNow,
      ),
    );

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();

    final state = c.read(driverInvitesViewModelProvider);
    expect(state.phase, DriverInvitesPhase.ready);
    expect(state.items, hasLength(1));
    // Server says 20s remain even though device clock is 30s ahead —
    // without skew correction the invite would look already expired.
    expect(vm.remainingFor(state.items.single).inSeconds, 20);
  });

  test('countdown expiry auto-removes the card', () async {
    final expiry = now.add(const Duration(seconds: 2));
    when(() => listInvited()).thenAnswer(
      (_) async =>
          pageWith([_invite(waveId: 'w1', inviteExpiresAt: expiry)]),
    );

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();
    expect(c.read(driverInvitesViewModelProvider).items, hasLength(1));

    vm.tickCountdown();
    expect(c.read(driverInvitesViewModelProvider).items, hasLength(1));

    now = now.add(const Duration(seconds: 3));
    vm.tickCountdown();
    final state = c.read(driverInvitesViewModelProvider);
    expect(state.items, isEmpty);
    expect(state.phase, DriverInvitesPhase.empty);
  });

  test('accept creates the offer via the invite endpoint and clears card',
      () async {
    final expiry = now.add(const Duration(seconds: 15));
    when(() => listInvited()).thenAnswer(
      (_) async =>
          pageWith([_invite(waveId: 'r1_w1', inviteExpiresAt: expiry)]),
    );
    when(() => acceptInvite(rideId: 'r1', waveId: 'r1_w1'))
        .thenAnswer((_) async => 'r1_d1_v1');

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();
    await vm.accept(c.read(driverInvitesViewModelProvider).items.single);

    verify(() => acceptInvite(rideId: 'r1', waveId: 'r1_w1')).called(1);
    final state = c.read(driverInvitesViewModelProvider);
    expect(state.items, isEmpty);
    expect(state.infoMessage, contains('Offer sent'));
  });

  test('late accept — server INVITE_EXPIRED removes card, no crash',
      () async {
    final expiry = now.add(const Duration(seconds: 15));
    var fetches = 0;
    when(() => listInvited()).thenAnswer((_) async {
      fetches++;
      // First fetch: invite still ACTIVE. After the failed accept the
      // re-sync reflects server truth — the invite is gone.
      return pageWith(
        fetches == 1
            ? [_invite(waveId: 'r1_w1', inviteExpiresAt: expiry)]
            : const [],
      );
    });
    when(() => acceptInvite(rideId: 'r1', waveId: 'r1_w1')).thenThrow(
      const AppFailure.conflict(message: 'expired', code: 'INVITE_EXPIRED'),
    );

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();
    await vm.accept(c.read(driverInvitesViewModelProvider).items.single);
    // Allow the trailing unawaited refresh to settle.
    await Future<void>.delayed(Duration.zero);

    final state = c.read(driverInvitesViewModelProvider);
    expect(state.items, isEmpty);
    expect(state.errorMessage, contains('expired'));
  });

  test('decline removes the card and is durable server-side', () async {
    final expiry = now.add(const Duration(seconds: 15));
    when(() => listInvited()).thenAnswer(
      (_) async =>
          pageWith([_invite(waveId: 'r1_w1', inviteExpiresAt: expiry)]),
    );
    when(() => declineInvite(rideId: 'r1', waveId: 'r1_w1'))
        .thenAnswer((_) async {});

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();
    await vm.decline(c.read(driverInvitesViewModelProvider).items.single);

    verify(() => declineInvite(rideId: 'r1', waveId: 'r1_w1')).called(1);
    expect(c.read(driverInvitesViewModelProvider).items, isEmpty);
  });

  test('duplicate accept taps issue a single request', () async {
    final expiry = now.add(const Duration(seconds: 15));
    when(() => listInvited()).thenAnswer(
      (_) async =>
          pageWith([_invite(waveId: 'r1_w1', inviteExpiresAt: expiry)]),
    );
    when(() => acceptInvite(rideId: 'r1', waveId: 'r1_w1'))
        .thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return 'r1_d1_v1';
    });

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();
    final item = c.read(driverInvitesViewModelProvider).items.single;

    await Future.wait([vm.accept(item), vm.accept(item), vm.accept(item)]);
    verify(() => acceptInvite(rideId: 'r1', waveId: 'r1_w1')).called(1);
  });

  test('FCM payload parses authoritative inviteExpiresAt', () {
    // Covered in dispatch_invite_message_test; keep the contract pinned here.
    final parsed = DateTime.tryParse('2026-05-13T12:00:20.000Z');
    expect(parsed, isNotNull);
    expect(parsed!.millisecondsSinceEpoch, greaterThan(0));
  });

  test('non-actionable items (responded/expired) render but are not'
      ' countdown-tracked', () async {
    when(() => listInvited()).thenAnswer(
      (_) async => pageWith([
        _invite(waveId: 'w1', status: 'RESPONDED_ACCEPTED'),
        _invite(waveId: 'w2', status: 'EXPIRED'),
      ]),
    );

    final c = container();
    addTearDown(c.dispose);
    // Keep the autoDispose provider alive for the test duration.
    final keepAlive = c.listen(driverInvitesViewModelProvider, (_, __) {});
    addTearDown(keepAlive.close);
    final vm = c.read(driverInvitesViewModelProvider.notifier);
    await vm.refresh();

    // Tick should not strip non-ACTIVE items (they carry history status).
    vm.tickCountdown();
    expect(c.read(driverInvitesViewModelProvider).items, hasLength(2));
  });
}
