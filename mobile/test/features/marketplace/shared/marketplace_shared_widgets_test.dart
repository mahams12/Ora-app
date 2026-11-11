import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/subcategory_photo_card.dart';
import 'package:ora/features/marketplace/shared/widgets/illustrated_category_card.dart';
import 'package:ora/features/marketplace/shared/widgets/marketplace_empty_state.dart';
import 'package:ora/features/marketplace/shared/widgets/marketplace_search_field.dart';
import 'package:ora/features/marketplace/shared/widgets/provider_card.dart';
import 'package:ora/features/marketplace/shared/widgets/rental_listing_card.dart';
import 'package:ora/features/marketplace/shared/widgets/status_pill.dart';

Widget _app(Widget child) => MaterialApp(
  theme: OraTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('search field debounces text entry by 250ms', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(
      _app(MarketplaceSearchField(onChanged: values.add)),
    );

    await tester.enterText(find.byType(TextField), 'plumbing');
    await tester.pump(const Duration(milliseconds: 249));
    expect(values, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(values, ['plumbing']);
  });

  testWidgets('illustrated category exposes its action and count', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _app(
        IllustratedCategoryCard(
          imageAsset: 'assets/marketplace/modules/services.webp',
          title: 'Sample category',
          countLine: '3 services',
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('Sample category'), findsOneWidget);
    expect(find.text('3 services'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(IllustratedCategoryCard)),
      matchesSemantics(
        label: 'Sample category, 3 services',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Sample category'));
    expect(tapped, isTrue);
  });

  testWidgets('subcategory photo uses a neutral fallback when unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 168,
          height: 124,
          child: SubcategoryPhotoCard(
            subcategory: ServiceSubcategory(
              id: 'missing_subcategory',
              name: 'Fallback service',
              keywords: [],
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fallback service'), findsOneWidget);
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, hasLength(1));
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status pills show each honest state', (tester) async {
    await tester.pumpWidget(
      _app(
        const Wrap(
          children: [
            StatusPill.quotation(),
            StatusPill.comingSoon(),
            StatusPill.notActive(),
          ],
        ),
      ),
    );

    expect(find.text('Quotation'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Not active'), findsOneWidget);
  });

  testWidgets('empty state delegates its honest message', (tester) async {
    await tester.pumpWidget(
      _app(
        const MarketplaceEmptyState(
          title: 'No providers yet',
          message: 'Verified providers are joining ORA soon',
        ),
      ),
    );

    expect(find.text('No providers yet'), findsOneWidget);
    expect(
      find.text('Verified providers are joining ORA soon'),
      findsOneWidget,
    );
  });

  testWidgets('provider card hides optional and unrated metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ProviderCard(
          model: ServiceProviderSummary(
            name: 'Test provider',
            specialization: 'Test specialization',
            rating: 4.9,
            reviewCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('Test provider'), findsOneWidget);
    expect(find.text('Test specialization'), findsOneWidget);
    expect(find.text('Rating'), findsNothing);
    expect(find.text('Total jobs'), findsNothing);
    expect(find.text('Rate'), findsNothing);
    expect(find.textContaining('★'), findsNothing);
  });

  testWidgets('provider card hides metrics when optional values are null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ProviderCard(
          model: ServiceProviderSummary(
            name: 'Test provider',
            specialization: 'Test specialization',
          ),
        ),
      ),
    );

    expect(find.text('Rating'), findsNothing);
    expect(find.text('Total jobs'), findsNothing);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('provider card renders supplied verified metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ProviderCard(
          model: ServiceProviderSummary(
            name: 'Test provider',
            specialization: 'Residential plumber',
            rating: 4.5,
            reviewCount: 6,
            verifiedJobCount: 22,
            rate: 'Rs 1,500/hr',
            isVerified: true,
          ),
        ),
      ),
    );

    expect(find.text('Test provider'), findsOneWidget);
    expect(find.text('Residential plumber'), findsOneWidget);
    expect(find.text('★ 4.5'), findsOneWidget);
    expect(find.text('Total jobs'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('Rs 1,500/hr'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('provider card fits compact and large phone widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    for (final size in [const Size(320, 640), const Size(430, 932)]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        _app(
          const ProviderCard(
            model: ServiceProviderSummary(
              name: 'Test provider',
              specialization: 'Residential plumber',
              rating: 4.5,
              reviewCount: 6,
              verifiedJobCount: 22,
              rate: 'Rs 1,500/hr',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'ProviderCard at $size');
    }
  });

  testWidgets('rental listing hides absent data and zero-review rating', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const RentalListingCard(
          model: RentalListingCardModel(
            title: 'Preview sample rental',
            rating: 4.8,
            reviewCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('Preview sample rental'), findsOneWidget);
    expect(find.textContaining('reviews'), findsNothing);
    expect(find.textContaining('Verified'), findsNothing);
    expect(find.textContaining('per night'), findsNothing);
  });

  testWidgets('rental listing renders supplied optional fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const RentalListingCard(
          model: RentalListingCardModel(
            title: 'Preview sample rental',
            location: 'Preview sample location',
            rating: 4.5,
            reviewCount: 12,
            priceLabel: 'Preview nightly rate',
            availability: 'Preview availability',
            isVerified: true,
          ),
        ),
      ),
    );

    expect(find.text('Preview sample rental'), findsOneWidget);
    expect(find.text('Preview sample location'), findsOneWidget);
    expect(find.textContaining('12 reviews'), findsOneWidget);
    expect(find.text('Preview nightly rate'), findsOneWidget);
    expect(find.text('Preview availability'), findsOneWidget);
    expect(find.text('Verified host'), findsOneWidget);
  });
}
