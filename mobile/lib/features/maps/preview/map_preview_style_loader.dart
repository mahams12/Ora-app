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
      return _loadOpenFreeMap();
    }

    final apiKey = MapPreviewConfig.mapTilerApiKey;
    try {
      await setHttpHeaders({
        HttpHeaders.userAgentHeader: MapPreviewConfig.mapTilerUserAgent,
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
        HttpHeaders.userAgentHeader: MapPreviewConfig.mapTilerUserAgent,
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
    final client = HttpClient();
    try {
      client.userAgent = MapPreviewConfig.mapTilerUserAgent;
      final uri = Uri.parse(url);
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
