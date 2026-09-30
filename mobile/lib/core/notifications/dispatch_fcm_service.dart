import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/routes.dart';
import '../../features/driver/data/driver_device_token_remote_data_source.dart';
import '../../features/driver/presentation/view_models/driver_open_rides_view_model.dart';
import '../network/api_client.dart';
import 'dispatch_fcm_local_notifications.dart';
import 'dispatch_invite_message.dart';

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
      unawaited(_registerToken(token));
    });
  }

  Future<void> syncDriverTokenRegistration() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _registerToken(token);
  }

  Future<void> clearRegisteredToken() async {
    final token = _lastRegisteredToken ??
        await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    try {
      await _tokenApi.clearToken(
        token: token,
        context: _apiClient.newContext(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[D1_FCM] clear token failed: ${e.runtimeType}');
      }
    }
    _lastRegisteredToken = null;
  }

  Future<void> _registerToken(String token) async {
    if (token == _lastRegisteredToken) {
      return;
    }
    await _tokenApi.registerToken(
      token: token,
      context: _apiClient.newContext(),
    );
    _lastRegisteredToken = token;
    if (kDebugMode) {
      debugPrint('[D1_FCM] device token registered (hash only in server logs)');
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
  }

  void dispose() {
    unawaited(_foregroundSub?.cancel());
    unawaited(_openedSub?.cancel());
    _foregroundSub = null;
    _openedSub = null;
  }
}
