import 'package:flutter/foundation.dart';

import 'api_base_url_guard.dart';
import 'environment.dart';

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.appCheckEnabled,
    required this.clientVersion,
    this.googlePlacesApiKey = '',
  });

  factory AppConfig.development() => const AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: 'https://api-dev.ora.app/v1',
        appCheckEnabled: false,
        clientVersion: '1.0.0',
        googlePlacesApiKey: '',
      );

  factory AppConfig.fromEnvironment(AppEnvironment environment) {
    // Optional override for local auth-service / staging tunnels.
    // Example: --dart-define=ORA_API_BASE_URL=http://10.0.2.2:8080/v1
    const override = String.fromEnvironment('ORA_API_BASE_URL');
    // Staging-only escape hatch for local HTTPS-less tunnels.
    const allowHttp = bool.fromEnvironment(
      'ORA_ALLOW_HTTP_API',
      defaultValue: false,
    );
    // Force App Check on/off regardless of environment defaults.
    const appCheckDefine = String.fromEnvironment(
      'ORA_APP_CHECK',
      defaultValue: '',
    );

    final rawBase = override.isEmpty ? environment.apiBaseUrl : override;
    final apiBaseUrl = resolveApiBaseUrl(
      environment: environment,
      apiBaseUrl: rawBase,
      isReleaseMode: kReleaseMode,
      allowInsecureHttp: allowHttp,
    );

    final appCheckEnabled = switch (appCheckDefine) {
      'true' => true,
      'false' => false,
      _ => !environment.isDevelopment,
    };

    // Fail-closed: production/release must never ship with App Check disabled.
    if (kReleaseMode &&
        environment.isProduction &&
        !appCheckEnabled) {
      throw StateError(
        'REFUSING_START: production release requires App Check '
        '(unset ORA_APP_CHECK=false).',
      );
    }

    // Fail-closed: release builds must never use HTTP API endpoints.
    // (resolveApiBaseUrl already throws; this documents the invariant.)
    if (kReleaseMode && apiBaseUrl.startsWith('http://')) {
      throw StateError(
        'REFUSING_START: release builds require HTTPS API base URL.',
      );
    }

    const placesKey = String.fromEnvironment(
      'ORA_GOOGLE_PLACES_API_KEY',
      defaultValue: '',
    );

    return AppConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      appCheckEnabled: appCheckEnabled,
      clientVersion: '1.0.0',
      googlePlacesApiKey: placesKey,
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool appCheckEnabled;
  final String clientVersion;

  /// Places API (New) key for passenger autocomplete/details (Phase 4A).
  /// Never put Routes/server keys here.
  final String googlePlacesApiKey;

  bool get hasGooglePlacesApiKey => googlePlacesApiKey.trim().isNotEmpty;
}
