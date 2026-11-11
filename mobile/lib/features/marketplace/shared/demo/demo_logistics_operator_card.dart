import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import 'demo_listings.dart';

class DemoLogisticsOperatorCard extends StatelessWidget {
  const DemoLogisticsOperatorCard({
    required this.operator,
    required this.onSampleAction,
    super.key,
  });

  final DemoLogisticsOperator operator;
  final VoidCallback onSampleAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          'SAMPLE, ${operator.name}, ${operator.typeName}, '
          'rating ${operator.rating.toStringAsFixed(1)}, '
          '${operator.distance} away, ${operator.priceLabel}',
      onTap: onSampleAction,
      child: Container(
        decoration: BoxDecoration(
          color: OraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(OraRadius.card),
          border: Border.all(color: OraColors.border),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(OraRadius.card),
          child: InkWell(
            onTap: onSampleAction,
            borderRadius: BorderRadius.circular(OraRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(OraSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    height: 124,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(OraRadius.sm),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            operator.imageAsset,
                            cacheWidth: 360,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(
                                  color: OraColors.surfaceStrong,
                                  child: Icon(
                                    Icons.local_shipping_outlined,
                                    color: OraColors.textMuted,
                                  ),
                                ),
                          ),
                          Positioned(
                            top: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: OraColors.gold,
                                borderRadius: BorderRadius.circular(
                                  OraRadius.pill,
                                ),
                              ),
                              child: Text(
                                'SAMPLE',
                                style:
                                    OraTypography.caption(
                                      OraColors.primaryForeground,
                                    ).copyWith(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 5,
                            left: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: OraColors.navy.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(
                                  OraRadius.pill,
                                ),
                              ),
                              child: Text(
                                'Near you',
                                style: OraTypography.caption(
                                  OraColors.textPrimary,
                                ).copyWith(fontSize: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                operator.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.bodyEmphasis(
                                  OraColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Save sample operator',
                              onPressed: onSampleAction,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 44,
                                height: 44,
                              ),
                              icon: const Icon(
                                Icons.favorite_border_rounded,
                                color: OraColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          operator.typeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.textSecondary),
                        ),
                        const SizedBox(height: OraSpacing.xxs),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: OraColors.gold,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              operator.rating.toStringAsFixed(1),
                              style: OraTypography.caption(
                                OraColors.textPrimary,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: OraSpacing.xxs),
                            Expanded(
                              child: Text(
                                '(${operator.reviewCount} reviews)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${operator.distance} · ${operator.eta} · ${operator.area}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                        const SizedBox(height: OraSpacing.xxs),
                        const Wrap(
                          spacing: OraSpacing.xxs,
                          runSpacing: OraSpacing.xxs,
                          children: [
                            _OperatorBadge(
                              icon: Icons.verified_rounded,
                              label: 'Verified',
                            ),
                            _OperatorBadge(
                              icon: Icons.schedule_rounded,
                              label: 'On-time',
                            ),
                          ],
                        ),
                        const SizedBox(height: OraSpacing.xs),
                        Text(
                          operator.priceLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(
                            OraColors.goldSoft,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: OraSpacing.xxs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: onSampleAction,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: OraSpacing.sm,
                                ),
                                backgroundColor: OraColors.gold,
                                foregroundColor: OraColors.navy,
                              ),
                              child: const Text('Book now', maxLines: 1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OperatorBadge extends StatelessWidget {
  const _OperatorBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: OraColors.tealMuted,
        borderRadius: BorderRadius.circular(OraRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: OraColors.tealBright),
          const SizedBox(width: 3),
          Text(
            label,
            style: OraTypography.caption(
              OraColors.tealBright,
            ).copyWith(fontSize: 9),
          ),
        ],
      ),
    );
  }
}
