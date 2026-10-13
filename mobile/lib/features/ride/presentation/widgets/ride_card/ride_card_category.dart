import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_assets.dart';
import 'ride_card_model.dart';

/// Easy / Medium difficulty pill from server `category`.
class RideCardCategoryBadge extends StatelessWidget {
  const RideCardCategoryBadge({
    required this.label,
    required this.tone,
    super.key,
  });

  final String label;
  final RideCardCategoryTone tone;

  @override
  Widget build(BuildContext context) {
    if (tone == RideCardCategoryTone.none || label.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final (Color bg, Color fg, IconData? icon, String? asset) = switch (tone) {
      RideCardCategoryTone.easy => (
          const Color(0xFF1B4332),
          const Color(0xFF95D5B2),
          null,
          RideCardAssets.shieldCheck,
        ),
      RideCardCategoryTone.medium => (
          const Color(0xFF3D2E0F),
          const Color(0xFFFFD166),
          Icons.flag_rounded,
          null,
        ),
      RideCardCategoryTone.hard => (
          const Color(0xFF3D1515),
          const Color(0xFFF5A8A8),
          Icons.warning_amber_rounded,
          null,
        ),
      RideCardCategoryTone.none => (
          OraColors.navy,
          OraColors.textSecondary,
          Icons.circle,
          null,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (asset != null)
            RideCardAssetImage(assetPath: asset, width: 12, height: 12)
          else if (icon != null)
            Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: OraTypography.label(fg).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
