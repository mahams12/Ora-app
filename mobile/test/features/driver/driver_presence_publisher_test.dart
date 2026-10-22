import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/features/driver/data/location/driver_location_remote_data_source.dart';
import 'package:ora/features/driver/domain/location/driver_location_fix.dart';
import 'package:ora/features/driver/domain/location/driver_location_source.dart';
import 'package:ora/features/driver/domain/location/driver_presence_publisher.dart';

void main() {
  late _FakeRemote remote;
  late _FakeSource source;
  late _RecordingLogger logger;
  late DateTime now;
  late DriverPresencePublisher publisher;
  var streamCounter = 0;

  DriverLocationFix fix({double accuracy = 8, DateTime? timestamp}) {
    return DriverLocationFix(
      latitude: 31.52,
      longitude: 74.35,
      accuracyMeters: accuracy,
      speedKmh: 0,
      timestamp: timestamp ?? now,
    );
  }

  setUp(() {
    remote = _FakeRemote();
    source = _FakeSource();
    logger = _RecordingLogger();
    now = DateTime.utc(2026, 10, 21, 12);
    streamCounter = 0;
    publisher = DriverPresencePublisher(
      remote: remote,
      source: source,
      logger: logger,
      now: () => now,
      newStreamId: () => 'idle-stream-${++streamCounter}',
    );
  });

  tearDown(() {
    publisher.dispose();
  });

  test('does not watch or publish while offline', () {
    fakeAsync((async) {
      publisher.onAvailability(online: false);
      source.emit(fix());
      async.flushMicrotasks();
      expect(source.watchCount, 0);
      expect(remote.idleCalls, 0);
    });
  });

  test('going online starts watch and publishes on first fix', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      expect(source.watchCount, 1);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
      expect(remote.lastStreamId, 'idle-stream-1');
      expect(remote.seqs, [1]);
    });
  });

  test('publishes at most once per interval; heartbeat keeps presence', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      // Burst of fixes — only the first publishes (interval gate).
      source.emit(fix());
      async.flushMicrotasks();
      source.emit(fix());
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);

      // Live watch keeps emitting fresh fixes; heartbeat publishes each
      // interval — the same fix is only republishable for 12s (freshness).
      now = now.add(const Duration(seconds: 10));
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(remote.idleCalls, 2);
      expect(remote.seqs, [1, 2]);

      now = now.add(const Duration(seconds: 10));
      source.emit(fix()); // fresh fix (watch keeps sampling)
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(remote.idleCalls, 3);
    });
  });

  test('stale fix is not republished by heartbeat', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
      // Fix is now 20s old (> 12s freshness) — heartbeat must skip it so the
      // server-side marker expires and the driver leaves matching (fail-closed).
      now = now.add(const Duration(seconds: 20));
      async.elapse(const Duration(seconds: 20));
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
    });
  });

  test('poor-accuracy fix is skipped client-side', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix(accuracy: 80)); // > kPresenceMaxAccuracyMeters
      async.flushMicrotasks();
      expect(remote.idleCalls, 0);
      // Heartbeat must not republish it either.
      now = now.add(const Duration(seconds: 15));
      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(remote.idleCalls, 0);
    });
  });

  test('background stops; foreground resumes with fresh stream', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);

      publisher.onBackground();
      expect(publisher.isPublishing, isFalse);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);

      publisher.onForeground();
      expect(source.watchCount, 2);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 2);
      expect(remote.lastStreamId, 'idle-stream-2');
      expect(remote.seqs, [1, 1]);
    });
  });

  test('going offline stops immediately', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
      publisher.onAvailability(online: false);
      expect(publisher.isPublishing, isFalse);
      source.emit(fix());
      now = now.add(const Duration(seconds: 30));
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
    });
  });

  test('sign-out stops permanently', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      publisher.onSignedOut();
      expect(publisher.isPublishing, isFalse);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
    });
  });

  test('in-flight publish: latest fix is picked up after completion', () {
    fakeAsync((async) {
      remote.delay = const Duration(milliseconds: 500);
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
      // While in-flight, fixes queue (latest only) — but interval gate still
      // applies after completion, so no immediate second publish.
      source.emit(fix());
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(remote.idleCalls, 1);
    });
  });

  test('logs never include coordinates', () {
    fakeAsync((async) {
      publisher.onAvailability(online: true);
      source.emit(fix());
      async.flushMicrotasks();
      for (final record in logger.records) {
        expect(record.metadata?.keys, isNot(contains('lat')));
        expect(record.metadata?.keys, isNot(contains('lng')));
        expect(record.metadata?.keys, isNot(contains('latitude')));
        expect(record.metadata?.keys, isNot(contains('longitude')));
      }
    });
  });
}

class _FakeSource extends DriverLocationSource {
  final _controllers = <StreamController<DriverLocationReading>>[];
  int watchCount = 0;

  @override
  Stream<DriverLocationReading> watch() {
    watchCount++;
    final controller = StreamController<DriverLocationReading>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }

  void emit(DriverLocationFix fix) {
    for (final c in _controllers) {
      if (!c.isClosed) c.add(DriverLocationFixReading(fix));
    }
  }
}

class _FakeRemote implements DriverLocationRemoteDataSource {
  int idleCalls = 0;
  int? lastSeq;
  String? lastStreamId;
  final seqs = <int>[];
  Duration delay = Duration.zero;

  @override
  Future<LocationPublishResult> publishTripLocation({
    required String rideId,
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    throw UnimplementedError('presence tests must not publish trip locations');
  }

  @override
  Future<LocationPublishResult> publishIdleLocation({
    required int locationSeq,
    required String locationStreamId,
    required DriverLocationFix fix,
    required CancelToken cancelToken,
    RequestContext? context,
  }) async {
    idleCalls++;
    seqs.add(locationSeq);
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
    return LocationPublishAccepted(
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
