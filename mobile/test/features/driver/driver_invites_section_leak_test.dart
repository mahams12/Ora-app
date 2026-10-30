import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/features/driver/presentation/view_models/driver_invites_view_model.dart';
import 'package:ora/features/driver/presentation/widgets/driver_invites_section.dart';
import 'package:ora/features/ride/presentation/widgets/ride_card/ride_card.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';

class _MockListInvited extends Mock implements ListInvitedRidesUseCase {}

class _MockAccept extends Mock implements AcceptInviteUseCase {}

class _MockDecline extends Mock implements DeclineInviteUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

int _countWidgets(WidgetTester tester, Type type) {
  return find.byType(type).evaluate().length;
}

void main() {
  testWidgets('bare invite card renders', (tester) async {
    final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000);
    final expiry = now.add(const Duration(seconds: 20));
    final invite = DriverInvite(
      rideId: 'r1',
      waveId: 'w1',
      waveNumber: 1,
      status: 'ACTIVE',
      pickup: const LatLngPoint(lat: 31.5, lng: 74.3, address: 'A'),
      destination: const LatLngPoint(lat: 31.6, lng: 74.4, address: 'B'),
      passengerOfferMinor: 45000,
      currency: 'PKR',
      serviceType: 'ride',
      category: 'zip',
      passengerCount: 1,
      inviteExpiresAt: expiry,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RideCard(
            model: RideCardAdapters.fromDriverInvite(
              invite,
              remaining: const Duration(seconds: 20),
              windowTotal: driverInviteWindow,
              responding: false,
              onAccept: () {},
              onDecline: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.allElements
          .where(
            (e) => e.widget.runtimeType
                .toString()
                .contains('TweenAnimationBuilder'),
          )
          .length,
      1,
    );
  });

  testWidgets(
    'invite section does not accumulate TweenAnimationBuilder elements '
    'during the countdown window',
    (tester) async {
      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000_000);
      final expiry = now.add(const Duration(seconds: 20));
      final invite = DriverInvite(
        rideId: 'r1',
        waveId: 'w1',
        waveNumber: 1,
        status: 'ACTIVE',
        pickup: const LatLngPoint(lat: 31.5, lng: 74.3, address: 'A'),
        destination: const LatLngPoint(lat: 31.6, lng: 74.4, address: 'B'),
        passengerOfferMinor: 45000,
        currency: 'PKR',
        serviceType: 'ride',
        category: 'zip',
        passengerCount: 1,
        inviteExpiresAt: expiry,
      );

      final listInvited = _MockListInvited();
      when(listInvited.call).thenAnswer(
        (_) async => DriverInvitePage(
          items: [invite],
          serverNowMs: now.millisecondsSinceEpoch,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            listInvitedRidesUseCaseProvider.overrideWithValue(listInvited),
            acceptInviteUseCaseProvider.overrideWithValue(_MockAccept()),
            declineInviteUseCaseProvider.overrideWithValue(_MockDecline()),
            inviteClockProvider.overrideWithValue(() => now),
            failureMapperProvider.overrideWithValue(
              const _PassthroughFailureMapper(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DriverInvitesSection()),
            ),
          ),
        ),
      );
      // Let the post-frame refresh + initial builds run (no pumpAndSettle —
      // the 1s view-model ticker never settles under fake async).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final baseline = _countWidgets(tester, TweenAnimationBuilder);

      // Simulate 5 seconds of the countdown — the 1s view-model ticker
      // rebuilds labels; widget counts must stay flat.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      final after = _countWidgets(tester, TweenAnimationBuilder);
      expect(after, equals(baseline));
      expect(baseline, lessThanOrEqualTo(8));
    },
  );
}
