import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';

/// Status badge — green completed, red cancelled, blue in-progress.
class RideCardStatus extends StatelessWidget {
  const RideCardStatus({
    required this.label,
    super.key,
    this.emphasized = false,
    this.kind = RideCardStatusKind.neutral,
    this.icon,
  });

  final String label;
  final bool emphasized;
  final RideCardStatusKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border, IconData? resolvedIcon) =
        switch (kind) {
      RideCardStatusKind.success => (
          const Color(0xFF1B4332),
          const Color(0xFF95D5B2),
          const Color(0xFF2D6A4F),
          icon ?? Icons.check_circle_rounded,
        ),
      RideCardStatusKind.danger => (
          const Color(0xFF3D1515),
          const Color(0xFFF5A8A8),
          const Color(0xFF8B2E2E),
          icon ?? Icons.cancel_rounded,
        ),
      RideCardStatusKind.warning => (
          const Color(0xFF3D2E0F),
          const Color(0xFFFFD166),
          const Color(0xFF8B6914),
          icon,
        ),
      RideCardStatusKind.active => (
          OraColors.infoMuted,
          OraColors.info,
          OraColors.info.withValues(alpha: 0.5),
          icon ?? Icons.directions_car_filled_rounded,
        ),
      RideCardStatusKind.neutral => (
          emphasized ? OraColors.infoMuted : OraColors.navy,
          emphasized ? OraColors.info : OraColors.textSecondary,
          emphasized
              ? OraColors.info.withValues(alpha: 0.45)
              : OraColors.border,
          icon,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.sm,
        vertical: OraSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: border),
        boxShadow: kind == RideCardStatusKind.active || emphasized
            ? [
                BoxShadow(
                  color: OraColors.info.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resolvedIcon != null) ...[
            Icon(resolvedIcon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: OraTypography.label(fg).copyWith(
                letterSpacing: 0.2,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark pill with yellow/amber text for raw state chips (e.g. RIDE_STARTED).
class RideCardSecondaryStatus extends StatelessWidget {
  const RideCardSecondaryStatus({
    required this.label,
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.sm,
        vertical: OraSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF12161F),
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: OraColors.warning.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.toUpperCase(),
        style: OraTypography.label(OraColors.warning).copyWith(
          fontSize: 10,
          letterSpacing: 0.6,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}
