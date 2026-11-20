import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

enum StatusPillVariant { quotation, comingSoon, notActive }

class StatusPill extends StatelessWidget {
  const StatusPill({required this.variant, super.key, this.inverse = false});

  const StatusPill.quotation({super.key, this.inverse = false})
    : variant = StatusPillVariant.quotation;
  const StatusPill.comingSoon({super.key, this.inverse = false})
    : variant = StatusPillVariant.comingSoon;
  const StatusPill.notActive({super.key, this.inverse = false})
    : variant = StatusPillVariant.notActive;

  final StatusPillVariant variant;
  final bool inverse;

  String get _label => switch (variant) {
    StatusPillVariant.quotation => 'Quotation',
    StatusPillVariant.comingSoon => 'Coming soon',
    StatusPillVariant.notActive => 'Not active',
  };

  Color get _foreground => switch (variant) {
    StatusPillVariant.quotation => OraColors.info,
    StatusPillVariant.comingSoon => OraColors.gold,
    StatusPillVariant.notActive => OraColors.textMuted,
  };

  Color get _background => switch (variant) {
    StatusPillVariant.quotation => OraColors.infoMuted,
    StatusPillVariant.comingSoon => OraColors.goldMuted,
    StatusPillVariant.notActive => OraColors.border,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: OraSpacing.xs,
          vertical: OraSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: inverse ? OraColors.photoChip : _background,
          borderRadius: BorderRadius.circular(OraRadius.pill),
        ),
        child: Text(
          _label,
          style: OraTypography.caption(
            inverse ? OraColors.navy : _foreground,
          ).copyWith(height: 1),
        ),
      ),
    );
  }
}
