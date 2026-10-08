import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/features/driver/data/location/driver_location_remote_data_source.dart';
import 'package:ora/features/driver/domain/location/driver_location_fix.dart';
import 'package:ora/features/driver/domain/location/driver_location_source.dart';
import 'package:ora/features/driver/presentation/location/driver_location_session.dart';
import 'package:ora/features/driver/presentation/views/driver_assigned_ride_view.dart';
import 'package:ora/features/driver/presentation/widgets/driver_location_status_line.dart';
import 'package:ora/features/ride/domain/entities/ride.dart';
import 'package:ora/features/ride/domain/use_cases/ride_use_cases.dart';
import 'package:ora/features/ride/presentation/view_models/active_ride_view_model.dart';

import '../../helpers/in_memory_idempotency_nonce_store.dart';

class _MockGetRide extends Mock implements GetRideUseCase {}

class _MockEnRoute extends Mock implements MarkEnRouteUseCase {}

class _MockArrived extends Mock implements MarkArrivedUseCase {}

class _MockStart extends Mock implements StartRideUseCase {}

class _MockComplete extends Mock implements CompleteRideUseCase {}

class _MockCancel extends Mock implements CancelRideUseCase {}

class _MockClose extends Mock implements CloseRideUseCase {}

class _PassthroughFailureMapper extends FailureMapper {
  const _PassthroughFailureMapper();

  @override
  AppFailure fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppFailure) return error;
    return AppFailure.unknown(message: error.toString());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedSource source;

  setUp(() {
    source = _ScriptedSource();
  });

  Future<void> pumpRide(WidgetTester tester) async {
    final getRide = _MockGetRide();
    when(() => getRide('ride-1')).thenAnswer((_) async => _ride());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          getRideUseCaseProvider.overrideWithValue(getRide),
          markEnRouteUseCaseProvider.overrideWithValue(_MockEnRoute()),
          markArrivedUseCaseProvider.overrideWithValue(_MockArrived()),
          startRideUseCaseProvider.overrideWithValue(_MockStart()),
          completeRideUseCaseProvider.overrideWithValue(_MockComplete()),
          cancelRideUseCaseProvider.overrideWithValue(_MockCancel()),
          closeRideUseCaseProvider.overrideWithValue(_MockClose()),
          failureMapperProvider.overrideWithValue(
            const _PassthroughFailureMapper(),
          ),
          idempotencyNonceStoreProvider.overrideWithValue(
            InMemoryIdempotencyNonceStore(),
          ),
          activeRidePollingPolicyProvider.overrideWithValue(
            const ActiveRidePollingPolicy(
              intervals: [Duration(days: 1)],
              maxLifetime: Duration(days: 1),
            ),
          ),
          driverLocationSourceProvider.overrideWithValue(source),
          driverLocationRemoteDataSourceProvider.overrideWithValue(
            const _NoopLocationRemote(),
          ),
        ],
        child: const MaterialApp(
          home: DriverAssignedRideView(rideId: 'ride-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('assigned ride displays location status', (tester) async {
    await pumpRide(tester);
    expect(find.text('Getting your location…'), findsOneWidget);
    expect(source.watchCount, 1);
    expect(find.byIcon(Icons.map_outlined), findsNothing);
    expect(find.text('Map preview'), findsNothing);
    expect(find.textContaining('Redis'), findsNothing);
    expect(find.textContaining('24.86000'), findsNothing);

    final changesAtStart = _session(tester).statusChangeCount;
    source.emit(DriverLocationFixReading(_fix()));
    source.emit(DriverLocationFixReading(_fix()));
    source.emit(DriverLocationFixReading(_fix()));
    await tester.pump();

    expect(find.text('Location is ready'), findsOneWidget);
    expect(_session(tester).statusChangeCount, changesAtStart + 1);
    expect(find.byType(DriverLocationStatusLine), findsOneWidget);
  });

  testWidgets('poor accuracy displays friendly status', (tester) async {
    await pumpRide(tester);
    source.emit(DriverLocationFixReading(_fix(accuracyMeters: 80)));
    await tester.pump();
    expect(find.text('Location accuracy is low'), findsOneWidget);
    expect(find.textContaining('50'), findsNothing);
  });

  testWidgets('location unavailable displays friendly status', (tester) async {
    await pumpRide(tester);
    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDenied,
      ),
    );
    await tester.pump();
    expect(find.text('Location permission is needed'), findsOneWidget);
    expect(find.text('Allow location'), findsOneWidget);
    expect(find.text('Getting your location…'), findsNothing);
    expect(find.textContaining('PERMISSION'), findsNothing);
    expect(find.textContaining('denied'), findsNothing);
    expect(find.textContaining('LocationPermission'), findsNothing);

    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDeniedForever,
      ),
    );
    await tester.pump();
    expect(find.text('Location permission is needed'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);

    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.serviceDisabled,
      ),
    );
    await tester.pump();
    expect(find.text('Location is turned off'), findsOneWidget);
    expect(find.text('Turn on location'), findsOneWidget);
  });

  testWidgets('stream end while acquiring leaves recovery UI', (tester) async {
    await pumpRide(tester);
    expect(find.text('Getting your location…'), findsOneWidget);
    source.closeActive();
    await tester.pump();
    expect(find.text('Getting your location…'), findsNothing);
    expect(find.text('Location is temporarily unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('assigned ride copy avoids engineering terms', (tester) async {
    await pumpRide(tester);
    expect(find.textContaining('server'), findsNothing);
    expect(find.textContaining('Server'), findsNothing);
    expect(find.textContaining('API'), findsNothing);
    expect(find.textContaining('Redis'), findsNothing);
    expect(find.textContaining('RTDB'), findsNothing);
    expect(find.textContaining('requestVersion'), findsNothing);
    expect(find.textContaining('Checking for server'), findsNothing);
  });

  testWidgets('leaving the screen stops the watch and return resumes it', (
    tester,
  ) async {
    await pumpRide(tester);
    expect(source.watchCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(source.cancelCount, 1);
    expect(source.watchCount, 1);

    await pumpRide(tester);
    expect(source.watchCount, 2);
    expect(find.text('Getting your location…'), findsOneWidget);
  });
}

DriverLocationSession _session(WidgetTester tester) {
  final context = tester.element(find.byType(DriverLocationStatusLine));
  return ProviderScope.containerOf(
    context,
  ).read(driverLocationSessionProvider('ride-1').notifier);
}

Ride _ride() {
  return const Ride(
    rideId: 'ride-1',
    passengerId: 'passenger-1',
    assignedDriverId: 'driver-1',
    state: 'DRIVER_ASSIGNED',
    version: 2,
    requestVersion: 1,
    category: 'economy',
    serviceType: 'ride',
    pickup: LatLngPoint(lat: 24.86, lng: 67.01, address: 'Pickup point'),
    destination: LatLngPoint(lat: 24.92, lng: 67.08, address: 'Dropoff point'),
    pricingSnapshotId: 'snap-1',
    recommendedFareMinor: 25000,
    passengerOfferMinor: 25000,
    paymentMethod: 'CASH',
    passengerCount: 1,
    expiresAt: '2099-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

DriverLocationFix _fix({double accuracyMeters = 8}) {
  return DriverLocationFix(
    latitude: 31.5204,
    longitude: 74.3587,
    accuracyMeters: accuracyMeters,
    speedKmh: 12,
    timestamp: DateTime.now(),
  );
}

class _NoopLocationRemote implements DriverLocationRemoteDataSource {
  const _NoopLocationRemote();

  @override
  Future<LocationPublishResult> publishTripLocation({
    required String rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    return LocationPublishAccepted(
      locationSeq: locationSeq,
      locationStreamId: locationStreamId,
      acceptedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }
}

class _ScriptedSource extends DriverLocationSource {
  int watchCount = 0;
  int cancelCount = 0;
  StreamController<DriverLocationReading>? _active;

  @override
  Stream<DriverLocationReading> watch() {
    watchCount++;
    final controller = StreamController<DriverLocationReading>(
      sync: true,
      onCancel: () => cancelCount++,
    );
    _active = controller;
    return controller.stream;
  }

  void emit(DriverLocationReading reading) {
    _active!.add(reading);
  }

  void closeActive() {
    final active = _active;
    if (active != null && !active.isClosed) {
      active.close();
    }
  }
}
