import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import 'app_check_token_provider.dart';

/// Activates Firebase App Check for the current process.
///
/// - Debug builds: Debug provider only (never ship in release).
/// - Release/profile: Play Integrity (Android) / App Attest (iOS).
///
/// Call only when [AppConfig.appCheckEnabled] is true. Do not enable Firebase
/// Console "Enforce" until clients send valid tokens in staging.
Future<void> activateOraAppCheck({required bool useDebugProvider}) async {
  await FirebaseAppCheck.instance.activate(
    providerAndroid: useDebugProvider
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: useDebugProvider
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
}

/// Token provider backed by Firebase App Check. Never log tokens.
class FirebaseAppCheckTokenProvider implements AppCheckTokenProvider {
  FirebaseAppCheckTokenProvider({FirebaseAppCheck? appCheck})
      : _appCheck = appCheck ?? FirebaseAppCheck.instance;

  final FirebaseAppCheck _appCheck;

  @override
  Future<String?> getToken({bool forceRefresh = false}) async {
    try {
      return await _appCheck.getToken(forceRefresh);
    } catch (_) {
      // Fail soft at the provider — API will 401 APP_CHECK_REQUIRED when
      // the backend enforces App Check.
      return null;
    }
  }
}

/// Whether this process should use the debug App Check provider.
///
/// Debug provider must never be compiled into release attestation paths.
bool shouldUseAppCheckDebugProvider() => kDebugMode;
