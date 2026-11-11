import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

class RentalListingCardModel {
  const RentalListingCardModel({
    required this.title,
    this.location,
    this.imageAsset,
    this.rating,
    this.reviewCount,
    this.priceLabel,
    this.availability,
    this.isVerified,
    this.amenities = const [],
    this.tag,
  });

  final String title;
  final String? location;
  final String? imageAsset;
  final double? rating;
  final int? reviewCount;
  final String? priceLabel;
  final String? availability;
  final bool? isVerified;
  final List<String> amenities;
  final String? tag;
}

class RentalListingCard extends StatelessWidget {
  const RentalListingCard({
    required this.model,
    super.key,
    this.onTap,
    this.onBookmark,
    this.width = 300,
    this.height = 220,
    this.horizontal = false,
    this.isSample = false,
  });

  final RentalListingCardModel model;
  final VoidCallback? onTap;
  final VoidCallback? onBookmark;
  final double width;
  final double height;
  final bool horizontal;
  final bool isSample;

  @override
  Widget build(BuildContext context) {
    final hasRating =
        model.rating != null &&
        model.reviewCount != null &&
        model.reviewCount! > 0;
    final hasInformation =
        hasRating ||
        model.location != null ||
        model.priceLabel != null ||
        model.availability != null;
    final semanticsLabel = [
      model.title,
      if (model.location != null) model.location!,
      if (hasRating)
        '${model.rating!.toStringAsFixed(1)}, ${model.reviewCount} reviews',
      if (model.priceLabel != null) model.priceLabel!,
      if (model.availability != null) model.availability!,
      if (model.isVerified != null)
        model.isVerified! ? 'Verified host' : 'Not verified',
    ].join(', ');
    final radius = BorderRadius.circular(OraRadius.card);
    if (horizontal) {
      return Semantics(
        button: onTap != null,
        label: semanticsLabel,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: _HorizontalRentalListingCard(
            model: model,
            isSample: isSample,
            onTap: onTap,
            onBookmark: onBookmark,
          ),
        ),
      );
    }
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: OraColors.navyElevated,
            borderRadius: radius,
            border: Border.fromBorderSide(OraElevation.cardBorder),
            boxShadow: OraElevation.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                excludeFromSemantics: true,
                onTap: onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onTap!();
                      },
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    if (model.imageAsset != null)
                      Image.asset(
                        model.imageAsset!,
                        cacheWidth: 900,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      )
                    else
                      const ColoredBox(color: OraColors.surfaceStrong),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            OraColors.shadow,
                            OraColors.photoScrimStrong,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: isSample
                          ? const _SampleBadge()
                          : Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: OraColors.photoChip,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.home_work_outlined,
                                size: 16,
                                color: OraColors.navy,
                              ),
                            ),
                    ),
                    if (isSample && onBookmark != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          tooltip: 'Save sample listing',
                          onPressed: onBookmark,
                          style: IconButton.styleFrom(
                            backgroundColor: OraColors.onPhotoMuted,
                            foregroundColor: OraColors.navy,
                          ),
                          icon: const Icon(Icons.favorite_border_rounded),
                        ),
                      ),
                    if (model.isVerified != null)
                      Positioned(
                        top: 10,
                        right: 8,
                        child: _VerifiedBadge(isVerified: model.isVerified!),
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            model.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(
                              OraColors.onPhoto,
                            ),
                          ),
                          if (model.location != null)
                            Text(
                              model.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OraTypography.caption(
                                OraColors.onPhotoMuted,
                              ),
                            ),
                          if (hasInformation)
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                if (hasRating)
                                  _CardMetric(
                                    text:
                                        '${model.rating!.toStringAsFixed(1)} · '
                                        '${model.reviewCount} reviews',
                                  ),
                                if (model.priceLabel != null)
                                  _CardMetric(text: model.priceLabel!),
                                if (model.availability != null)
                                  _CardMetric(text: model.availability!),
                              ],
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
      ),
    );
  }
}

class _HorizontalRentalListingCard extends StatelessWidget {
  const _HorizontalRentalListingCard({
    required this.model,
    required this.isSample,
    required this.onTap,
    required this.onBookmark,
  });

  final RentalListingCardModel model;
  final bool isSample;
  final VoidCallback? onTap;
  final VoidCallback? onBookmark;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: OraColors.navyElevated,
        borderRadius: radius,
        border: Border.fromBorderSide(OraElevation.cardBorder),
        boxShadow: OraElevation.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Row(
              children: [
                SizedBox(
                  width: 118,
                  height: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (model.imageAsset != null)
                        Image.asset(
                          model.imageAsset!,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        )
                      else
                        const ColoredBox(color: OraColors.surfaceStrong),
                      if (isSample)
                        const Positioned(
                          top: 7,
                          left: 6,
                          child: _SampleBadge(),
                        ),
                      if (model.rating != null)
                        Positioned(
                          left: 6,
                          bottom: 7,
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
                              '★ ${model.rating!.toStringAsFixed(1)}',
                              style: OraTypography.caption(OraColors.goldSoft),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      OraSpacing.sm,
                      OraSpacing.xs,
                      OraSpacing.xs,
                      OraSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.tag ?? 'Lahore',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.tealBright,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (onBookmark != null)
                              IconButton(
                                tooltip: 'Save sample listing',
                                onPressed: onBookmark,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 44,
                                  height: 44,
                                ),
                                icon: const Icon(
                                  Icons.favorite_border_rounded,
                                  color: OraColors.textMuted,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          model.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.bodyEmphasis(
                            OraColors.textPrimary,
                          ),
                        ),
                        if (model.location != null)
                          Text(
                            model.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        const SizedBox(height: OraSpacing.xxs),
                        if (model.amenities.isNotEmpty)
                          Text(
                            model.amenities.take(2).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(
                              OraColors.textSecondary,
                            ),
                          ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                model.priceLabel ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.goldSoft,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: 'Open sample listing',
                              onPressed: onTap,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(44, 44),
                                backgroundColor: OraColors.gold,
                                foregroundColor: OraColors.navy,
                              ),
                              icon: const Icon(Icons.arrow_forward_rounded),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SampleBadge extends StatelessWidget {
  const _SampleBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: OraColors.gold,
      borderRadius: BorderRadius.circular(OraRadius.pill),
    ),
    child: Text(
      'SAMPLE',
      style: OraTypography.caption(
        OraColors.primaryForeground,
      ).copyWith(fontSize: 9, fontWeight: FontWeight.w800),
    ),
  );
}

class _CardMetric extends StatelessWidget {
  const _CardMetric({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: OraTypography.caption(OraColors.onPhotoMuted),
  );
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.isVerified});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: OraColors.photoChip,
        borderRadius: BorderRadius.circular(OraRadius.pill),
      ),
      child: Text(
        isVerified ? 'Verified host' : 'Not verified',
        maxLines: 1,
        style: OraTypography.caption(OraColors.navy).copyWith(fontSize: 9),
      ),
    );
  }
}
