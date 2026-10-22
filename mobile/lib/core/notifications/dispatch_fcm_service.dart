import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../features/driver/data/driver_device_token_remote_data_source.dart';
import '../../features/driver/presentation/view_models/driver_invites_view_model.dart';
import '../../features/driver/presentation/view_models/driver_open_rides_view_model.dart';
import '../network/api_client.dart';
import 'dispatch_fcm_local_notifications.dart';
import 'dispatch_invite_message.dart';
import 'ride_fcm_nudge.dart';

/// D1 client: register FCM token, show dispatch invites, navigate on tap.
class DispatchFcmService {
  DispatchFcmService({
    required DriverDeviceTokenRemoteDataSource tokenApi,
    required ApiClient apiClient,
  })  : _tokenApi = tokenApi,
        _apiClient = apiClient;

  final DriverDeviceTokenRemoteDataSource _tokenApi;
  final ApiClient _apiClient;

  final _seenEventIds = <String>{};
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _lastRegisteredToken;
  // Which registration path the last successful token sync used, so token
  // refreshes re-register on the correct (role-gated) endpoint.
  bool _lastRegistrationWasPassenger = false;

  /// NOTIF-RIDE-NUDGE: ride-state messages (non-invite, carries rideId).
  /// Consumers treat these as "poll now" hints — payloads are never state.
  final _rideNudgeController = StreamController<RideFcmNudge>.broadcast();
  Stream<RideFcmNudge> get rideNudges => _rideNudgeController.stream;

  Future<void> init({
    required GoRouter router,
    required WidgetRef ref,
  }) async {
    await DispatchFcmLocalNotifications.ensureInitialized(
      onNotificationTap: (payload) {
        _navigateToOpenRides(router, ref, eventId: payload);
      },
    );

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    _foregroundSub ??=
        FirebaseMessaging.onMessage.listen((message) async {
      await _handleMessage(message, router: router, ref: ref, fromTap: false);
    });

    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(
        _handleMessage(message, router: router, ref: ref, fromTap: true),
      );
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      await _handleMessage(initial, router: router, ref: ref, fromTap: true);
    }

    messaging.onTokenRefresh.listen((token) {
      unawaited(
        _lastRegistrationWasPassenger
            ? _registerPassengerToken(token)
            : _registerToken(token),
      );
    });
  }

  /// Messaging instance, or null when Firebase isn't initialized (tests,
  /// degraded startup). Token sync is best-effort — invites still arrive via
  /// the invited-rides HTTP listing, so a missing instance must never crash.
  FirebaseMessaging? get _messagingOrNull {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncDriverTokenRegistration() async {
    final token = await _messagingOrNull?.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _registerToken(token);
  }

  /// NOTIF-RS-PUSH — passenger token sync; hits the role-gated
  /// /device-tokens route so ride-state nudges can reach passengers.
  Future<void> syncPassengerTokenRegistration() async {
    final token = await _messagingOrNull?.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _registerPassengerToken(token);
  }

  Future<void> clearRegisteredToken() async {
    final token = _lastRegisteredToken ??
        await _messagingOrNull?.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      if (_lastRegistrationWasPassenger) {
        await _tokenApi.clearPassengerToken(
          token: token,
          context: _apiClient.newContext(),
        );
      } else {
        await _tokenApi.clearToken(
          token: token,
          context: _apiClient.newContext(),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[D1_FCM] clear token failed: ${e.runtimeType}');
      }
    }
    _lastRegisteredToken = null;
  }

  Future<void> _registerToken(String token) async {
    if (token == _lastRegisteredToken && !_lastRegistrationWasPassenger) {
      return;
    }
    await _tokenApi.registerToken(
      token: token,
      context: _apiClient.newContext(),
    );
    _lastRegisteredToken = token;
    _lastRegistrationWasPassenger = false;
    if (kDebugMode) {
      debugPrint('[D1_FCM] device token registered (hash only in server logs)');
    }
  }

  Future<void> _registerPassengerToken(String token) async {
    if (token == _lastRegisteredToken && _lastRegistrationWasPassenger) {
      return;
    }
    await _tokenApi.registerPassengerToken(
      token: token,
      context: _apiClient.newContext(),
    );
    _lastRegisteredToken = token;
    _lastRegistrationWasPassenger = true;
    if (kDebugMode) {
      debugPrint('[RS_FCM] passenger device token registered');
    }
  }

  Future<void> _handleMessage(
    RemoteMessage message, {
    required GoRouter router,
    required WidgetRef ref,
    required bool fromTap,
  }) async {
    final invite = DispatchInviteMessage.tryParse(message.data);
    if (invite == null) {
      _emitRideNudge(message);
      return;
    }
    if (!_markEventSeen(invite.eventId)) {
      return;
    }
    if (fromTap) {
      _navigateToOpenRides(router, ref, eventId: invite.eventId);
      return;
    }
    await DispatchFcmLocalNotifications.showDispatchInvite(
      invite: invite,
      payload: invite.eventId,
    );
    _refreshOpenRides(ref);
  }

  /// Emit a ride nudge for non-invite messages carrying a rideId.
  /// Dedupes by eventId when the backend provides one; id-less nudges pass
  /// through (consumer-side debounce absorbs duplicates).
  void _emitRideNudge(RemoteMessage message) {
    if (_rideNudgeController.isClosed) return;
    final nudge = RideFcmNudge.tryParse(message);
    if (nudge == null) return;
    final eventId = nudge.eventId;
    if (eventId != null && !_markEventSeen(eventId)) {
      return;
    }
    _rideNudgeController.add(nudge);
  }

  bool _markEventSeen(String eventId) {
    if (_seenEventIds.contains(eventId)) {
      return false;
    }
    _seenEventIds.add(eventId);
    if (_seenEventIds.length > 200) {
      _seenEventIds.remove(_seenEventIds.first);
    }
    return true;
  }

  void _navigateToOpenRides(
    GoRouter router,
    WidgetRef ref, {
    required String eventId,
  }) {
    _markEventSeen(eventId);
    router.go(AppRoutes.driverOpen);
    _refreshOpenRides(ref);
  }

  void _refreshOpenRides(WidgetRef ref) {
    unawaited(
      ref.read(driverOpenRidesViewModelProvider.notifier).refresh(),
    );
    // Dispatch invites arrive via the same nudge — resync the authoritative
    // invite feed so countdown cards appear even if the app was restarted.
    unawaited(
      ref.read(driverInvitesViewModelProvider.notifier).refresh(),
    );
  }

  void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    _foregroundSub = null;
    _openedSub = null;
    unawaited(_rideNudgeController.close());
  }
}
