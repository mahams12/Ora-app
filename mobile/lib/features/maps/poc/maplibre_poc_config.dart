/// Disposable MapLibre PoC configuration.
///
/// Tile key is build-time only (`--dart-define` / local.properties → build script).
/// Never hardcode secrets. Missing key → fail closed (no map widget).
class MapLibrePoCConfig {
  MapLibrePoCConfig._();

  /// Preferred define. Also accepts [ORA_MAPTILER_API_KEY] as alias.
  static const String tileKeyDefine = String.fromEnvironment(
    'MAPLIBRE_TILE_KEY',
    defaultValue: '',
  );

  static const String mapTilerKeyAlias = String.fromEnvironment(
    'ORA_MAPTILER_API_KEY',
    defaultValue: '',
  );

  /// Resolved MapTiler Cloud key (empty ⇒ PoC must not load tiles).
  static String get mapTilerApiKey {
    final primary = tileKeyDefine.trim();
    if (primary.isNotEmpty) return primary;
    return mapTilerKeyAlias.trim();
  }

  static bool get hasTileKey => mapTilerApiKey.isNotEmpty;

  /// Asset style with `__MAPTILER_KEY__` placeholders (Ora-controlled paints).
  static const String styleAssetPath =
      'assets/maps/poc/ora_maplibre_poc_style.json';

  static const String styleKeyPlaceholder = '__MAPTILER_KEY__';

  static const String pickupMarkerAsset =
      'assets/maps/poc/poc_pickup_marker.png';
  static const String destinationMarkerAsset =
      'assets/maps/poc/poc_destination_marker.png';
  static const String driverMarkerAsset =
      'assets/maps/poc/poc_driver_marker.png';

  /// Prerequisite copy when key is absent (safe, no invented credentials).
  static const String missingKeyMessage =
      'MAPLIBRE_TILE_KEY (MapTiler) is not configured.\n\n'
      'Set it via --dart-define=MAPLIBRE_TILE_KEY=… or '
      'android/local.properties (gitignored), then rebuild.\n\n'
      'This disposable PoC will not invent or hardcode a tile key.';

  /// Preflight URL (key appended at runtime; never log the key).
  static String tilesPreflightUrl(String apiKey) =>
      'https://api.maptiler.com/tiles/v3/tiles.json?key=$apiKey';

  /// Must match MapTiler Cloud → API Keys → Allowed User-Agent (case-sensitive
  /// substring). Dedicated PoC key accepts requests containing "Ora".
  /// Native MapLibre/OkHttp defaults do NOT match and get HTTP 403.
  static const String mapTilerUserAgent = 'Ora-MapLibre-PoC/1.0';

  static const String keyRestrictedMessage =
      'MapTiler rejected this API key (HTTP 403 — key usage restricted).\n\n'
      'Native MapLibre tile requests must send User-Agent containing the '
      'Allowed User-Agent substring configured on the PoC key '
      '(currently expected: "Ora").\n\n'
      'In MapTiler Cloud → API Keys → EDIT "Ora MapLibre PoC":\n'
      '• Prefer Allowed User-Agent = Ora (mobile) — do NOT combine with HTTP '
      'origins on the same key (AND logic blocks native requests), or\n'
      '• Clear both restrictions only for local disposable testing.\n\n'
      'Key stays local/gitignored; never commit or log it.';
}

