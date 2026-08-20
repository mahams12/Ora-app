enum AppEnvironment {
  development,
  staging,
  production;

  bool get isProduction => this == AppEnvironment.production;
  bool get isDevelopment => this == AppEnvironment.development;

  String get apiBaseUrl => switch (this) {
        AppEnvironment.development => 'https://api-dev.ora.app/v1',
        AppEnvironment.staging => 'https://api-staging.ora.app/v1',
        AppEnvironment.production => 'https://api.ora.app/v1',
      };

  String get displayName => switch (this) {
        AppEnvironment.development => 'Development',
        AppEnvironment.staging => 'Staging',
        AppEnvironment.production => 'Production',
      };
}

AppEnvironment environmentFromString(String value) {
  return switch (value.toLowerCase()) {
    'staging' => AppEnvironment.staging,
    'production' => AppEnvironment.production,
    _ => AppEnvironment.development,
  };
}
