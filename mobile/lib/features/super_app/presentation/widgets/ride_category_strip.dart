import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';

class RideCategoryStrip extends StatelessWidget {
  const RideCategoryStrip({
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OraSectionHeader(
          title: 'Choose a ride',
          action: Text(
            '${_categories.length} options',
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ),
        const SizedBox(height: OraSpacing.sm),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: OraSpacing.sm),
            itemBuilder: (context, index) {
              final category = _categories[index];
              return _CategoryCard(
                category: category,
                selected: category.id == selectedId,
                onTap: () => onSelect(category.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RideCategory {
  const _RideCategory({
    required this.id,
    required this.name,
    required this.blurb,
    required this.icon,
  });

  final String id;
  final String name;
  final String blurb;
  final IconData icon;
}

const _categories = <_RideCategory>[
  _RideCategory(
    id: 'zip',
    name: 'Zip',
    blurb: 'Bike, fastest way',
    icon: Icons.two_wheeler_rounded,
  ),
  _RideCategory(
    id: 'trio',
    name: 'Trio',
    blurb: 'Rickshaw, 3 seats',
    icon: Icons.airport_shuttle_rounded,
  ),
  _RideCategory(
    id: 'easy',
    name: 'Easy',
    blurb: 'Compact',
    icon: Icons.directions_car_rounded,
  ),
  _RideCategory(
    id: 'breeze',
    name: 'Breeze',
    blurb: 'AC comfort car',
    icon: Icons.ac_unit_rounded,
  ),
  _RideCategory(
    id: 'executive',
    name: 'Executive',
    blurb: 'Big trunk · events',
    icon: Icons.airport_shuttle_outlined,
  ),
  _RideCategory(
    id: 'premium',
    name: 'Premium',
    blurb: 'Luxury feel ride',
    icon: Icons.workspace_premium_rounded,
  ),
];

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _RideCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: Material(
        color: selected ? OraColors.primaryMuted : OraColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? OraColors.primary : OraColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  color: selected ? OraColors.primary : OraColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(height: 10),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary)
                      .copyWith(fontSize: 13.5, height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  category.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.textMuted)
                      .copyWith(fontSize: 11, height: 1.15),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fare on request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.primary)
                      .copyWith(fontSize: 11, height: 1.1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
