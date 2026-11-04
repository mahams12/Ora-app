/// Production Ride Request map-preview configuration (MapLibre + MapTiler).
///
/// Tile key is build-time only (`--dart-define` / local.properties).
/// Never hardcode secrets. Missing key → soft-fail shell (never gates rides).
class MapPreviewConfig {
  MapPreviewConfig._();

  /// Preferred define. Also accepts [ORA_MAPTILER_API_KEY] as alias.
  static const String tileKeyDefine = String.fromEnvironment(
    'MAPLIBRE_TILE_KEY',
    defaultValue: '',
  );

  static const String mapTilerKeyAlias = String.fromEnvironment(
    'ORA_MAPTILER_API_KEY',
    defaultValue: '',
  );

  /// Resolved MapTiler Cloud key (empty ⇒ preview must soft-fail).
  static String get mapTilerApiKey {
    final primary = tileKeyDefine.trim();
    if (primary.isNotEmpty) return primary;
    return mapTilerKeyAlias.trim();
  }

  static bool get hasTileKey => mapTilerApiKey.isNotEmpty;

  static const String styleAssetPath =
      'assets/maps/preview/ora_dark_style.json';

  static const String styleKeyPlaceholder = '__MAPTILER_KEY__';

  static const String pickupMarkerAsset =
      'assets/maps/preview/pickup_marker.png';
  static const String destinationMarkerAsset =
      'assets/maps/preview/destination_marker.png';

  /// Must match MapTiler Cloud → API Keys → Allowed User-Agent substring.
  /// Native MapLibre/OkHttp defaults do NOT match and get HTTP 403.
  static const String mapTilerUserAgent = 'Ora-MapPreview/1.0';

  /// Preflight URL (key appended at runtime; never log the key).
  static String tilesPreflightUrl(String apiKey) =>
      'https://api.maptiler.com/tiles/v3/tiles.json?key=$apiKey';

  /// $0 keyless fallback — OpenFreeMap (OpenMapTiles schema over OSM data,
  /// free public CDN, no API key). Used only when no MapTiler key is
  /// configured so previews still render instead of soft-failing.
  static const String openFreeMapTilesUrl =
      'https://tiles.openfreemap.org/planet';

  static const String openFreeMapGlyphsUrl =
      'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf';

  static const String openFreeMapAttribution =
      '<a href="https://openfreemap.org" target="_blank">&copy; OpenFreeMap</a>'
      ' <a href="https://openmaptiles.org" target="_blank">&copy; OpenMapTiles</a>'
      ' <a href="https://www.openstreetmap.org/copyright" target="_blank">&copy; OpenStreetMap contributors</a>';

  /// Approved Ora map accent blue (route core + glow).
  static const String routeBlue = '#4FA3D9';
  static const String routeGlow = '#7CC8F5';

  static const double routeCoreWidth = 5.5;
  static const double routeGlowWidth = 10;
  static const double threeDTilt = 52;
  static const double flatTilt = 0;
}
