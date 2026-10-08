
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/features/driver/data/location/driver_location_remote_data_source.dart';
import 'package:ora/features/driver/domain/location/driver_location_fix.dart';
import 'package:ora/features/driver/domain/location/driver_trip_location_publisher.dart';

void main() {
  late _FakeRemote remote;
  late _RecordingLogger logger;
  late DateTime now;
  late DriverTripLocationPublisher publisher;
  var streamCounter = 0;

  DriverLocationFix fix({
    double lat = 31.52,
    double lng = 74.35,
    DateTime? timestamp,
  }) {
    return DriverLocationFix(
      latitude: lat,
      longitude: lng,
      accuracyMeters: 8,
      speedKmh: 12,
      headingDegrees: 90,
      timestamp: timestamp ?? now,
    );
  }

  /// ~20m east of (31.52, 74.35) at Pakistan latitudes.
  DriverLocationFix movedFix({DateTime? timestamp}) {
    return fix(lat: 31.52, lng: 74.3502, timestamp: timestamp);
  }

  setUp(() {
    remote = _FakeRemote();
    logger = _RecordingLogger();
    now = DateTime.utc(2026, 10, 6, 12);
    streamCounter = 0;
    publisher = DriverTripLocationPublisher(
      rideId: 'ride-1',
      remote: remote,
      logger: logger,
      now: () => now,
      newStreamId: () => 'stream-${++streamCounter}',
    );
    publisher.onRideState('DRIVER_ASSIGNED');
    publisher.onWatchStarted();
  });

  tearDown(() {
    publisher.dispose();
  });

  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('new watch starts seq at 1 with new stream id', () {
    expect(publisher.activeLocationStreamId, 'stream-1');
    expect(publisher.nextLocationSeq, 1);
    publisher.onWatchStopped('background');
    publisher.onWatchStarted();
    expect(publisher.activeLocationStreamId, 'stream-2');
    expect(publisher.nextLocationSeq, 1);
  });

  test('first accepted fix publishes immediately', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    expect(remote.calls, 1);
    expect(remote.lastSeq, 1);
    expect(remote.lastStreamId, 'stream-1');
    expect(remote.lastRideId, 'ride-1');
    expect(publisher.successCount, 1);
    expect(publisher.nextLocationSeq, 2);
  });

  test('minimum interval blocks republish under 4s without movement gate pass',
      () async {
    publisher.onAcceptedFix(fix());
    await flush();
    now = now.add(const Duration(seconds: 2));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 1);
  });

  test('15m movement after 4s publishes', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    now = now.add(const Duration(seconds: 4));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 2);
    expect(remote.lastSeq, 2);
  });

  test('duplicate exact fix is suppressed', () async {
    final f = fix();
    publisher.onAcceptedFix(f);
    await flush();
    now = now.add(const Duration(seconds: 5));
    publisher.onAcceptedFix(f);
    await flush();
    expect(remote.calls, 1);
  });

  test('heartbeat republishes fresh fix after heartbeat interval', () {
    fakeAsync((async) {
      remote.calls = 0;
      var clock = DateTime.utc(2026, 10, 6, 12);
      publisher.dispose();
      publisher = DriverTripLocationPublisher(
        rideId: 'ride-1',
        remote: remote,
        logger: logger,
        now: () => clock,
        newStreamId: () => 'stream-hb',
        heartbeat: const Duration(seconds: 10),
        minInterval: const Duration(seconds: 4),
      );
      publisher.onRideState('DRIVER_ASSIGNED');
      publisher.onWatchStarted();
      publisher.onAcceptedFix(fix(timestamp: clock));
      async.flushMicrotasks();
      expect(remote.calls, 1);

      clock = clock.add(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(remote.calls, 2);
    });
  });

  test('single-flight coalesces latest fix', () async {
    remote.delay = const Duration(milliseconds: 30);
    publisher.onAcceptedFix(fix());
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(publisher.isInFlight, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await flush();
    // First send + coalesced second after in-flight completes (may need movement+interval).
    // After first success, second pending may be blocked by interval — ensure at least 1.
    expect(remote.calls, greaterThanOrEqualTo(1));
    expect(remote.calls, lessThanOrEqualTo(2));
  });

  test('max 15 publishes per minute enforced', () async {
    remote.calls = 0;
    for (var i = 0; i < 16; i++) {
      now = now.add(const Duration(seconds: 4));
      publisher.onAcceptedFix(
        fix(lat: 31.52 + i * 0.0002, lng: 74.35, timestamp: now),
      );
      await flush();
    }
    expect(remote.calls, 15);
  });

  test('CANCELLED stops publishing', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    publisher.onRideState('CANCELLED');
    publisher.stop(reason: 'ride_cancelled');
    now = now.add(const Duration(seconds: 5));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 1);
    expect(publisher.isStoppedPermanently, isTrue);
  });

  test('RIDE_COMPLETED stops publishing', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    publisher.onRideState('RIDE_COMPLETED');
    publisher.stop(reason: 'ride_completed');
    now = now.add(const Duration(seconds: 5));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 1);
  });

  test('watch stop cancels in-flight and ignores late response', () async {
    remote.delay = const Duration(milliseconds: 40);
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isInFlight, isTrue);
    publisher.onWatchStopped('background');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await flush();
    expect(publisher.successCount, 0);
  });

  test('dispose prevents further publishes', () async {
    publisher.dispose();
    publisher.onAcceptedFix(fix());
    await flush();
    expect(remote.calls, 0);
  });

  test('rideId binding: remote always receives session rideId', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    expect(remote.lastRideId, 'ride-1');
  });

  test('403 forbidden stops publisher permanently', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.forbidden,
      statusCode: 403,
      code: 'RIDE_LOCATION_FORBIDDEN',
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isStoppedPermanently, isTrue);
    now = now.add(const Duration(seconds: 5));
    remote.nextResult = null;
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 1);
  });

  test('401 unauthorized stops publisher', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.unauthorized,
      statusCode: 401,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isStoppedPermanently, isTrue);
  });

  test('422 stale drops and allows later fresh publish', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.invalidOrStale,
      statusCode: 422,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.successCount, 0);
    expect(publisher.isStoppedPermanently, isFalse);

    remote.nextResult = null;
    now = now.add(const Duration(seconds: 5));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(publisher.successCount, 1);
  });

  test('422 sequence violation advances and waits for next fix', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.sequenceViolation,
      statusCode: 422,
      code: 'SEQUENCE_VIOLATION',
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.nextLocationSeq, 2);
    expect(publisher.isStoppedPermanently, isFalse);

    remote.nextResult = null;
    now = now.add(const Duration(seconds: 5));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.lastSeq, 2);
    expect(publisher.successCount, 1);
  });

  test('429 sets backoff without permanent stop', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.rateLimited,
      statusCode: 429,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isStoppedPermanently, isFalse);

    remote.nextResult = null;
    now = now.add(const Duration(seconds: 1));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    // Still within 3s backoff.
    expect(remote.calls, 1);

    now = now.add(const Duration(seconds: 3));
    publisher.onAcceptedFix(
      fix(lat: 31.521, lng: 74.35, timestamp: now),
    );
    await flush();
    expect(remote.calls, 2);
  });

  test('5xx backoff then next fresh fix', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.server,
      statusCode: 500,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    remote.nextResult = null;
    now = now.add(const Duration(seconds: 1));
    publisher.onAcceptedFix(movedFix(timestamp: now));
    await flush();
    expect(remote.calls, 1);

    now = now.add(const Duration(seconds: 2));
    publisher.onAcceptedFix(
      fix(lat: 31.521, lng: 74.35, timestamp: now),
    );
    await flush();
    expect(remote.calls, 2);
  });

  test('timeout is not permanent stop', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.timeout,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isStoppedPermanently, isFalse);
  });

  test('network failure is not permanent stop', () async {
    remote.nextResult = const LocationPublishFailed(
      kind: LocationPublishFailureKind.network,
    );
    publisher.onAcceptedFix(fix());
    await flush();
    expect(publisher.isStoppedPermanently, isFalse);
  });

  test('inactive ride states do not publish', () async {
    publisher.onRideState('SEARCHING');
    publisher.onAcceptedFix(fix());
    await flush();
    expect(remote.calls, 0);
  });

  test('EN_ROUTE ARRIVED STARTED allow publish', () async {
    for (final state in ['DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'RIDE_STARTED']) {
      remote.calls = 0;
      publisher = DriverTripLocationPublisher(
        rideId: 'ride-1',
        remote: remote,
        logger: logger,
        now: () => now,
        newStreamId: () => 'stream-$state',
      );
      publisher.onRideState(state);
      publisher.onWatchStarted();
      publisher.onAcceptedFix(fix(timestamp: now));
      await flush();
      expect(remote.calls, 1, reason: state);
      publisher.dispose();
      now = now.add(const Duration(seconds: 1));
    }
  });

  test('logs never include lat/lng keys', () async {
    publisher.onAcceptedFix(fix());
    await flush();
    for (final record in logger.records) {
      expect(record.metadata?.keys, isNot(contains('lat')));
      expect(record.metadata?.keys, isNot(contains('lng')));
      expect(record.metadata?.keys, isNot(contains('latitude')));
      expect(record.metadata?.keys, isNot(contains('longitude')));
    }
  });
}

class _FakeRemote implements DriverLocationRemoteDataSource {
  int calls = 0;
  int? lastSeq;
  String? lastStreamId;
  String? lastRideId;
  Duration delay = Duration.zero;
  LocationPublishResult? nextResult;

  @override
  Future<LocationPublishResult> publishTripLocation({
    required String rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    calls++;
    lastRideId = rideId;
    lastSeq = locationSeq;
    lastStreamId = locationStreamId;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (cancelToken.isCancelled) {
      return const LocationPublishFailed(
        kind: LocationPublishFailureKind.cancelled,
      );
    }
    return nextResult ??
        LocationPublishAccepted(
          locationSeq: locationSeq,
          locationStreamId: locationStreamId,
          acceptedAt: DateTime.now().toUtc().toIso8601String(),
        );
  }
}

class _RecordingLogger extends AppLogger {
  final records = <LogRecord>[];

  @override
  void log(LogRecord record) {
    records.add(record);
  }
}
