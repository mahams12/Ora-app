import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'app/config/environment.dart';
import 'core/security/firebase_app_check_bootstrap.dart';

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

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  try {
    await Firebase.initializeApp();
    // Debug/emulator only: skip Play Integrity / reCAPTCHA so Firebase
    // Console test phone numbers work without Chrome. Never in release.
    if (kDebugMode) {
      await FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
    }

    final env = environmentFromString(
      const String.fromEnvironment('ORA_ENV', defaultValue: 'development'),
    );
    final config = AppConfig.fromEnvironment(env);
    if (config.appCheckEnabled) {
      await activateOraAppCheck(
        useDebugProvider: shouldUseAppCheckDebugProvider(),
      );
    }
  } catch (_) {
    runApp(const _FirebaseInitFailedApp());
    return;
  }

  runApp(
    const ProviderScope(
      child: OraApp(),
    ),
  );
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
