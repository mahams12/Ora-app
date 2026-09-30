import 'dispatch_fcm_constants.dart';

/// Parsed D1 dispatch invite (data-only FCM).
class DispatchInviteMessage {
  const DispatchInviteMessage({
    required this.rideId,
    required this.eventId,
    this.waveNumber,
  });

  final String rideId;
  final String eventId;
  final String? waveNumber;

  static DispatchInviteMessage? tryParse(Map<String, dynamic> data) {
    final type = data[DispatchFcmConstants.dataKeyType];
    if (type != DispatchFcmConstants.messageType) {
      return null;
    }
    final rideId = data[DispatchFcmConstants.dataKeyRideId];
    final eventId = data[DispatchFcmConstants.dataKeyEventId];
    if (rideId is! String ||
        rideId.isEmpty ||
        eventId is! String ||
        eventId.isEmpty) {
      return null;
    }
    final wave = data[DispatchFcmConstants.dataKeyWaveNumber];
    return DispatchInviteMessage(
      rideId: rideId,
      eventId: eventId,
      waveNumber: wave is String ? wave : null,
    );
  }
}
