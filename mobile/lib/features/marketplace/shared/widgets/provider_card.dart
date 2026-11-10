import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

@immutable
class ServiceProviderSummary {
  const ServiceProviderSummary({
    required this.name,
    required this.specialization,
    this.photo,
    this.location,
    this.rating,
    this.reviewCount,
    this.verifiedJobCount,
    this.rate,
    this.isVerified,
  });

  final String name;
  final String specialization;
  final ImageProvider? photo;
  final String? location;
  final double? rating;
  final int? reviewCount;
  final int? verifiedJobCount;
  final String? rate;
  final bool? isVerified;
}

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    required this.model,
    super.key,
    this.onContact,
    this.onViewProfile,
    this.onBookmark,
    this.isSample = false,
  });

  final ServiceProviderSummary model;
  final VoidCallback? onContact;
  final VoidCallback? onViewProfile;
  final VoidCallback? onBookmark;
  final bool isSample;

  @override
  Widget build(BuildContext context) {
    final hasRating =
        model.rating != null &&
        model.reviewCount != null &&
        model.reviewCount! > 0;
    final metrics = <Widget>[
      if (hasRating)
        _ProviderMetric(
          label: 'Rating',
          value: '★ ${model.rating!.toStringAsFixed(1)}',
        ),
      if (model.verifiedJobCount != null)
        _ProviderMetric(
          label: 'Total jobs',
          value: model.verifiedJobCount.toString(),
        ),
      if (model.rate != null)
        _ProviderMetric(label: 'Rate', value: model.rate!),
    ];
    final initials = model.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Semantics(
      label: [
        model.name,
        model.specialization,
        if (model.location != null) model.location!,
        if (isSample) 'Sample data',
      ].join(', '),
      child: Container(
        padding: const EdgeInsets.all(OraSpacing.sm),
        decoration: BoxDecoration(
          color: OraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(OraRadius.card),
          border: Border.all(color: OraColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OraRadius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (model.photo == null)
                      ColoredBox(
                        color: OraColors.infoMuted,
                        child: Center(
                          child: Text(
                            initials,
                            style: OraTypography.title(OraColors.info),
                          ),
                        ),
                      )
                    else
                      Image(
                        image: model.photo!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            ColoredBox(
                              color: OraColors.infoMuted,
                              child: Center(
                                child: Text(
                                  initials,
                                  style: OraTypography.title(OraColors.info),
                                ),
                              ),
                            ),
                      ),
                    if (isSample)
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: OraColors.gold,
                            borderRadius: BorderRadius.circular(OraRadius.pill),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              model.specialization,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OraTypography.caption(
                                OraColors.tealBright,
                              ),
                            ),
                            if (model.location != null)
                              Text(
                                model.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: OraSpacing.xxs),
                      IconButton(
                        tooltip: 'Bookmark ${model.name}',
                        onPressed: onBookmark,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: const Icon(
                          Icons.bookmark_border_rounded,
                          size: 20,
                          color: OraColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (model.isVerified == true) ...[
                    const SizedBox(height: OraSpacing.xxs),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: OraColors.info,
                        ),
                        SizedBox(width: OraSpacing.xxs),
                        Text('Verified'),
                      ],
                    ),
                  ],
                  if (metrics.isNotEmpty) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (
                          var index = 0;
                          index < metrics.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: OraSpacing.xxs),
                          Expanded(child: metrics[index]),
                        ],
                      ],
                    ),
                  ],
                  if (onContact != null || onViewProfile != null) ...[
                    const SizedBox(height: OraSpacing.xs),
                    Wrap(
                      spacing: OraSpacing.xs,
                      children: [
                        if (onContact != null)
                          TextButton(
                            onPressed: onContact,
                            child: const Text('Contact'),
                          ),
                        if (onViewProfile != null)
                          TextButton(
                            onPressed: onViewProfile,
                            child: const Text('View profile'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderMetric extends StatelessWidget {
  const _ProviderMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OraTypography.caption(OraColors.textMuted),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: OraTypography.caption(
            OraColors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
