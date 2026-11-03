import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../domain/models/ride_chat_message.dart';
import '../domain/ports/ride_chat_port.dart';

/// [ChatController] backed by `rideChats/{rideId}` in RTDB.
///
/// Remote snapshots are authoritative: each emission maps to a
/// `ChatOperation.set`. Sends are plain RTDB writes that echo back
/// through the same watch stream, so both sides stay in sync.
class RtdbChatController implements ChatController {
  RtdbChatController({
    required String rideId,
    required RideChatPort port,
    required AppLogger logger,
  })  : _rideId = rideId,
        _port = port,
        _logger = logger;

  final String _rideId;
  final RideChatPort _port;
  final AppLogger _logger;

  final _operationsController = StreamController<ChatOperation>.broadcast();
  StreamSubscription<List<RideChatMessage>>? _sub;
  List<Message> _messages = const [];
  var _started = false;
  var _disposed = false;

  /// Starts the RTDB watch. Idempotent — safe to call from initState.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _sub = _port.watchMessages(_rideId).listen(_onSnapshot);
  }

  /// Sends a text message; the RTDB echo updates the list via [_onSnapshot].
  Future<void> sendText({
    required String authorId,
    required String authorName,
    required String text,
  }) =>
      _port.sendMessage(
        _rideId,
        authorId: authorId,
        authorName: authorName,
        text: text,
      );

  void _onSnapshot(List<RideChatMessage> snapshot) {
    final mapped = snapshot.map(_toMessage).toList(growable: false);
    if (_sameList(_messages, mapped)) return;
    _messages = mapped;
    if (!_operationsController.isClosed) {
      _operationsController.add(ChatOperation.set(mapped));
    }
  }

  bool _sameList(List<Message> a, List<Message> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  Message _toMessage(RideChatMessage m) => TextMessage(
        id: m.id,
        authorId: m.authorId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          m.createdAtMs,
          isUtc: true,
        ),
        sentAt: DateTime.fromMillisecondsSinceEpoch(
          m.createdAtMs,
          isUtc: true,
        ),
        text: m.text,
        metadata: {'authorName': m.authorName},
      );

  // ── ChatController contract ───────────────────────────────────────────────
  // Local mutations mirror into _messages and emit the matching operation;
  // remote writes always arrive via the snapshot stream.

  @override
  List<Message> get messages => List.unmodifiable(_messages);

  @override
  Stream<ChatOperation> get operationsStream => _operationsController.stream;

  @override
  Future<void> insertMessage(Message message, {int? index}) async {
    if (_messages.any((m) => m.id == message.id)) return;
    final at = (index ?? _messages.length).clamp(0, _messages.length);
    _messages = List.of(_messages)..insert(at, message);
    _emit(ChatOperation.insert(message, at));
  }

  @override
  Future<void> insertAllMessages(List<Message> messages, {int? index}) async {
    if (messages.isEmpty) return;
    final at = (index ?? _messages.length).clamp(0, _messages.length);
    _messages = List.of(_messages)..insertAll(at, messages);
    _emit(ChatOperation.insertAll(messages, at));
  }

  @override
  Future<void> updateMessage(Message oldMessage, Message newMessage) async {
    final index = _messages.indexWhere((m) => m.id == oldMessage.id);
    if (index < 0) return;
    final current = _messages[index];
    _messages = List.of(_messages)..[index] = newMessage;
    _emit(ChatOperation.update(current, newMessage, index));
  }

  @override
  Future<void> removeMessage(Message message) async {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final current = _messages[index];
    _messages = List.of(_messages)..removeAt(index);
    _emit(ChatOperation.remove(current, index));
  }

  @override
  Future<void> setMessages(List<Message> messages) async {
    _messages = List.of(messages);
    _emit(ChatOperation.set(_messages));
  }

  void _emit(ChatOperation operation) {
    if (_disposed || _operationsController.isClosed) return;
    _operationsController.add(operation);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_sub?.cancel());
    unawaited(_operationsController.close());
    _logger.debug('ride_chat_controller_disposed');
  }
}

/// Per-ride controller — autoDisposed with the chat view.
final rideChatControllerProvider =
    Provider.autoDispose.family<RtdbChatController, String>(
  (ref, rideId) {
    final controller = RtdbChatController(
      rideId: rideId,
      port: ref.watch(rideChatPortProvider),
      logger: ref.watch(appLoggerProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
);
