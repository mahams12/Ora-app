/// Pure layout helpers for Ride Request half-screen map UX.
///
/// Display-only sizing — does not touch pricing, Places, or camera policy.
///
/// [viewportHeight] should be the **already-usable** column height (after
/// SafeArea / keyboard resize). Do not subtract the same insets twice.
class RideRequestMapLayout {
  RideRequestMapLayout._();

  /// Target share of usable height for the compact map (normal layouts).
  static const double compactFraction = 0.50;

  static const double compactFractionMin = 0.45;
  static const double compactFractionMax = 0.55;

  /// When the keyboard is open, keep the map smaller so the form stays usable.
  static const double keyboardCompactFraction = 0.32;

  static const double minCompactHeight = 160;
  static const double minSheetHeight = 220;

  /// Sheet overlap used by [RideRequestView] (visual tuck under map).
  static const double sheetOverlap = 18;

  /// Compact map height for the given usable column height.
  static double compactMapHeight({
    required double viewportHeight,
    required bool keyboardVisible,
  }) {
    final available = viewportHeight.clamp(0.0, double.infinity);
    if (available <= 0) return minCompactHeight;

    final double raw;
    if (keyboardVisible) {
      raw = available * keyboardCompactFraction;
    } else {
      raw = (available * compactFraction).clamp(
        available * compactFractionMin,
        available * compactFractionMax,
      );
    }

    final maxMap = (available - minSheetHeight).clamp(0.0, available);
    if (maxMap < minCompactHeight) {
      // Very short screens: prefer a smaller map so the sheet remains usable.
      return raw.clamp(available * 0.35, available * 0.45);
    }
    return raw.clamp(minCompactHeight, maxMap);
  }

  /// Full-bleed height while expanded (fill the column).
  static double expandedMapHeight({required double viewportHeight}) {
    return viewportHeight.clamp(0.0, double.infinity);
  }
}
