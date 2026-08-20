import 'environment.dart';

/// Resolves and validates the API base URL for the active environment.
///
/// - Development: `http://` allowed (emulator → host).
/// - Staging: HTTPS required unless [allowInsecureHttp] is explicitly true.
/// - Production / release: HTTPS **always** required.
///
/// Throws [ArgumentError] when the URL is unsafe for the environment.
String resolveApiBaseUrl({
  required AppEnvironment environment,
  required String apiBaseUrl,
  bool isReleaseMode = false,
  bool allowInsecureHttp = false,
}) {
  final trimmed = apiBaseUrl.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('API base URL must not be empty.');
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError('API base URL is not a valid absolute URL.');
  }

  final requiresHttps = environment.isProduction ||
      isReleaseMode ||
      (environment == AppEnvironment.staging && !allowInsecureHttp);

  if (requiresHttps && uri.scheme.toLowerCase() != 'https') {
    throw ArgumentError(
      'HTTPS is required for ${environment.name} API URLs '
      '(refusing ${uri.scheme}://).',
    );
  }

  if (uri.scheme.toLowerCase() != 'http' &&
      uri.scheme.toLowerCase() != 'https') {
    throw ArgumentError('API base URL must use http or https.');
  }

  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}
