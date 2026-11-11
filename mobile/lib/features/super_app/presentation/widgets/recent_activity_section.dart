import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_card.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../recent/recent_activity.dart';

class RecentActivitySection extends ConsumerWidget {
  const RecentActivitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(recentActivityProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OraSectionHeader(title: 'Frequently used'),
        const SizedBox(height: OraSpacing.sm),
        if (activities.isEmpty)
          Text(
            'Your recent rides, rentals and services will appear here.',
            style: OraTypography.caption(OraColors.textMuted),
          )
        else
          for (final activity in activities)
            Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.xs),
              child: OraCard(
                onTap: () => context.push<void>(activity.route),
                padding: const EdgeInsets.all(OraSpacing.sm),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(OraRadius.sm),
                      child: Image.asset(
                        activity.imageAsset,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                              color: OraColors.navyElevated,
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: OraColors.textMuted,
                                ),
                              ),
                            ),
                      ),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          Text(
                            activity.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: OraSpacing.xs),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: OraColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
