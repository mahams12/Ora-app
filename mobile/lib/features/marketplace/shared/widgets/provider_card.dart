import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

class ProviderCardModel {
  const ProviderCardModel({
    required this.name,
    required this.serviceName,
    this.rating,
    this.reviewCount,
    this.completedJobs,
    this.priceLabel,
    this.availability,
    this.isVerified,
  });

  final String name;
  final String serviceName;
  final double? rating;
  final int? reviewCount;
  final int? completedJobs;
  final String? priceLabel;
  final String? availability;
  final bool? isVerified;
}

class ProviderCard extends StatelessWidget {
  const ProviderCard({required this.model, super.key, this.onTap});

  final ProviderCardModel model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasRating =
        model.rating != null &&
        model.reviewCount != null &&
        model.reviewCount! > 0;
    return Semantics(
      button: onTap != null,
      label: '${model.name}, ${model.serviceName}',
      child: Material(
        color: OraColors.navyElevated,
        borderRadius: BorderRadius.circular(OraRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(OraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: OraColors.infoMuted,
                      child: Icon(Icons.person_outline, color: OraColors.info),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            model.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          Text(
                            model.serviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (model.isVerified != null)
                      Icon(
                        model.isVerified!
                            ? Icons.verified_rounded
                            : Icons.verified_outlined,
                        color: model.isVerified!
                            ? OraColors.info
                            : OraColors.textMuted,
                        semanticLabel: model.isVerified!
                            ? 'Verified'
                            : 'Not verified',
                      ),
                  ],
                ),
                if (hasRating ||
                    model.completedJobs != null ||
                    model.priceLabel != null ||
                    model.availability != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Wrap(
                    spacing: OraSpacing.sm,
                    runSpacing: OraSpacing.xs,
                    children: [
                      if (hasRating)
                        _ProviderMetric(
                          icon: Icons.star_rounded,
                          label:
                              '${model.rating!.toStringAsFixed(1)} · '
                              '${model.reviewCount} reviews',
                        ),
                      if (model.completedJobs != null)
                        _ProviderMetric(
                          icon: Icons.check_circle_outline_rounded,
                          label: '${model.completedJobs} jobs',
                        ),
                      if (model.priceLabel != null)
                        _ProviderMetric(
                          icon: Icons.payments_outlined,
                          label: model.priceLabel!,
                        ),
                      if (model.availability != null)
                        _ProviderMetric(
                          icon: Icons.schedule_rounded,
                          label: model.availability!,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderMetric extends StatelessWidget {
  const _ProviderMetric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: OraColors.textMuted),
        const SizedBox(width: OraSpacing.xxs),
        Text(label, style: OraTypography.caption(OraColors.textSecondary)),
      ],
    );
  }
}
