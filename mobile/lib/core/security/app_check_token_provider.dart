/// Optional App Check token source for API requests.
///
/// Never log returned token values.
abstract class AppCheckTokenProvider {
  Future<String?> getToken({bool forceRefresh = false});
}

/// No-op provider used when App Check is disabled (local Phase 2A/2B default).
class NoAppCheckTokenProvider implements AppCheckTokenProvider {
  const NoAppCheckTokenProvider();

  @override
  Future<String?> getToken({bool forceRefresh = false}) async => null;
}
