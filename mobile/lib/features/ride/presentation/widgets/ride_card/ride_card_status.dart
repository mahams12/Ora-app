import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Status badge for ride cards — luminous blue when active/emphasized.
class RideCardStatus extends StatelessWidget {
  const RideCardStatus({
    required this.label,
    super.key,
    this.emphasized = false,
  });

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final bg = emphasized ? OraColors.infoMuted : OraColors.navy;
    final fg = emphasized ? OraColors.info : OraColors.textSecondary;
    final border = emphasized
        ? OraColors.info.withValues(alpha: 0.45)
        : OraColors.border;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.sm,
        vertical: OraSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OraRadius.chip),
        border: Border.all(color: border),
        boxShadow: emphasized
            ? [
                BoxShadow(
                  color: OraColors.info.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: OraTypography.label(fg).copyWith(
          letterSpacing: 0.6,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
