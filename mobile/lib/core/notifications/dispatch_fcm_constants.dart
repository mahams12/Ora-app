/// D1 data-only FCM contract (must match auth-service `D1_FCM_TYPE`).
class DispatchFcmConstants {
  DispatchFcmConstants._();

  static const messageType = 'DISPATCH_INVITE';
  static const dataKeyType = 'type';
  static const dataKeyRideId = 'rideId';
  static const dataKeyWaveNumber = 'waveNumber';
  static const dataKeyEventId = 'eventId';

  static const notificationChannelId = 'ora_dispatch_invite';
  static const notificationChannelName = 'Ride requests';
}
