import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Lightweight PoC timing sink — no invented FPS.
class MapLibrePoCMetrics {
  MapLibrePoCMetrics() : screenOpenAt = DateTime.now();

  final DateTime screenOpenAt;
  DateTime? mapCreatedAt;
  DateTime? styleLoadedAt;
  DateTime? firstIdleAt;
  DateTime? overlaysReadyAt;
  DateTime? showcaseAnimDoneAt;
  int cameraIdleCount = 0;
  int openCloseCycle = 0;
  String? lastError;
  final List<String> events = <String>[];

  void mark(String event) {
    final ms = DateTime.now().difference(screenOpenAt).inMilliseconds;
    events.add('$ms ms — $event');
    debugPrint('MAPLIBRE_POC_METRIC $ms $event');
  }

  void onMapCreated() {
    mapCreatedAt = DateTime.now();
    mark('map_initialized');
  }

  void onStyleLoaded() {
    styleLoadedAt = DateTime.now();
    mark('style_loaded');
  }

  void onMapIdle() {
    firstIdleAt ??= DateTime.now();
    if (firstIdleAt != null &&
        events.every((e) => !e.contains('first_map_idle'))) {
      mark('first_map_idle');
    }
  }

  void onCameraIdle() {
    cameraIdleCount += 1;
  }

  void onOverlaysReady() {
    overlaysReadyAt = DateTime.now();
    mark('overlays_ready');
  }

  void onShowcaseDone() {
    showcaseAnimDoneAt = DateTime.now();
    mark('showcase_camera_done');
  }

  void error(String message) {
    lastError = message;
    mark('error:$message');
  }

  int? get msOpenToMapCreated => mapCreatedAt == null
      ? null
      : mapCreatedAt!.difference(screenOpenAt).inMilliseconds;

  int? get msCreatedToStyle =>
      (mapCreatedAt == null || styleLoadedAt == null)
          ? null
          : styleLoadedAt!.difference(mapCreatedAt!).inMilliseconds;

  int? get msOpenToFirstIdle => firstIdleAt == null
      ? null
      : firstIdleAt!.difference(screenOpenAt).inMilliseconds;

  int? get msOpenToOverlays => overlaysReadyAt == null
      ? null
      : overlaysReadyAt!.difference(screenOpenAt).inMilliseconds;

  Map<String, Object?> toJson() => {
        'screenOpenAt': screenOpenAt.toIso8601String(),
        'msOpenToMapCreated': msOpenToMapCreated,
        'msCreatedToStyleLoaded': msCreatedToStyle,
        'msOpenToFirstMapIdle': msOpenToFirstIdle,
        'msOpenToOverlaysReady': msOpenToOverlays,
        'cameraIdleCount': cameraIdleCount,
        'openCloseCycle': openCloseCycle,
        'fps': 'NOT_MEASURED',
        'memoryMb': 'NOT_MEASURED',
        'lastError': lastError,
        'events': List<String>.from(events),
      };

  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
