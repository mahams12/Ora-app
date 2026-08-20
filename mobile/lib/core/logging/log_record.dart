import 'log_level.dart';

class LogRecord {
  const LogRecord({
    required this.level,
    required this.message,
    required this.timestamp,
    this.requestId,
    this.operationId,
    this.userId,
    this.rideId,
    this.error,
    this.stackTrace,
    this.metadata,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String? requestId;
  final String? operationId;
  final String? userId;
  final String? rideId;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?>? metadata;
}
