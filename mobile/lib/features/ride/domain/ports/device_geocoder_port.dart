/// Device-side reverse geocoder (platform `Geocoder` on Android,
/// `CLGeocoder` on iOS) — no API key, no cloud billing.
///
/// Used only as a fallback when the Places HTTP lookup fails; coordinates
/// remain authoritative and the label is display-only. Never invents a name.
abstract class DeviceGeocoderPort {
  /// Best-effort human-readable locality/address for [lat]/[lng].
  ///
  /// Returns null when the platform geocoder is unavailable or finds no
  /// usable label. Throws only on argument errors.
  Future<String?> localityLabel({required double lat, required double lng});
}
