import 'package:firebase_messaging/firebase_messaging.dart';

/// A ride-state FCM "nudge" (NOTIF-RIDE-NUDGE).
///
/// Push payloads are never authoritative ride state — they only signal that an
/// immediate HTTP poll is worthwhile. Parsing is deliberately lenient: any
/// message carrying a non-empty `data['rideId']` that isn't a dispatch invite
/// yields a nudge; unknown/extra fields are ignored.
class RideFcmNudge {
  const RideFcmNudge({
    required this.rideId,
    this.eventId,
    this.type,
  });

  final String rideId;

  /// Backend event id when present — used for deduplication.
  final String? eventId;

  /// Backend message `type` when present (e.g. `ride_update`) — diagnostic only.
  final String? type;

  /// Returns null when the message carries no usable ride id.
  static RideFcmNudge? tryParse(RemoteMessage message) {
    final data = message.data;
    final rawRideId = data['rideId'] ?? data['ride_id'];
    final rideId = rawRideId?.toString().trim() ?? '';
    if (rideId.isEmpty) return null;
    final rawEventId = data['eventId'] ??
        data['event_id'] ??
        data['deliveryEventId'] ??
        data['delivery_event_id'];
    final eventId = rawEventId?.toString().trim();
    final rawType = data['type'];
    final type = rawType?.toString().trim();
    return RideFcmNudge(
      rideId: rideId,
      eventId: (eventId == null || eventId.isEmpty) ? null : eventId,
      type: (type == null || type.isEmpty) ? null : type,
    );
  }
}
