import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_button.dart';

class RentalPropertyDetailModel {
  RentalPropertyDetailModel({
    required this.title,
    List<String> galleryAssetPaths = const [],
    this.description,
    this.address,
    List<String> amenities = const [],
    List<String> rules = const [],
    this.priceBreakdown,
    this.availability,
    this.hostName,
    this.hostVerified,
    this.rating,
    this.reviewCount,
    List<RentalPropertyReview> reviews = const [],
  }) : galleryAssetPaths = List.unmodifiable(galleryAssetPaths),
       amenities = List.unmodifiable(amenities),
       rules = List.unmodifiable(rules),
       reviews = List.unmodifiable(reviews);

  final String title;
  final List<String> galleryAssetPaths;
  final String? description;
  final String? address;
  final List<String> amenities;
  final List<String> rules;
  final RentalPriceBreakdown? priceBreakdown;
  final String? availability;
  final String? hostName;
  final bool? hostVerified;
  final double? rating;
  final int? reviewCount;
  final List<RentalPropertyReview> reviews;
}

class RentalPriceBreakdown {
  const RentalPriceBreakdown({required this.lines, required this.total});

  final List<RentalPriceLine> lines;
  final String total;
}

class RentalPriceLine {
  const RentalPriceLine({required this.label, required this.amount});

  final String label;
  final String amount;
}

class RentalPropertyReview {
  const RentalPropertyReview({
    required this.author,
    required this.comment,
    this.rating,
  });

  final String author;
  final String comment;
  final double? rating;
}

class RentalPropertyDetailView extends StatelessWidget {
  const RentalPropertyDetailView({
    required this.model,
    super.key,
    this.previewBannerLabel,
  });

  final RentalPropertyDetailModel model;
  final String? previewBannerLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        title: Text(model.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          if (previewBannerLabel != null)
            MaterialBanner(
              content: Text(previewBannerLabel!),
              leading: const Icon(Icons.info_outline_rounded),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: ListView(
              children: [
                _gallery(),
                Padding(
                  padding: const EdgeInsets.all(OraSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Description'),
                      Text(
                        model.description ??
                            'Description will appear once a verified host '
                                'lists a property.',
                        style: OraTypography.body(OraColors.textSecondary),
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Address'),
                      Text(
                        model.address ??
                            'Address will be shared once a verified listing is '
                                'available.',
                        style: OraTypography.body(OraColors.textSecondary),
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Amenities'),
                      if (model.amenities.isEmpty)
                        _placeholder(
                          'Amenities will be listed by verified hosts.',
                        )
                      else
                        Wrap(
                          spacing: OraSpacing.xs,
                          runSpacing: OraSpacing.xs,
                          children: [
                            for (final amenity in model.amenities)
                              Chip(label: Text(amenity)),
                          ],
                        ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('House rules'),
                      if (model.rules.isEmpty)
                        _placeholder(
                          'House rules will be shown with a verified listing.',
                        )
                      else
                        for (final rule in model.rules)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.rule_rounded,
                              color: OraColors.info,
                            ),
                            title: Text(rule),
                          ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Price breakdown'),
                      if (model.priceBreakdown == null)
                        _placeholder(
                          'Pricing will be shown once verified hosts are '
                          'onboarded.',
                        )
                      else ...[
                        for (final line in model.priceBreakdown!.lines)
                          _priceLine(line.label, line.amount),
                        const Divider(),
                        _priceLine('Total', model.priceBreakdown!.total),
                      ],
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Availability'),
                      _placeholder(
                        model.availability ??
                            'Availability will be shown once hosts are verified.',
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Vendor / host'),
                      if (model.hostName == null)
                        _placeholder(
                          'Host details will appear once a verified listing is '
                          'available.',
                        )
                      else
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(model.hostName!),
                          subtitle: model.hostVerified == null
                              ? null
                              : Text(
                                  model.hostVerified!
                                      ? 'Verified host'
                                      : 'Not verified',
                                ),
                        ),
                      const SizedBox(height: OraSpacing.lg),
                      _sectionTitle('Reviews'),
                      if (model.rating != null &&
                          model.reviewCount != null &&
                          model.reviewCount! > 0)
                        Text(
                          '${model.rating!.toStringAsFixed(1)} · '
                          '${model.reviewCount} reviews',
                          style: OraTypography.body(OraColors.textSecondary),
                        )
                      else
                        _placeholder(
                          'Reviews will appear once verified stays are listed.',
                        ),
                      if (model.reviews.isNotEmpty)
                        for (final review in model.reviews)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(review.author),
                            subtitle: Text(review.comment),
                            trailing: review.rating == null
                                ? null
                                : Text(review.rating!.toStringAsFixed(1)),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(OraSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Available once hosts are verified',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.xs),
            const Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: null,
                    child: Text('Contact'),
                  ),
                ),
                SizedBox(width: OraSpacing.sm),
                Expanded(child: OraButton(label: 'Request', onPressed: null)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gallery() {
    if (model.galleryAssetPaths.isEmpty) {
      return Container(
        height: 220,
        color: OraColors.navyElevated,
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 42,
              color: OraColors.textMuted,
            ),
            SizedBox(height: OraSpacing.xs),
            Text('Photos will appear with a verified listing'),
          ],
        ),
      );
    }
    return SizedBox(
      height: 220,
      child: PageView.builder(
        itemCount: model.galleryAssetPaths.length,
        itemBuilder: (context, index) => Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              model.galleryAssetPaths[index],
              cacheWidth: 900,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x12000000), Color(0xD9000000)],
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
            if (model.hostVerified != null)
              Positioned(
                top: 10,
                right: 8,
                child: _GalleryStatus(isVerified: model.hostVerified!),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
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
                  if (model.address != null)
                    Text(
                      model.address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.caption(const Color(0xD9FFFFFF)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: OraSpacing.xs),
    child: Text(text, style: OraTypography.title(OraColors.textPrimary)),
  );

  Widget _placeholder(String text) =>
      Text(text, style: OraTypography.body(OraColors.textSecondary));

  Widget _priceLine(String label, String amount) => Padding(
    padding: const EdgeInsets.symmetric(vertical: OraSpacing.xxs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(amount),
      ],
    ),
  );
}

class _GalleryStatus extends StatelessWidget {
  const _GalleryStatus({required this.isVerified});

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
        style: OraTypography.caption(OraColors.navy).copyWith(fontSize: 9),
      ),
    );
  }
}
