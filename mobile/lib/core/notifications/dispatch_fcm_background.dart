import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dispatch_fcm_local_notifications.dart';
import 'dispatch_invite_message.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await DispatchFcmLocalNotifications.ensureInitialized();
  final invite = DispatchInviteMessage.tryParse(message.data);
  if (invite == null) {
    return;
  }
  await DispatchFcmLocalNotifications.showDispatchInvite(
    invite: invite,
    payload: invite.eventId,
  );
}
