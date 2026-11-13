import 'package:flutter/material.dart';

import 'ora_colors.dart';

/// Restrained elevation / shadow tokens for subtle depth without GPU cost.
class OraElevation {
  OraElevation._();

  static const card = 2.0;
  static const raised = 2.0;
  static const modal = 8.0;

  static List<BoxShadow> get cardShadow => const [
    BoxShadow(
      color: Color(0x2EF88733),
      blurRadius: 18,
      offset: Offset(0, 8),
      spreadRadius: -7,
    ),
    BoxShadow(
      color: Color(0x332A211D),
      blurRadius: 30,
      offset: Offset(0, 16),
      spreadRadius: -12,
    ),
  ];

  static List<BoxShadow> get raisedShadow => const [
    BoxShadow(
      color: Color(0x38F88733),
      blurRadius: 24,
      offset: Offset(0, 10),
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x402A211D),
      blurRadius: 40,
      offset: Offset(0, 20),
      spreadRadius: -12,
    ),
  ];

  static List<BoxShadow> get sheetShadow => const [
    BoxShadow(
      color: OraColors.shadow,
      blurRadius: 30,
      offset: Offset(0, -12),
      spreadRadius: -14,
    ),
  ];

  static List<BoxShadow> get primaryButtonShadow => const [
    BoxShadow(
      color: OraColors.goldMuted,
      blurRadius: 22,
      offset: Offset(0, 10),
      spreadRadius: -8,
    ),
  ];

  static List<BoxShadow> get secondaryButtonShadow => const [
    BoxShadow(
      color: OraColors.tealMuted,
      blurRadius: 22,
      offset: Offset(0, 10),
      spreadRadius: -8,
    ),
  ];

  /// Hairline border used instead of Material elevation on dark cards.
  static BorderSide get cardBorder =>
      const BorderSide(color: OraColors.border, width: 1);
}
