import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../domain/models/ride_category_option.dart';

/// Prototype-faithful category rows without fabricated fares or ETAs.
class RideCategorySelector extends StatelessWidget {
  const RideCategorySelector({
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final cat in kRideCategoryOptions) ...[
          _CategoryRow(
            category: cat,
            selected: cat.id == selectedId,
            onTap: () => onSelect(cat.id),
          ),
          if (cat != kRideCategoryOptions.last)
            const SizedBox(height: OraSpacing.xs),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final RideCategoryOption category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${category.name}, ${category.blurb}, ${category.priceLabel}',
      child: AnimatedScale(
        scale: selected ? 1.01 : 1,
        duration: OraMotion.select,
        child: OraCard(
          selected: selected,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.md,
            vertical: OraSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? OraColors.primaryMuted
                      : OraColors.surfaceStrong,
                  borderRadius: BorderRadius.circular(OraRadius.sm),
                ),
                child: Icon(
                  category.icon,
                  color: selected ? OraColors.primary : OraColors.textSecondary,
                ),
              ),
              const SizedBox(width: OraSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    ),
                    Text(
                      category.blurb,
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                category.priceLabel,
                style: OraTypography.label(
                  selected ? OraColors.primary : OraColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
