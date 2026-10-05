import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/features/driver/domain/location/driver_location_fix.dart';
import 'package:ora/features/driver/domain/location/driver_location_lifecycle.dart';
import 'package:ora/features/driver/domain/location/driver_location_source.dart';
import 'package:ora/features/driver/domain/location/driver_location_status.dart';

void main() {
  late _FakeSource source;
  late _RecordingLogger logger;
  late DriverLocationLifecycleController controller;
  final now = DateTime.utc(2026, 10, 5, 12);

  setUp(() {
    source = _FakeSource();
    logger = _RecordingLogger();
    controller = DriverLocationLifecycleController(
      source: source,
      logger: logger,
      now: () => now,
      onStatus: (_) {},
      // Existing tests drive terminal statuses explicitly; keep the watchdog off
      // so delayed emits cannot race a 20s timer.
      acquisitionTimeout: Duration.zero,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  DriverLocationFix sample({double accuracyMeters = 8}) {
    return DriverLocationFix(
      latitude: 31.5204,
      longitude: 74.3587,
      accuracyMeters: accuracyMeters,
      speedKmh: 18,
      timestamp: now,
    );
  }

  test('1. home does not start watch', () {
    controller.onSurface(DriverLocationSurface.home);
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 0);
    expect(controller.isWatching, isFalse);
  });

  test('2. offline does not start watch', () {
    controller.onDriverOffline(true);
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 0);

    controller.onDriverOffline(false);
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_EN_ROUTE');
    expect(source.watchCount, 1);
    controller.onDriverOffline(true);
    expect(controller.isWatching, isFalse);
    expect(source.cancelCount, 1);
  });

  test('3. DRIVER_ASSIGNED starts watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 1);
    expect(controller.isWatching, isTrue);
    expect(controller.status, DriverLocationStatusKind.acquiring);
  });

  test('4. DRIVER_EN_ROUTE keeps watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_EN_ROUTE');
    expect(source.watchCount, 1);
    expect(source.cancelCount, 0);
    expect(controller.isWatching, isTrue);
  });

  test('5. DRIVER_ARRIVED keeps watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ARRIVED');
    expect(source.watchCount, 1);
    expect(controller.isWatching, isTrue);
  });

  test('6. RIDE_STARTED keeps watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_EN_ROUTE');
    controller.onRide(rideId: 'ride-1', rideState: 'RIDE_STARTED');
    expect(source.watchCount, 1);
    expect(controller.isWatching, isTrue);
  });

  test('7. terminal state stops watch', () {
    const inactive = [
      'RIDE_COMPLETED',
      'RIDE_CLOSED',
      'CANCELLED',
      'EXPIRED',
      'NO_SHOW',
      'SEARCHING',
      'OFFERS_AVAILABLE',
    ];
    for (final state in inactive) {
      controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
      expect(controller.isWatching, isTrue, reason: state);
      controller.onRide(rideId: 'ride-1', rideState: state);
      expect(controller.isWatching, isFalse, reason: state);
    }
    controller.onRide(rideId: null, rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, inactive.length);
    expect(controller.isWatching, isFalse);
  });

  test('8. background stops watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'RIDE_STARTED');
    controller.onBackground();
    expect(controller.isWatching, isFalse);
    expect(source.cancelCount, 1);
  });

  test('9. foreground resumes active ride', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ARRIVED');
    controller.onBackground();
    controller.onForeground();
    expect(controller.isWatching, isTrue);
    expect(source.watchCount, 2);

    controller.onBackground();
    controller.onRide(rideId: 'ride-1', rideState: 'CANCELLED');
    controller.onForeground();
    expect(controller.isWatching, isFalse);
    expect(source.watchCount, 2);
  });

  test('10. sign-out stops watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    controller.onSignedOut();
    expect(controller.isWatching, isFalse);
    expect(source.cancelCount, 1);
    controller.onForeground();
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 1);
    expect(controller.isWatching, isFalse);
  });

  test('11. dispose cancels watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'RIDE_STARTED');
    controller.dispose();
    expect(controller.isWatching, isFalse);
    expect(source.cancelCount, 1);
    controller.dispose();
    expect(source.cancelCount, 1);
  });

  test(
    '12. repeated active-state updates do not create duplicate subscriptions',
    () {
      controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
      controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
      controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_EN_ROUTE');
      controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ARRIVED');
      controller.onRide(rideId: 'ride-1', rideState: 'RIDE_STARTED');
      expect(source.watchCount, 1);
      expect(source.cancelCount, 0);
      expect(controller.isWatching, isTrue);
    },
  );

  test('accepted fixes do not notify again and logs omit coordinates', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    final afterStart = controller.statusChangeCount;
    final reading = DriverLocationFixReading(sample());
    source.emit(reading);
    source.emit(reading);
    source.emit(reading);
    expect(controller.status, DriverLocationStatusKind.ready);
    expect(controller.statusChangeCount, afterStart + 1);

    source.emit(DriverLocationFixReading(sample(accuracyMeters: 80)));
    expect(controller.status, DriverLocationStatusKind.poorAccuracy);

    final blob = logger.records
        .map((record) => '${record.message} ${record.metadata}')
        .join('\n');
    expect(blob, isNot(contains('31.5204')));
    expect(blob, isNot(contains('74.3587')));
    expect(blob, contains('ACCEPTED'));
    expect(blob, contains('POOR_ACCURACY'));
    expect(blob, contains('ride-1'));
  });

  test('service disabled and permission failure use friendly statuses', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.serviceDisabled,
      ),
    );
    expect(controller.status, DriverLocationStatusKind.servicesDisabled);
    expect(driverLocationStatusLabel(controller.status), 'Location is turned off');
    expect(
      driverLocationStatusActionLabel(controller.status),
      'Turn on location',
    );

    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDenied,
      ),
    );
    expect(controller.status, DriverLocationStatusKind.permissionNeeded);
    expect(
      driverLocationStatusLabel(controller.status),
      'Location permission is needed',
    );
    expect(
      driverLocationStatusActionLabel(controller.status),
      'Allow location',
    );

    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDeniedForever,
      ),
    );
    expect(controller.status, DriverLocationStatusKind.permissionBlocked);
    expect(
      driverLocationStatusLabel(controller.status),
      'Location permission is needed',
    );
    expect(
      driverLocationStatusActionLabel(controller.status),
      'Open settings',
    );
  });

  test('stream end while acquiring leaves a terminal status, not acquiring', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(controller.status, DriverLocationStatusKind.acquiring);
    source.closeActive();
    expect(controller.isWatching, isFalse);
    expect(controller.status, isNot(DriverLocationStatusKind.acquiring));
    expect(controller.status, DriverLocationStatusKind.unavailable);
    expect(
      driverLocationStatusLabel(controller.status),
      'Location is temporarily unavailable',
    );
  });

  test('acquisition timeout leaves acquiring for a terminal status', () async {
    controller.dispose();
    controller = DriverLocationLifecycleController(
      source: source,
      logger: logger,
      now: () => now,
      onStatus: (_) {},
      acquisitionTimeout: const Duration(milliseconds: 40),
    );
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(controller.status, DriverLocationStatusKind.acquiring);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(controller.status, isNot(DriverLocationStatusKind.acquiring));
    expect(controller.status, DriverLocationStatusKind.unavailable);
    expect(controller.isWatching, isFalse);
    expect(
      logger.records.any((r) => r.message == 'location_acquisition_failed'),
      isTrue,
    );
  });

  test('permission denial does not auto-restart the watch', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 1);
    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDenied,
      ),
    );
    source.closeActive();
    expect(source.watchCount, 1);
    expect(controller.status, DriverLocationStatusKind.permissionNeeded);

    // Same ride, state flicker must not restart.
    controller.onRide(rideId: 'ride-1', rideState: null);
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 1);
    expect(controller.status, DriverLocationStatusKind.permissionNeeded);

    // System permission-sheet lifecycle must not restart after soft deny.
    controller.onBackground();
    controller.onForeground();
    expect(source.watchCount, 1);
    expect(controller.status, DriverLocationStatusKind.permissionNeeded);

    // Reconcile without user action must not start another watch.
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(source.watchCount, 1);
  });

  test('user recovery after permission denial starts a new watch', () async {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    source.emit(
      const DriverLocationFailureReading(
        DriverLocationAcquisitionFailure.permissionDenied,
      ),
    );
    source.closeActive();
    expect(source.watchCount, 1);

    await controller.onUserRecoveryAction();
    expect(source.watchCount, 2);
    expect(controller.status, DriverLocationStatusKind.acquiring);
  });

  test('terminal cancel while watching stops GPS and does not restart on home', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    expect(controller.isWatching, isTrue);
    source.emit(DriverLocationFixReading(sample()));
    expect(controller.status, DriverLocationStatusKind.ready);

    controller.onRide(rideId: 'ride-1', rideState: 'CANCELLED');
    expect(controller.isWatching, isFalse);
    expect(source.cancelCount, 1);

    controller.onSurface(DriverLocationSurface.home);
    controller.onRide(rideId: null, rideState: null);
    expect(controller.isWatching, isFalse);
    expect(source.watchCount, 1);
  });

  test('acquisition timing diagnostics omit coordinates', () {
    controller.onRide(rideId: 'ride-1', rideState: 'DRIVER_ASSIGNED');
    source.emit(DriverLocationFixReading(sample()));
    final blob = logger.records
        .map((record) => '${record.message} ${record.metadata}')
        .join('\n');
    expect(blob, contains('location_first_callback'));
    expect(blob, contains('location_first_accepted'));
    expect(blob, contains('elapsedMs'));
    expect(blob, isNot(contains('31.5204')));
    expect(blob, isNot(contains('74.3587')));
  });
}

class _FakeSource extends DriverLocationSource {
  int watchCount = 0;
  int cancelCount = 0;
  int openPermissionSettingsCount = 0;
  int openLocationSettingsCount = 0;
  final List<StreamController<DriverLocationReading>> controllers = [];

  @override
  Stream<DriverLocationReading> watch() {
    watchCount++;
    final controller = StreamController<DriverLocationReading>(
      sync: true,
      onCancel: () {
        cancelCount++;
      },
    );
    controllers.add(controller);
    return controller.stream;
  }

  void emit(DriverLocationReading reading) {
    controllers.last.add(reading);
  }

  void closeActive() {
    final controller = controllers.last;
    if (!controller.isClosed) {
      controller.close();
    }
  }

  @override
  Future<bool> openPermissionSettings() async {
    openPermissionSettingsCount++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCount++;
    return true;
  }
}

class _RecordingLogger extends AppLogger {
  final List<LogRecord> records = [];

  @override
  void log(LogRecord record) {
    records.add(record);
  }
}
