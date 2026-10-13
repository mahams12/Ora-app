import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_preview_config.dart';

/// Result of preparing the Ora dark MapLibre style for the ride preview.
class MapPreviewStyleLoadResult {
  const MapPreviewStyleLoadResult._({
    this.styleJson,
    this.errorMessage,
  });

  const MapPreviewStyleLoadResult.ok(String styleJson)
      : this._(styleJson: styleJson);

  const MapPreviewStyleLoadResult.fail(String errorMessage)
      : this._(errorMessage: errorMessage);

  final String? styleJson;
  final String? errorMessage;

  bool get isOk => styleJson != null && styleJson!.isNotEmpty;
}

/// Loads Ora dark style + injects MapTiler key; preflights tile access.
///
/// Soft-fails with a user-safe message — never throws secrets or gates rides.
class MapPreviewStyleLoader {
  MapPreviewStyleLoader._();

  static Future<MapPreviewStyleLoadResult> load() async {
    if (!MapPreviewConfig.hasTileKey) {
      return const MapPreviewStyleLoadResult.fail(
        'Map preview unavailable · tile key not configured',
      );
    }

    final apiKey = MapPreviewConfig.mapTilerApiKey;
    try {
      await setHttpHeaders({
        HttpHeaders.userAgentHeader: MapPreviewConfig.mapTilerUserAgent,
      });

      final preflight = await _preflightMapTiler(apiKey);
      if (!preflight.ok) {
        return MapPreviewStyleLoadResult.fail(preflight.message);
      }

      final raw =
          await rootBundle.loadString(MapPreviewConfig.styleAssetPath);
      final injected = raw.replaceAll(
        MapPreviewConfig.styleKeyPlaceholder,
        apiKey,
      );
      jsonDecode(injected);
      return MapPreviewStyleLoadResult.ok(injected);
    } catch (_) {
      return const MapPreviewStyleLoadResult.fail(
        'Map preview unavailable · style failed to load',
      );
    }
  }

  static Future<({bool ok, String message})> _preflightMapTiler(
    String apiKey,
  ) async {
    final client = HttpClient();
    try {
      client.userAgent = MapPreviewConfig.mapTilerUserAgent;
      final uri = Uri.parse(MapPreviewConfig.tilesPreflightUrl(apiKey));
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(
        HttpHeaders.userAgentHeader,
        MapPreviewConfig.mapTilerUserAgent,
      );
      final res = await req.close().timeout(const Duration(seconds: 12));
      await res.drain<void>();
      if (res.statusCode == 200) {
        return (ok: true, message: '');
      }
      if (res.statusCode == 403) {
        return (
          ok: false,
          message: 'Map preview unavailable · tile key restricted',
        );
      }
      return (
        ok: false,
        message: 'Map preview unavailable · tiles unreachable',
      );
    } catch (_) {
      return (
        ok: false,
        message: 'Map preview unavailable · network error',
      );
    } finally {
      client.close(force: true);
    }
  }
}
