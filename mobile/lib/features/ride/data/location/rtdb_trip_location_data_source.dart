import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../../core/logging/app_logger.dart';
import '../../domain/models/trip_location_latest.dart';
import '../../domain/ports/trip_location_port.dart';

/// Read-only RTDB adapter for `tripLocations/{rideId}/latest`.
///
/// NEVER writes. Malformed payloads and permission errors are soft.
class RtdbTripLocationDataSource implements TripLocationPort {
  RtdbTripLocationDataSource({
    required String databaseUrl,
    required AppLogger logger,
    FirebaseDatabase? database,
  })  : _databaseUrl = databaseUrl.trim(),
        _logger = logger,
        _database = database;

  final String _databaseUrl;
  final AppLogger _logger;
  final FirebaseDatabase? _database;

  static final _forbiddenSegment = RegExp(r'[./#$\[\]]');

  FirebaseDatabase get _db {
    final existing = _database;
    if (existing != null) return existing;
    if (_databaseUrl.isEmpty) {
      return FirebaseDatabase.instance;
    }
    return FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: _databaseUrl,
    );
  }

  @override
  Stream<TripLocationLatest?> watchLatest(String rideId) {
    final safeId = _safeRideId(rideId);
    if (safeId == null) {
      _logger.warning(
        'trip_location_watch_rejected_ride_id',
        metadata: const {'reason': 'invalid_segment'},
      );
      return Stream<TripLocationLatest?>.value(null);
    }

    final controller = StreamController<TripLocationLatest?>.broadcast();
    StreamSubscription<DatabaseEvent>? sub;
    var closed = false;

    void softClose() {
      if (closed) return;
      closed = true;
      unawaited(sub?.cancel());
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }

    try {
      final ref = _db.ref('tripLocations/$safeId/latest');
      sub = ref.onValue.listen(
        (event) {
          if (closed) return;
          final raw = event.snapshot.value;
          if (raw == null) {
            controller.add(null);
            return;
          }
          final parsed = TripLocationLatest.tryParse(raw);
          if (parsed == null) {
            _logger.warning(
              'trip_location_malformed_skipped',
              metadata: {'rideIdPresent': true},
            );
            // Skip malformed — do not emit / do not crash.
            return;
          }
          controller.add(parsed);
        },
        onError: (Object error, StackTrace stack) {
          // permission_denied after terminal cleanup is expected.
          _logger.info(
            'trip_location_watch_unavailable',
            metadata: {
              'errorType': error.runtimeType.toString(),
            },
          );
          if (!controller.isClosed) {
            controller.add(null);
          }
          softClose();
        },
        onDone: softClose,
        cancelOnError: false,
      );
    } catch (error) {
      _logger.warning(
        'trip_location_watch_start_failed',
        metadata: {'errorType': error.runtimeType.toString()},
      );
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          controller.add(null);
          softClose();
        }
      });
    }

    controller.onCancel = () {
      softClose();
    };

    return controller.stream;
  }

  String? _safeRideId(String rideId) {
    final trimmed = rideId.trim();
    if (trimmed.isEmpty) return null;
    if (_forbiddenSegment.hasMatch(trimmed) || trimmed.contains('/')) {
      return null;
    }
    return trimmed;
  }
}

/// In-memory fake for tests — never touches Firebase.
class MemoryTripLocationPort implements TripLocationPort {
  MemoryTripLocationPort();

  final _controllers = <String, StreamController<TripLocationLatest?>>{};
  int watchStartCount = 0;
  final activeRideIds = <String>{};

  void emit(String rideId, TripLocationLatest? value) {
    final c = _controllers[rideId];
    if (c == null || c.isClosed) return;
    c.add(value);
  }

  void error(String rideId, Object error) {
    final c = _controllers[rideId];
    if (c == null || c.isClosed) return;
    c.addError(error);
  }

  @override
  Stream<TripLocationLatest?> watchLatest(String rideId) {
    watchStartCount += 1;
    activeRideIds.add(rideId);
    final controller = StreamController<TripLocationLatest?>();
    _controllers[rideId] = controller;
    controller.onCancel = () {
      activeRideIds.remove(rideId);
      if (identical(_controllers[rideId], controller)) {
        _controllers.remove(rideId);
      }
    };
    return controller.stream;
  }
}
