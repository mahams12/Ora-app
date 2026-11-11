import 'package:flutter/material.dart';

/// Ora brand + semantic palette — aligned with the HTML prototype `:root`.
///
/// Prefer semantic names (`primary`, `surface`, `textPrimary`, …) in new code.
/// Legacy navy/gold/teal aliases remain for existing screens.
class OraColors {
  OraColors._();

  // ── Brand primitives (prototype) ───────────────────────────────────────────

  static const navy = Color(0xFFF2E3DD);
  static const navyElevated = Color(0xFFFFF7F3);
  static const canvas = Color(0xFFF2E3DD);

  static const gold = Color(0xFFF88733);
  static const goldMuted = Color(0x33F88733);
  static const goldSoft = Color(0xFFA67D68);
  static const goldDeep = Color(0xFFE16F22);

  static const teal = Color(0xFFA67D68);
  static const tealMuted = Color(0x33E9C2AD);
  static const tealBright = Color(0xFFA67D68);
  static const tealDeep = Color(0xFF8A624E);

  static const info = Color(0xFFA67D68);
  static const infoMuted = Color(0x33A67D68);

  static const accentPurple = Color(0xFFF88733);
  static const accentCoral = Color(0xFFF88733);

  static const ink = Color(0xFF2A211D);
  static const slate = Color(0xFFA67D68);
  static const slateMuted = Color(0xFFA67D68);
  static const line = Color(0xFFE9C2AD);
  static const starEmpty = Color(0xFFE9C2AD);

  static const danger = Color(0xFFB33B36);
  static const dangerForeground = Color(0xFF8F2926);
  static const dangerMuted = Color(0x1AB33B36);

  static const success = Color(0xFF30A46C);
  static const successSurface = Color(0xFFE8F5EC);
  static const successForeground = Color(0xFF2D6A4F);
  static const successBorder = Color(0xFF95D5B2);
  static const warning = Color(0xFFE16F22);
  static const warningSurface = Color(0xFFFFF0D6);
  static const warningForeground = Color(0xFF8B6914);
  static const errorSurface = Color(0xFFFCE9E7);

  static const disabled = Color(0xFFE9C2AD);
  static const disabledForeground = Color(0xFFA67D68);
  static const shadow = Color(0x142A211D);
  static const photoScrim = Color(0x99000000);
  static const photoScrimStrong = Color(0xE6000000);
  static const onPhoto = Color(0xFFFFFFFF);
  static const onPhotoMuted = Color(0xD9FFFFFF);
  static const photoChip = Color(0xF2FFFFFF);

  // ── Semantic aliases (preferred) ───────────────────────────────────────────

  static const primary = gold;
  static const primaryMuted = Color(0xFFE9C2AD);
  static const primaryForeground = Color(0xFFFFFFFF);

  static const secondary = teal;
  static const secondaryMuted = tealMuted;
  static const secondaryForeground = Color(0xFF2A211D);

  static const background = canvas;
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFFF7F3);
  static const surfaceStrong = Color(0xFFFFFFFF);

  static const textPrimary = ink;
  static const textSecondary = slate;
  static const textMuted = slateMuted;

  static const border = line;
  static const divider = line;

  // ── Legacy aliases (existing screens) ──────────────────────────────────────

  static const navy900 = navy;
  static const navy800 = navyElevated;
  static const navy700 = surfaceStrong;
  static const gold500 = gold;
  static const gold400 = Color(0xFFFFA45E);
  static const teal500 = teal;
  static const teal400 = Color(0xFFB48A73);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark = canvas;
  static const error = danger;
  static const textPrimaryLight = Color(0xFF2A211D);
  static const textSecondaryLight = Color(0xFFA67D68);
  static const textPrimaryDark = ink;
  static const textSecondaryDark = Color(0xFFA67D68);
}
