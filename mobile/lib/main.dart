import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/config/environment.dart';
import 'core/notifications/dispatch_fcm_background.dart';
import 'core/security/firebase_app_check_bootstrap.dart';

void _startupMark(String name) {
  if (kDebugMode) {
    debugPrint('[STARTUP] $name ${DateTime.now().toUtc().toIso8601String()}');
  }
}

void _scheduleFirstFrameMark() {
  if (!kDebugMode) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _startupMark('first_frame');
  });
}

/// Entrypoint.
///
/// [Firebase.initializeApp] must complete before any Firebase service is
/// accessed. Initialization happens exactly once here — never from Views or
/// feature screens.
///
/// Failures are caught and shown as a non-technical recovery screen. Raw
/// Firebase exceptions are never shown to the user.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _startupMark('main_enter');

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    _startupMark('firebase_init_begin');
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _startupMark('firebase_init_done');
    // Debug/emulator only: skip Play Integrity / reCAPTCHA so Firebase
    // Console test phone numbers work without Chrome. Never in release.
    if (kDebugMode) {
      _startupMark('firebase_auth_settings_begin');
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
      _startupMark('firebase_auth_settings_done');
    }

    final env = environmentFromString(
      const String.fromEnvironment('ORA_ENV', defaultValue: 'development'),
    );
    final config = AppConfig.fromEnvironment(env);
    // Debug-only: prove which API the physical device build is targeting.
    // Never log tokens or credentials.
    if (kDebugMode) {
      debugPrint('ORA API BASE URL = ${config.apiBaseUrl}');
    }
    if (config.appCheckEnabled) {
      _startupMark('app_check_begin');
      await activateOraAppCheck(
        useDebugProvider: shouldUseAppCheckDebugProvider(),
      );
      _startupMark('app_check_done');
    }
  } catch (_) {
    _startupMark('run_app_begin');
    runApp(const _FirebaseInitFailedApp());
    _scheduleFirstFrameMark();
    return;
  }

  _startupMark('run_app_begin');
  runApp(
    const ProviderScope(
      child: OraApp(),
    ),
  );
  _scheduleFirstFrameMark();
}

/// Shown when native Firebase config is missing or invalid.
///
/// Keeps the process alive so the user sees a recoverable message instead of
/// a crash dump. No Firebase APIs are touched from this tree.
class _FirebaseInitFailedApp extends StatelessWidget {
  const _FirebaseInitFailedApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Ora could not start securely.\n\n'
                'Please reinstall the app or contact support if this continues.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
