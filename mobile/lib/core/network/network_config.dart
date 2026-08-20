import '../../app/config/environment.dart';

class NetworkConfig {
  const NetworkConfig({
    required this.baseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.sendTimeout,
    required this.enableRequestLogging,
  });

  factory NetworkConfig.fromEnvironment(AppEnvironment environment) {
    return NetworkConfig(
      baseUrl: environment.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      enableRequestLogging: !environment.isProduction,
    );
  }

  final String baseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
  final bool enableRequestLogging;
}
