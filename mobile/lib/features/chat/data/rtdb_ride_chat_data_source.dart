import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../../core/logging/app_logger.dart';
import '../domain/models/ride_chat_message.dart';
import '../domain/ports/ride_chat_port.dart';

/// RTDB adapter for `rideChats/{rideId}/messages`.
///
/// Mirrors [RtdbTripLocationDataSource] conventions: invalid ride ids and
/// permission/malformed payloads are soft failures, never crashes.
class RtdbRideChatDataSource implements RideChatPort {
  RtdbRideChatDataSource({
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

  String? _safeRideId(String rideId) {
    final trimmed = rideId.trim();
    if (trimmed.isEmpty || _forbiddenSegment.hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  @override
  Stream<List<RideChatMessage>> watchMessages(String rideId) {
    final safeId = _safeRideId(rideId);
    if (safeId == null) {
      _logger.warning(
        'ride_chat_watch_rejected_ride_id',
        metadata: const {'reason': 'invalid_segment'},
      );
      return Stream<List<RideChatMessage>>.value(const []);
    }

    final controller = StreamController<List<RideChatMessage>>.broadcast();
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
      final ref = _db
          .ref('rideChats/$safeId/messages')
          .orderByChild('createdAtMs');
      sub = ref.onValue.listen(
        (event) {
          if (closed) return;
          final raw = event.snapshot.value;
          if (raw is! Map) {
            controller.add(const []);
            return;
          }
          final messages = <RideChatMessage>[];
          raw.forEach((key, value) {
            final parsed = _tryParse(key, value);
            if (parsed != null) messages.add(parsed);
          });
          messages.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
          controller.add(messages);
        },
        onError: (Object error, StackTrace stack) {
          _logger.info(
            'ride_chat_watch_unavailable',
            metadata: {'errorType': error.runtimeType.toString()},
          );
          if (!controller.isClosed) {
            controller.add(const []);
          }
          softClose();
        },
        onDone: softClose,
        cancelOnError: false,
      );
    } catch (error) {
      _logger.warning(
        'ride_chat_watch_start_failed',
        metadata: {'errorType': error.runtimeType.toString()},
      );
      scheduleMicrotask(() {
        if (!controller.isClosed) {
          controller.add(const []);
          softClose();
        }
      });
    }

    controller.onCancel = softClose;
    return controller.stream;
  }

  /// Writes a message under `rideChats/{rideId}/messages/{pushKey}`.
  @override
  Future<RideChatMessage> sendMessage(
    String rideId, {
    required String authorId,
    required String authorName,
    required String text,
  }) async {
    final safeId = _safeRideId(rideId);
    if (safeId == null) {
      _logger.warning(
        'ride_chat_send_rejected_ride_id',
        metadata: const {'reason': 'invalid_segment'},
      );
      throw StateError('Invalid ride id for chat');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw StateError('Empty chat message');
    }
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final ref = _db.ref('rideChats/$safeId/messages').push();
    final id = ref.key;
    if (id == null) {
      throw StateError('RTDB push() returned no key');
    }
    await ref.set({
      'authorId': authorId,
      'authorName': authorName,
      'text': trimmed,
      'createdAtMs': createdAtMs,
    });
    return RideChatMessage(
      id: id,
      authorId: authorId,
      authorName: authorName,
      text: trimmed,
      createdAtMs: createdAtMs,
    );
  }

  RideChatMessage? _tryParse(Object? key, Object? value) {
    if (key is! String || value is! Map) return null;
    final authorId = value['authorId'];
    final text = value['text'];
    final createdAtMs = value['createdAtMs'];
    if (authorId is! String ||
        text is! String ||
        createdAtMs is! int ||
        key.isEmpty ||
        authorId.isEmpty) {
      _logger.warning(
        'ride_chat_malformed_skipped',
        metadata: const {'reason': 'missing_fields'},
      );
      return null;
    }
    final authorName = value['authorName'];
    return RideChatMessage(
      id: key,
      authorId: authorId,
      authorName: authorName is String && authorName.isNotEmpty
          ? authorName
          : 'Unknown',
      text: text,
      createdAtMs: createdAtMs,
    );
  }
}
