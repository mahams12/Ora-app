import 'package:flutter/material.dart';

import 'ora_colors.dart';
import 'ora_elevation.dart';
import 'ora_radius.dart';
import 'ora_spacing.dart';
import 'ora_typography.dart';

/// Ora [ThemeData] — dark surfaces match the prototype; light remains usable.
class OraTheme {
  OraTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: OraColors.primary,
      onPrimary: OraColors.primaryForeground,
      secondary: OraColors.secondary,
      onSecondary: OraColors.secondaryForeground,
      error: OraColors.danger,
      onError: Colors.white,
      surface: isDark ? OraColors.surfaceElevated : Colors.white,
      onSurface: isDark ? OraColors.textPrimary : OraColors.textPrimaryLight,
      outline: isDark ? OraColors.border : const Color(0xFFD0D5DD),
    );

    final textTheme = OraTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? OraColors.background
          : OraColors.surfaceLight,
      fontFamily: OraTypography.bodyFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? OraColors.surface : Colors.white,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: isDark ? OraColors.surfaceElevated : Colors.white,
        elevation: OraElevation.card,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.card),
          side: isDark ? OraElevation.cardBorder : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? OraColors.divider : const Color(0xFFE4E7EC),
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? OraColors.surfaceElevated : Colors.white,
        selectedColor: OraColors.primaryMuted,
        disabledColor: OraColors.disabled,
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.sm,
          vertical: OraSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.chip),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: OraColors.primary,
          foregroundColor: OraColors.primaryForeground,
          textStyle: OraTypography.button(OraColors.primaryForeground),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: isDark ? OraColors.textSecondary : OraColors.navy,
          textStyle: OraTypography.button(
            isDark ? OraColors.textSecondary : OraColors.navy,
          ),
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: isDark ? OraColors.textSecondary : OraColors.navy,
          textStyle: OraTypography.button(
            isDark ? OraColors.textSecondary : OraColors.navy,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? OraColors.surfaceElevated : Colors.white,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? OraColors.textMuted : OraColors.textSecondaryLight,
        ),
        labelStyle: textTheme.labelMedium,
        errorStyle: textTheme.bodySmall?.copyWith(color: OraColors.danger),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.md,
          vertical: OraSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: BorderSide(color: colorScheme.outline, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: const BorderSide(color: OraColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: const BorderSide(color: OraColors.danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: const BorderSide(color: OraColors.danger, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(OraRadius.input),
          borderSide: const BorderSide(color: OraColors.disabled, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? OraColors.surfaceElevated : Colors.white,
        modalBackgroundColor: isDark ? OraColors.surfaceElevated : Colors.white,
        elevation: OraElevation.modal,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(OraRadius.sheet),
          ),
        ),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? OraColors.surfaceStrong : OraColors.navy,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: OraColors.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.md),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: OraColors.primary,
      ),
    );
  }
}
