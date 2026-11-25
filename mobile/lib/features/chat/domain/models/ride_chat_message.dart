/// One text message in a ride-scoped chat between passenger and driver.
///
/// Stored in RTDB at `rideChats/{rideId}/messages/{messageId}`. Plain class —
/// serialization lives in the data source, not here.
class RideChatMessage {
  const RideChatMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.createdAtMs,
  });

  /// RTDB push key — globally unique, time-ordered.
  final String id;

  /// Firebase Auth uid of the sender.
  final String authorId;

  /// Display name snapshot at send time (names change; messages should not).
  final String authorName;

  final String text;

  /// Epoch milliseconds — ordering field for `orderByChild`.
  final int createdAtMs;
}
