import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../../app/theme/ora_colors.dart';
import '../../../app/theme/ora_radius.dart';
import '../../../app/theme/ora_typography.dart';

/// [ChatTheme] mapped onto the Ora palette — navy canvas, elevated-navy
/// received bubbles, gold sent bubbles with navy text, Inter body font.
abstract final class OraChatTheme {
  static ChatTheme dark() => ChatTheme(
        colors: const ChatColors(
          primary: OraColors.gold,
          onPrimary: OraColors.navy,
          surface: OraColors.canvas,
          onSurface: OraColors.ink,
          surfaceContainerLow: OraColors.navy,
          surfaceContainer: OraColors.navyElevated,
          surfaceContainerHigh: OraColors.surfaceStrong,
        ),
        typography: ChatTypography(
          bodyLarge: OraTypography.body(OraColors.ink).copyWith(fontSize: 16),
          bodyMedium: OraTypography.body(OraColors.ink),
          bodySmall: OraTypography.caption(OraColors.slate),
          labelLarge: OraTypography.label(OraColors.ink),
          labelMedium: OraTypography.label(OraColors.slate),
          labelSmall: OraTypography.caption(OraColors.slateMuted)
              .copyWith(fontSize: 10),
        ),
        shape: const BorderRadius.all(Radius.circular(OraRadius.card)),
      );
}
