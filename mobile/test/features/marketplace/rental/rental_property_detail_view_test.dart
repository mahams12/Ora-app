import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/features/marketplace/rental/presentation/views/rental_property_detail_view.dart';

RentalPropertyDetailModel _previewSampleProperty() => RentalPropertyDetailModel(
  title: 'Preview sample home',
  galleryAssetPaths: const ['assets/marketplace/modules/rental.webp'],
  description: 'Preview sample description.',
  address: 'Preview sample address',
  amenities: const ['Preview sample amenity'],
  rules: const ['Preview sample rule'],
  priceBreakdown: const RentalPriceBreakdown(
    lines: [
      RentalPriceLine(
        label: 'Preview sample nightly rate',
        amount: 'Preview amount',
      ),
    ],
    total: 'Preview total',
  ),
  availability: 'Preview sample availability',
  hostName: 'Preview sample host',
  hostVerified: true,
  rating: 4.8,
  reviewCount: 3,
  reviews: const [
    RentalPropertyReview(
      author: 'Preview sample reviewer',
      comment: 'Preview sample review.',
      rating: 4.8,
    ),
  ],
);

void main() {
  testWidgets('rental detail shows model sections and disabled actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OraTheme.dark(),
        home: RentalPropertyDetailView(
          model: _previewSampleProperty(),
          previewBannerLabel: 'Preview sample · not a real property or review',
        ),
      ),
    );
    await tester.pump();

    for (final label in [
      'Preview sample · not a real property or review',
      'Description',
      'Address',
      'Amenities',
      'House rules',
      'Price breakdown',
      'Availability',
      'Vendor / host',
      'Reviews',
      'Available once hosts are verified',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('rental detail fits compact and large phone sizes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [const Size(320, 640), const Size(430, 932)]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: RentalPropertyDetailView(
            model: _previewSampleProperty(),
            previewBannerLabel: 'Preview sample',
          ),
        ),
      );
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
