import '../../../../core/logging/app_logger.dart';

/// Safe auth-bootstrap timeline markers (never log tokens or secrets).
class AuthBootstrapDiagnostics {
  AuthBootstrapDiagnostics(this._logger);

  final AppLogger _logger;
  int? _originMs;

  void resetOrigin() {
    _originMs = DateTime.now().millisecondsSinceEpoch;
  }

  int get elapsedMs {
    final origin = _originMs;
    if (origin == null) return 0;
    return DateTime.now().millisecondsSinceEpoch - origin;
  }

  void mark(String event, {Map<String, Object?> extra = const {}}) {
    _logger.info(
      event,
      metadata: {
        'marker': event,
        'elapsedMs': elapsedMs,
        ...extra,
      },
    );
  }

  void markFailure(
    String event, {
    required String classification,
    int? httpStatus,
  }) {
    mark(
      event,
      extra: {
        'classification': classification,
        if (httpStatus != null) 'httpStatus': httpStatus,
      },
    );
  }
}
