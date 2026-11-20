import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
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

  /// `flutter test` sets FLUTTER_TEST=true — keep previews on the static
  /// soft-fail shell there so widget tests never mount a real MapLibre
  /// platform view (which schedules frames forever and hangs pumpAndSettle).
  static bool get _isFlutterTest =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  static Future<MapPreviewStyleLoadResult> load() async {
    if (_isFlutterTest) {
      return const MapPreviewStyleLoadResult.fail(
        'Map preview unavailable · test environment',
      );
    }
    if (!MapPreviewConfig.hasTileKey) {
      return _loadOpenFreeMap();
    }

    final apiKey = MapPreviewConfig.mapTilerApiKey;
    try {
      await setHttpHeaders({
        'user-agent': MapPreviewConfig.mapTilerUserAgent,
      });

      final preflight =
          await _preflight(MapPreviewConfig.tilesPreflightUrl(apiKey));
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

  /// Keyless $0 path — same Ora dark style retargeted to OpenFreeMap tiles +
  /// glyphs (OpenMapTiles schema). Sprite is dropped (unused — no icon-image
  /// layers) so no keyed MapTiler asset is referenced.
  static Future<MapPreviewStyleLoadResult> _loadOpenFreeMap() async {
    try {
      await setHttpHeaders({
        'user-agent': MapPreviewConfig.mapTilerUserAgent,
      });

      final preflight =
          await _preflight(MapPreviewConfig.openFreeMapTilesUrl);
      if (!preflight.ok) {
        return MapPreviewStyleLoadResult.fail(preflight.message);
      }

      final raw =
          await rootBundle.loadString(MapPreviewConfig.styleAssetPath);
      final style = jsonDecode(raw) as Map<String, Object?>;
      final sources = style['sources'];
      if (sources is Map) {
        final omt = sources['openmaptiles'];
        if (omt is Map) {
          omt['url'] = MapPreviewConfig.openFreeMapTilesUrl;
          omt['attribution'] = MapPreviewConfig.openFreeMapAttribution;
        }
      }
      style['glyphs'] = MapPreviewConfig.openFreeMapGlyphsUrl;
      style.remove('sprite');
      return MapPreviewStyleLoadResult.ok(jsonEncode(style));
    } catch (_) {
      return const MapPreviewStyleLoadResult.fail(
        'Map preview unavailable · style failed to load',
      );
    }
  }

  static Future<({bool ok, String message})> _preflight(
    String url,
  ) async {
    final dio = Dio();
    try {
      final res = await dio.get<void>(
        url,
        options: Options(
          headers: {
            'accept': 'application/json',
            'user-agent': MapPreviewConfig.mapTilerUserAgent,
          },
          receiveTimeout: const Duration(seconds: 12),
          validateStatus: (_) => true,
        ),
      );
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
      dio.close();
    }
  }
}
