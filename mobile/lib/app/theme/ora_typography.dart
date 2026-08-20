import 'package:flutter/material.dart';

class OraTypography {
  OraTypography._();

  static const String fontFamily = 'Roboto';

  static TextTheme textTheme(Brightness brightness) {
    final primary = brightness == Brightness.dark
        ? const Color(0xFFF5F7FA)
        : const Color(0xFF0A1628);
    final secondary = brightness == Brightness.dark
        ? const Color(0xFFA8B3C2)
        : const Color(0xFF5C6B7A);

    return TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: primary,
        height: 1.2,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: primary,
        height: 1.25,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.3,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.35,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: primary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: primary,
        height: 1.45,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
        height: 1.2,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
        height: 1.4,
      ),
    );
  }
}
