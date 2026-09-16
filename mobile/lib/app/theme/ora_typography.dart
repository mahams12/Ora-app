import 'package:flutter/material.dart';

import 'ora_colors.dart';

/// Ora typography — Sora for display/emphasis, Inter for body/UI.
class OraTypography {
  OraTypography._();

  static const displayFamily = 'Sora';
  static const bodyFamily = 'Inter';

  /// Primary UI font family for [ThemeData.fontFamily] (body default).
  static const fontFamily = bodyFamily;

  static TextStyle _sora({
    required double size,
    required FontWeight weight,
    required Color color,
    double height = 1.25,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle _inter({
    required double size,
    required FontWeight weight,
    required Color color,
    double height = 1.45,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Semantic styles for direct use (prefer these over ad-hoc sizes).
  static TextStyle display(Color color) =>
      _sora(size: 28, weight: FontWeight.w800, color: color, height: 1.2);

  static TextStyle headline(Color color) =>
      _sora(size: 22, weight: FontWeight.w700, color: color, height: 1.25);

  static TextStyle title(Color color) =>
      _sora(size: 18, weight: FontWeight.w700, color: color);

  static TextStyle sectionTitle(Color color) => _sora(
    size: 12,
    weight: FontWeight.w700,
    color: color,
    letterSpacing: 0.06 * 12,
  );

  static TextStyle body(Color color) =>
      _inter(size: 14, weight: FontWeight.w400, color: color);

  static TextStyle bodyEmphasis(Color color) =>
      _inter(size: 14, weight: FontWeight.w600, color: color);

  static TextStyle label(Color color) =>
      _inter(size: 12, weight: FontWeight.w600, color: color);

  static TextStyle caption(Color color) =>
      _inter(size: 11.5, weight: FontWeight.w500, color: color, height: 1.35);

  static TextStyle button(Color color) =>
      _sora(size: 14, weight: FontWeight.w700, color: color, height: 1.2);

  static TextStyle numeric(Color color) =>
      _sora(size: 18, weight: FontWeight.w800, color: color, height: 1.2);

  static TextTheme textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? OraColors.textPrimary : OraColors.textPrimaryLight;
    final secondary = isDark
        ? OraColors.textSecondary
        : OraColors.textSecondaryLight;

    return TextTheme(
      displayLarge: display(primary),
      displayMedium: _sora(size: 24, weight: FontWeight.w800, color: primary),
      displaySmall: headline(primary),
      headlineLarge: headline(primary),
      headlineMedium: _sora(size: 20, weight: FontWeight.w700, color: primary),
      headlineSmall: title(primary),
      titleLarge: title(primary),
      titleMedium: _sora(size: 16, weight: FontWeight.w700, color: primary),
      titleSmall: _sora(size: 14, weight: FontWeight.w700, color: primary),
      bodyLarge: _inter(
        size: 16,
        weight: FontWeight.w400,
        color: primary,
        height: 1.5,
      ),
      bodyMedium: body(primary),
      bodySmall: caption(secondary),
      labelLarge: button(primary),
      labelMedium: label(secondary),
      labelSmall: _inter(
        size: 11,
        weight: FontWeight.w600,
        color: secondary,
        letterSpacing: 0.04 * 11,
      ),
    );
  }
}
