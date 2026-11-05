import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/theme/theme.dart';
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
          model: ProviderCardModel(
            name: 'Preview sample provider',
            serviceName: 'Preview sample service',
            rating: 4.9,
            reviewCount: 0,
          ),
        ),
      ),
    );

    expect(find.text('Preview sample provider'), findsOneWidget);
    expect(find.textContaining('reviews'), findsNothing);
    expect(find.textContaining('jobs'), findsNothing);
    expect(find.textContaining('Verified'), findsNothing);
    expect(find.byIcon(Icons.payments_outlined), findsNothing);
  });

  testWidgets('provider card renders only supplied verified metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ProviderCard(
          model: ProviderCardModel(
            name: 'Preview sample provider',
            serviceName: 'Preview sample service',
            rating: 4.7,
            reviewCount: 9,
            completedJobs: 22,
            priceLabel: 'Preview rate',
            availability: 'Preview availability',
            isVerified: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('4.7'), findsOneWidget);
    expect(find.textContaining('9 reviews'), findsOneWidget);
    expect(find.text('22 jobs'), findsOneWidget);
    expect(find.text('Preview rate'), findsOneWidget);
    expect(find.text('Preview availability'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
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
