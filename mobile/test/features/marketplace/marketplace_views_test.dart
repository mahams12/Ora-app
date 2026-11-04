import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/app/theme/widgets/ora_button.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/logistics/presentation/views/quote_request_form.dart';
import 'package:ora/features/marketplace/rental/presentation/views/rental_filter_sheet.dart';
import 'package:ora/features/marketplace/services/presentation/views/service_providers_view.dart';
import 'package:ora/features/marketplace/services/presentation/views/services_category_view.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/service_subcategory_icons.dart';
import 'package:ora/features/marketplace/shared/widgets/provider_card.dart';
import 'package:ora/features/marketplace/shared/widgets/rental_listing_card.dart';

import 'marketplace_test_helpers.dart';

void main() {
  late MarketplaceCatalogue catalogue;
  setUpAll(() async {
    catalogue = await loadMarketplaceCatalogue();
  });

  testWidgets('Logistics catalogue navigates to a non-submitting quote form', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.logisticsCategoryPath('trucks'),
      catalogue: catalogue,
    );

    expect(find.text('Medium & Heavy Trucks'), findsOneWidget);
    expect(find.text('Quotation'), findsWidgets);
    final type = catalogue.logisticsCategory('trucks')!.types.first;
    await tester.tap(find.text(type.name).first);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(QuoteRequestForm), findsOneWidget);
    expect(find.text(type.name), findsWidgets);
    expect(find.text('Photo uploads available after setup'), findsOneWidget);
    expect(
      find.text(
        'A quotation from verified operators will appear here once requests '
        'are enabled.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nothing will be sent'), findsOneWidget);
    expect(find.text('Quotation requests open soon'), findsOneWidget);
    expect(find.text('Submit request'), findsNothing);
    expect(find.text('Request sent'), findsNothing);
    expect(tester.widget<OraButton>(find.byType(OraButton)).onPressed, isNull);

    final firstField = find.byType(TextFormField).first;
    await tester.enterText(firstField, 'Pickup');
    await tester.enterText(firstField, '');
    await tester.pump();
    expect(find.text('Pickup address is required'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.testTextInput.hide();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('quote form limits optional stops to three', (tester) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.logisticsQuotePath('trucks', 'heavy_truck'),
      catalogue: catalogue,
    );

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.text('Add optional stop'));
      await tester.pump();
    }
    expect(find.text('Optional stop 1'), findsOneWidget);
    expect(find.text('Optional stop 2'), findsOneWidget);
    expect(find.text('Optional stop 3'), findsOneWidget);
    expect(find.text('Add optional stop'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Services home and catalogue show curated content and empty states',
    (tester) async {
      await pumpMarketplaceRoute(
        tester,
        location: AppRoutes.services,
        catalogue: catalogue,
      );

      expect(find.text('Suggested services'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Featured providers'), findsOneWidget);
      expect(
        find.text('Verified providers are joining ORA soon'),
        findsOneWidget,
      );
      expect(find.byType(ProviderCard), findsNothing);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Bookings'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Popular'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('service search results group wedding services and navigate', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.servicesSearchPath('wedding'),
      catalogue: catalogue,
    );

    for (final name in [
      'Bridal & party makeup',
      'Mehndi',
      'Event planning & catering',
      'Wedding photography',
      'Tent & marquee services',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(
      find.text(
        'Provider search will be available once providers are onboarded',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Bridal & party makeup'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServiceProvidersView), findsOneWidget);
    expect(
      find.text('No verified providers for Bridal & party makeup yet'),
      findsOneWidget,
    );
  });

  testWidgets('service categories render catalogue icons for subcategories', (
    tester,
  ) async {
    final category = catalogue.serviceCategory('home_repair')!;
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.servicesCategoryPath(category.id),
      catalogue: catalogue,
    );

    expect(find.byType(ServicesCategoryView), findsOneWidget);
    final firstSubcategory = category.subcategories.first;
    expect(find.text(firstSubcategory.name), findsOneWidget);
    expect(
      find.byIcon(serviceSubcategoryIcon(firstSubcategory.id)),
      findsOneWidget,
    );
  });

  testWidgets('services bottom navigation opens honest empty states', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );

    await tester.tap(find.text('Bookings'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No bookings yet'), findsOneWidget);
    expect(find.textContaining('No fake'), findsNothing);

    await tester.tap(find.text('Saved').last);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No saved services yet'), findsOneWidget);
  });

  testWidgets('rental filters are local and expose all requested controls', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rental,
      catalogue: catalogue,
    );

    expect(
      find.text('No properties listed yet — verified hosts are coming soon'),
      findsOneWidget,
    );
    expect(find.byType(RentalListingCard), findsNothing);
    for (final type in [
      'Apartment',
      'House',
      'Room',
      'Villa',
      'Guest house',
      'Hotel',
    ]) {
      expect(find.text(type), findsOneWidget);
    }

    await tester.tap(find.byTooltip('Open filters'));
    await tester.pumpAndSettle();
    for (final label in [
      'City / area',
      'Property type',
      'Minimum price',
      'Maximum price',
      'Dates',
      'Guests',
    ]) {
      expect(
        find.text(label),
        label == 'Property type' ? findsWidgets : findsOneWidget,
      );
    }
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Amenities'), findsOneWidget);
    expect(find.text('Minimum rating'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    await tester.tap(find.text('Relevance'));
    await tester.pumpAndSettle();
    expect(find.text('Relevance'), findsWidgets);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marketplace screens fit compact and large phone sizes', (
    tester,
  ) async {
    addTearDown(() => resetMarketplaceTestSurface(tester));
    const sizes = [Size(320, 640), Size(430, 932)];
    final routes = [
      AppRoutes.logistics,
      AppRoutes.logisticsCategoryPath('trucks'),
      AppRoutes.logisticsQuotePath('trucks', 'heavy_truck'),
      AppRoutes.logisticsSearchPath('tow'),
      AppRoutes.services,
      AppRoutes.servicesCategoryPath('home_repair'),
      AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'),
      AppRoutes.servicesSearchPath('wedding'),
      AppRoutes.servicesBookings,
      AppRoutes.servicesSaved,
      AppRoutes.rental,
    ];

    for (final size in sizes) {
      setMarketplaceTestSurface(tester, size);
      for (final location in routes) {
        await pumpMarketplaceRoute(
          tester,
          location: location,
          catalogue: catalogue,
        );
        expect(tester.takeException(), isNull, reason: '$location at $size');
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: RentalFilterSheet(initialValue: RentalFilterState()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'rental filters at $size');
    }
  });
}
