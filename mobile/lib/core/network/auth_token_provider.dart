import 'dart:async';

/// Supplies bearer tokens for authenticated API calls.
abstract interface class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// Phase 1 placeholder — no auth yet.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;
}

/// Production implementation that reads the current Firebase ID token.
///
/// Single-flight: if a refresh is already in progress when a second caller
/// asks for a token, the second caller awaits the same [Future] instead of
/// issuing a redundant refresh request — preventing concurrent 401-induced
/// refresh storms.
class FirebaseAuthTokenProvider implements AuthTokenProvider {
  FirebaseAuthTokenProvider({required Future<String?> Function(bool) getIdToken})
      : _getIdToken = getIdToken;

  final Future<String?> Function(bool forceRefresh) _getIdToken;

  // Single-flight refresh guard.
  Future<String?>? _refreshFuture;

  @override
  Future<String?> getAccessToken() async {
    // If a refresh is already in flight, join it instead of issuing another.
    if (_refreshFuture != null) {
      return _refreshFuture;
    }
    // Normal path: get token, let Firebase SDK handle its own cache.
    return _getIdToken(false);
  }

  /// Called by the 401-interceptor to force a single refresh attempt.
  ///
  /// All callers that arrive while the refresh is in progress receive the
  /// same [Future].  After completion the flight is cleared so future calls
  /// get fresh tokens normally.
  Future<String?> forceRefresh() {
    _refreshFuture ??= _getIdToken(true).whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }
}
