import 'package:flutter/foundation.dart';

import 'api_base_url_guard.dart';
import 'environment.dart';

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.appCheckEnabled,
    required this.clientVersion,
  });

  factory AppConfig.development() => const AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: 'https://api-dev.ora.app/v1',
        appCheckEnabled: false,
        clientVersion: '1.0.0',
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

    return AppConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      appCheckEnabled: appCheckEnabled,
      clientVersion: '1.0.0',
    );
  }

  final AppEnvironment environment;
  final String apiBaseUrl;
  final bool appCheckEnabled;
  final String clientVersion;
}
