import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ora_colors.dart';
import 'ora_elevation.dart';
import 'ora_radius.dart';
import 'ora_spacing.dart';
import 'ora_typography.dart';

/// Ora [ThemeData] — warm light surfaces with orange accents.
class OraTheme {
  OraTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: OraColors.primary,
      onPrimary: OraColors.primaryForeground,
      secondary: OraColors.secondary,
      onSecondary: OraColors.secondaryForeground,
      error: OraColors.danger,
      onError: OraColors.onPhoto,
      surface: OraColors.surface,
      onSurface: OraColors.textPrimary,
      outline: OraColors.border,
      // Tonal fills (IconButton.filledTonal, tonal chips) read as bright
      // orange instead of the muted brown secondary tint.
      secondaryContainer: OraColors.gold,
      onSecondaryContainer: OraColors.primaryForeground,
    );

    final textTheme = OraTypography.textTheme(brightness);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: OraTypography.bodyFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: OraColors.goldSharp,
        foregroundColor: OraColors.primaryForeground,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 3,
        shadowColor: const Color(0x55C25E10),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: OraColors.primaryForeground,
        ),
        iconTheme: const IconThemeData(color: OraColors.primaryForeground),
        actionsIconTheme: const IconThemeData(
          color: OraColors.primaryForeground,
        ),
      ),
      cardTheme: CardThemeData(
        color: OraColors.surface,
        elevation: OraElevation.card,
        shadowColor: OraColors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.card),
          side: const BorderSide(color: OraColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: OraColors.divider,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: OraColors.surfaceElevated,
        selectedColor: OraColors.gold,
        checkmarkColor: OraColors.primaryForeground,
        disabledColor: OraColors.disabled,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: OraColors.primaryForeground,
          fontWeight: FontWeight.w700,
        ),
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
          foregroundColor: OraColors.goldDeep,
          textStyle: OraTypography.button(OraColors.goldDeep),
          side: const BorderSide(color: OraColors.gold, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.button),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: OraColors.goldDeep,
          textStyle: OraTypography.button(OraColors.goldDeep),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: OraColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: OraColors.textSecondary,
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: OraColors.surface,
        modalBackgroundColor: OraColors.surface,
        elevation: OraElevation.modal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(OraRadius.sheet),
          ),
        ),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: OraColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: OraColors.onPhoto,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.md),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: OraColors.primary,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: OraColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: OraColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _OraPageTransitions(
            FadeUpwardsPageTransitionsBuilder(),
          ),
          TargetPlatform.fuchsia: _OraPageTransitions(
            FadeUpwardsPageTransitionsBuilder(),
          ),
          TargetPlatform.linux: _OraPageTransitions(
            FadeUpwardsPageTransitionsBuilder(),
          ),
          TargetPlatform.windows: _OraPageTransitions(
            FadeUpwardsPageTransitionsBuilder(),
          ),
          TargetPlatform.iOS: _OraPageTransitions(
            CupertinoPageTransitionsBuilder(),
          ),
          TargetPlatform.macOS: _OraPageTransitions(
            CupertinoPageTransitionsBuilder(),
          ),
        },
      ),
    );
  }
}

/// Paints the shared background gradient inside every pushed page so routes
/// stay fully opaque while entering and exiting. Scaffolds are transparent by
/// design; without this, the outgoing screen ghosts through the incoming one
/// during transitions (double-exposure flash on back/pop/tab switches).
class _OraPageTransitions extends PageTransitionsBuilder {
  const _OraPageTransitions(this._delegate);

  final PageTransitionsBuilder _delegate;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _delegate.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      DecoratedBox(
        decoration: const BoxDecoration(
          gradient: OraColors.backgroundGradient,
        ),
        child: child,
      ),
    );
  }
}
