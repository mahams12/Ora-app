import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'dispatch_fcm_constants.dart';
import 'dispatch_invite_message.dart';

/// Shows user-visible notifications for data-only D1 dispatch messages.
class DispatchFcmLocalNotifications {
  DispatchFcmLocalNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static Future<void> ensureInitialized({
    void Function(String payload)? onNotificationTap,
  }) async {
    if (_initialized) {
      return;
    }
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onNotificationTap?.call(payload);
        }
      },
    );
    final android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        DispatchFcmConstants.notificationChannelId,
        DispatchFcmConstants.notificationChannelName,
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  static Future<void> showDispatchInvite({
    required DispatchInviteMessage invite,
    required String payload,
  }) async {
    await ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        DispatchFcmConstants.notificationChannelId,
        DispatchFcmConstants.notificationChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      invite.eventId.hashCode,
      'New ride request',
      'Open Ora to view available rides near you.',
      details,
      payload: payload,
    );
    if (kDebugMode) {
      debugPrint(
        '[D1_FCM] local notification eventId=${invite.eventId} '
        'rideId=${invite.rideId}',
      );
    }
  }
}
