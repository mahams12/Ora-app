import '../models/ride_chat_message.dart';

/// Read/write port for ride-scoped passenger↔driver chat.
///
/// Implementations must scope data to a single ride and soft-fail on
/// permission/network errors — the chat screen never crashes the ride flow.
abstract class RideChatPort {
  /// Emits the full ordered message list (oldest → newest) on every change.
  Stream<List<RideChatMessage>> watchMessages(String rideId);

  /// Persists one text message under the given ride and returns it with
  /// the backend-assigned id. Throws on hard failure; caller decides UX.
  Future<RideChatMessage> sendMessage(
    String rideId, {
    required String authorId,
    required String authorName,
    required String text,
  });
}
