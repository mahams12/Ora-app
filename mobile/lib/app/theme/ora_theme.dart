import 'package:flutter/material.dart';

import 'ora_colors.dart';
import 'ora_elevation.dart';
import 'ora_radius.dart';
import 'ora_typography.dart';

class OraTheme {
  OraTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? OraColors.gold400 : OraColors.navy900,
      onPrimary: isDark ? OraColors.navy900 : Colors.white,
      secondary: OraColors.teal500,
      onSecondary: Colors.white,
      error: OraColors.error,
      onError: Colors.white,
      surface: isDark ? OraColors.surfaceDark : Colors.white,
      onSurface: isDark ? OraColors.textPrimaryDark : OraColors.textPrimaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? OraColors.navy900 : OraColors.surfaceLight,
      fontFamily: OraTypography.fontFamily,
      textTheme: OraTypography.textTheme(brightness),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? OraColors.navy800 : Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: OraElevation.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.lg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? OraColors.navy800 : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
