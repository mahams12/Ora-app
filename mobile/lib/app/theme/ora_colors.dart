import 'package:flutter/material.dart';

/// Ora brand + semantic palette — aligned with the HTML prototype `:root`.
///
/// Prefer semantic names (`primary`, `surface`, `textPrimary`, …) in new code.
/// Legacy navy/gold/teal aliases remain for existing screens.
class OraColors {
  OraColors._();

  // ── Brand primitives (prototype) ───────────────────────────────────────────

  static const navy = Color(0xFF12182B);
  static const navyElevated = Color(0xFF1B2340);
  static const canvas = Color(0xFF0B0F1C);

  static const gold = Color(0xFFD4A756);
  static const goldMuted = Color(0x2ED4A756); // ~18%
  static const goldSoft = Color(0xFFF3E3C2);
  static const goldDeep = Color(0xFFC1943F);

  static const teal = Color(0xFF1F9C82);
  static const tealMuted = Color(0x301F9C82); // ~18%
  static const tealBright = Color(0xFF7CFFCE);
  static const tealDeep = Color(0xFF167A66);

  static const info = Color(0xFF4FA3D9);
  static const infoMuted = Color(0x384FA3D9);

  static const accentPurple = Color(0xFFA78BFA);
  static const accentCoral = Color(0xFFF08A6A);

  static const ink = Color(0xFFF4F6FA);
  static const slate = Color(0xFFA8AEBF);
  static const slateMuted = Color(0xFF7A8196);
  static const line = Color(0xFF2A334D);
  static const starEmpty = Color(0xFF3A4560);

  static const danger = Color(0xFFC24A4A);
  static const dangerForeground = Color(0xFFF5A8A8);
  static const dangerMuted = Color(0x33C24A4A);

  static const success = Color(0xFF30A46C);
  static const warning = Color(0xFFE8A317);

  static const disabled = Color(0xFF3A4560);
  static const disabledForeground = Color(0xFF7A8196);

  // ── Semantic aliases (preferred) ───────────────────────────────────────────

  static const primary = gold;
  static const primaryMuted = goldMuted;
  static const primaryForeground = navy;

  static const secondary = teal;
  static const secondaryMuted = tealMuted;
  static const secondaryForeground = Color(0xFFFFFFFF);

  static const background = canvas;
  static const surface = navy;
  static const surfaceElevated = navyElevated;
  static const surfaceStrong = Color(0xFF243056);

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
  static const gold400 = Color(0xFFD4B44A);
  static const teal500 = teal;
  static const teal400 = Color(0xFF33B8A8);
  static const surfaceLight = Color(0xFFF5F7FA);
  static const surfaceDark = canvas;
  static const error = danger;
  static const textPrimaryLight = Color(0xFF0A1628);
  static const textSecondaryLight = Color(0xFF5C6B7A);
  static const textPrimaryDark = ink;
  static const textSecondaryDark = Color(0xFFA8B3C2);
}
