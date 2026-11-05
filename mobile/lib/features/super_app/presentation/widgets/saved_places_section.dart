import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_card.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';

class SavedPlacesSection extends StatelessWidget {
  const SavedPlacesSection({
    required this.onUnavailable,
    this.onSavedPlaceTap,
    super.key,
  });

  final ValueChanged<String> onUnavailable;
  final VoidCallback? onSavedPlaceTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OraSectionHeader(
          title: 'Saved places',
          action: GestureDetector(
            onTap: () => onUnavailable('Saved places'),
            child: Text(
              'See all',
              style: OraTypography.caption(OraColors.primary)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: OraSpacing.sm),
        OraCard(
          padding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.sm,
            vertical: OraSpacing.xxs,
          ),
          child: Column(
            children: [
              _SavedPlaceRow(
                icon: Icons.home_rounded,
                title: 'Home',
                subtitle: 'DHA Phase 5, Lahore',
                onTap: onSavedPlaceTap ?? () => onUnavailable('Home'),
              ),
              const Divider(height: 1, color: OraColors.border),
              _SavedPlaceRow(
                icon: Icons.work_outline_rounded,
                title: 'Work',
                subtitle: 'MM Alam Road, Gulberg',
                onTap: onSavedPlaceTap ?? () => onUnavailable('Work'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OraRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x0FFFFFFF),
              ),
              child: Icon(icon, size: 18, color: OraColors.textSecondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary)
                        .copyWith(fontSize: 13.5),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.textMuted)
                        .copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: OraColors.textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
