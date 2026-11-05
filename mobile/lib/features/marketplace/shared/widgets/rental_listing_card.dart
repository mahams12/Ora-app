import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
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
  });

  final String title;
  final String? location;
  final String? imageAsset;
  final double? rating;
  final int? reviewCount;
  final String? priceLabel;
  final String? availability;
  final bool? isVerified;
}

class RentalListingCard extends StatelessWidget {
  const RentalListingCard({
    required this.model,
    super.key,
    this.onTap,
    this.width = 300,
    this.height = 220,
  });

  final RentalListingCardModel model;
  final VoidCallback? onTap;
  final double width;
  final double height;

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
                          colors: [Color(0x12000000), Color(0xE6000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xF2FFFFFF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.home_work_outlined,
                          size: 16,
                          color: OraColors.navy,
                        ),
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
                            style: OraTypography.bodyEmphasis(Colors.white),
                          ),
                          if (model.location != null)
                            Text(
                              model.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: OraTypography.caption(
                                const Color(0xD9FFFFFF),
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

class _CardMetric extends StatelessWidget {
  const _CardMetric({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: OraTypography.caption(const Color(0xD9FFFFFF)),
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
        color: const Color(0xF2FFFFFF),
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
