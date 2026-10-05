import 'dart:developer' as developer;

import 'log_level.dart';
import 'log_record.dart';

abstract class AppLogger {
  void log(LogRecord record);

  void debug(String message, {Map<String, Object?>? metadata}) {
    log(
      LogRecord(
        level: LogLevel.debug,
        message: message,
        timestamp: DateTime.now().toUtc(),
        metadata: metadata,
      ),
    );
  }

  void info(String message, {Map<String, Object?>? metadata}) {
    log(
      LogRecord(
        level: LogLevel.info,
        message: message,
        timestamp: DateTime.now().toUtc(),
        metadata: metadata,
      ),
    );
  }

  void warning(String message, {Map<String, Object?>? metadata}) {
    log(
      LogRecord(
        level: LogLevel.warning,
        message: message,
        timestamp: DateTime.now().toUtc(),
        metadata: metadata,
      ),
    );
  }

  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    log(
      LogRecord(
        level: LogLevel.error,
        message: message,
        timestamp: DateTime.now().toUtc(),
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      ),
    );
  }

  void fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? metadata,
  }) {
    log(
      LogRecord(
        level: LogLevel.fatal,
        message: message,
        timestamp: DateTime.now().toUtc(),
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      ),
    );
  }
}

/// Default development logger.
///
/// Sink: [developer.log] with name `ora` (DevTools / VM service).
/// Debug-only: also [print]s the same line so `adb logcat` / `flutter logs`
/// can observe diagnostics (e.g. `location_watch_*`) on a physical device.
/// Release/profile builds keep developer.log only — no extra stdout mirror.
class ConsoleAppLogger extends AppLogger {
  ConsoleAppLogger({this.minimumLevel = LogLevel.debug});

  final LogLevel minimumLevel;

  @override
  void log(LogRecord record) {
    if (record.level.index < minimumLevel.index) {
      return;
    }

    final buffer = StringBuffer('[${record.level.name.toUpperCase()}] ');
    if (record.requestId != null) {
      buffer.write('req=${record.requestId} ');
    }
    if (record.operationId != null) {
      buffer.write('op=${record.operationId} ');
    }
    buffer.write(record.message);
    if (record.metadata != null && record.metadata!.isNotEmpty) {
      // Never log Authorization / App Check / raw tokens — callers must not
      // put those in metadata.
      buffer.write(' ');
      buffer.write(record.metadata);
    }

    final line = buffer.toString();
    developer.log(
      line,
      time: record.timestamp,
      error: record.error,
      stackTrace: record.stackTrace,
      name: 'ora',
    );

    // Debug-only adb/flutter logs mirror for device QA (assert strips in release).
    assert(() {
      // ignore: avoid_print
      print(line);
      return true;
    }());
  }
}
