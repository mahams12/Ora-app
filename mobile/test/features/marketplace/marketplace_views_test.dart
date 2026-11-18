import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/rental/presentation/views/rental_filter_sheet.dart';
import 'package:ora/features/marketplace/rental/presentation/views/rental_category_view.dart';
import 'package:ora/features/marketplace/shared/widgets/illustrated_category_card.dart';
import 'package:ora/features/marketplace/services/presentation/views/service_providers_view.dart';
import 'package:ora/features/marketplace/services/presentation/views/services_category_view.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/service_subcategory_icons.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/subcategory_photo_card.dart';
import 'package:ora/features/marketplace/shared/widgets/provider_card.dart';
import 'package:ora/features/marketplace/shared/widgets/rental_listing_card.dart';
import 'package:ora/features/marketplace/logistics/presentation/views/logistics_home_view.dart';
import 'package:ora/features/super_app/presentation/widgets/ora_module_bottom_bar.dart';

import 'marketplace_test_helpers.dart';

void main() {
  late MarketplaceCatalogue catalogue;
  setUpAll(() async {
    catalogue = await loadMarketplaceCatalogue();
  });

  testWidgets('Logistics home offers the ride-style delivery flow', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.logistics,
      catalogue: catalogue,
    );

    // Same shape as the rides hub — service tiles + vehicle grid, and
    // every entry opens the shared request composer (no listings).
    expect(find.text('Move cargo'), findsOneWidget);
    expect(find.text('Send parcel'), findsOneWidget);
    expect(find.text('Buy & Deliver'), findsOneWidget);
    expect(find.text('Choose a vehicle'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(catalogue.logistics.last.name),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(catalogue.logistics.last.name), findsWidgets);
    expect(find.text('Operators near you'), findsNothing);
    expect(find.text('Quotation'), findsNothing);
    final moduleBar = tester.widget<OraModuleBottomBar>(
      find.byType(OraModuleBottomBar),
    );
    expect(moduleBar.selected, OraModuleDestination.logistics);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Services home shows categories and catalogue sections', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Suggested services'), findsNothing);
    expect(find.text('Featured providers'), findsNothing);
    expect(find.byType(SubcategoryPhotoCard), findsWidgets);
    final moduleBar = tester.widget<OraModuleBottomBar>(
      find.byType(OraModuleBottomBar),
    );
    expect(moduleBar.selected, OraModuleDestination.services);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text(catalogue.services[1].name), findsWidgets);
    expect(find.text('Verified providers are joining ORA soon'), findsNothing);
    expect(find.byType(ProviderCard), findsNothing);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Logistics'), findsOneWidget);
    expect(find.text('Rental'), findsOneWidget);
    expect(find.text('Services'), findsNWidgets(2));
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Popular'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Services home lazily exposes all 88 subcategory cards', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );
    final outer = find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final seen = <String>{};
    for (final category in catalogue.services) {
      await tester.scrollUntilVisible(
        find.text(category.name).last,
        180,
        scrollable: outer,
      );
      await tester.pumpAndSettle();
      final horizontalList = find.byKey(
        PageStorageKey<String>('services-${category.id}-subcategories'),
      );
      await tester.ensureVisible(horizontalList);
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < category.subcategories.length + 1;
        attempt++
      ) {
        for (final subcategory in category.subcategories) {
          if (find
              .descendant(
                of: horizontalList,
                matching: find.text(subcategory.name),
              )
              .evaluate()
              .isNotEmpty) {
            seen.add(subcategory.id);
          }
        }
        await tester.drag(horizontalList, const Offset(-200, 0));
        await tester.pumpAndSettle();
      }
    }
    expect(seen, hasLength(88));
  });

  testWidgets('service category See all opens its category', (tester) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );

    await tester.scrollUntilVisible(
      find.text('See all').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('See all').first);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServicesCategoryView), findsOneWidget);
  });

  testWidgets('subcategory photo card opens empty provider route', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );
    final card = find.byType(SubcategoryPhotoCard).first;
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(card);
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServiceProvidersView), findsOneWidget);
    final providers = tester.widget<ServiceProvidersView>(
      find.byType(ServiceProvidersView),
    );
    expect(providers.providers, isEmpty);
    expect(find.text('No verified providers yet'), findsOneWidget);
  });

  testWidgets('demo service providers show SAMPLE and safe Contact actions', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'),
      catalogue: catalogue,
      demoListingsEnabled: true,
    );

    expect(find.text('SAMPLE'), findsWidgets);
    await tester.ensureVisible(find.text('Contact').first);
    await tester.tap(find.text('Contact').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Booking opens soon — this is sample data, nothing is booked.'),
      findsOneWidget,
    );
  });

  testWidgets('demo-off service providers keep the honest empty state', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'),
      catalogue: catalogue,
    );

    expect(find.text('No verified providers yet'), findsOneWidget);
    expect(find.text('SAMPLE'), findsNothing);
  });

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
    expect(find.byIcon(serviceSubcategoryIcon('makeup')), findsOneWidget);
    expect(find.byIcon(Icons.miscellaneous_services_outlined), findsNothing);
    await tester.tap(find.text('Bridal & party makeup'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(ServiceProvidersView), findsOneWidget);
    expect(find.text('Find expert Bridal & party makeup'), findsOneWidget);
    expect(find.text('Bridal & party makeup'), findsWidgets);
    expect(find.text('No verified providers yet'), findsOneWidget);
  });

  testWidgets('service categories render photo cards for subcategories', (
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
    expect(find.byType(SubcategoryPhotoCard), findsWidgets);
  });

  testWidgets('module navigation has four tabs and switches modules', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
    );

    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Rental'), findsOneWidget);
    await tester.tap(find.text('Logistics'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(LogisticsHomeView), findsOneWidget);
    expect(find.text('Wallet'), findsNothing);
  });

  testWidgets('rental filters are local and expose all requested controls', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rental,
      catalogue: catalogue,
    );

    expect(find.byType(RentalListingCard), findsNothing);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(IllustratedCategoryCard), findsWidgets);

    await tester.tap(find.byTooltip('Open filters'));
    await tester.pumpAndSettle();
    final filterList = find.byType(ListView).last;
    expect(find.text('City / area'), findsOneWidget);
    expect(find.text('Property type'), findsOneWidget);
    await tester.drag(filterList, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Guests'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.drag(filterList, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Amenities'), findsOneWidget);
    expect(find.text('Minimum rating'), findsOneWidget);
    await tester.drag(filterList, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    await tester.tap(find.text('Relevance'));
    await tester.pumpAndSettle();
    expect(find.text('Relevance'), findsWidgets);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('module homes show labeled near-you samples only when enabled', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rental,
      catalogue: catalogue,
      demoListingsEnabled: true,
    );
    await tester.scrollUntilVisible(
      find.text('Places near you'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('SAMPLE'), findsWidgets);

    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.services,
      catalogue: catalogue,
      demoListingsEnabled: true,
    );
    expect(find.text('Near you'), findsOneWidget);
    expect(find.text('SAMPLE'), findsWidgets);
  });

  testWidgets('rental categories open subcategories and honest empty state', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rentalCategoryPath('residential'),
      catalogue: catalogue,
    );

    expect(find.byType(RentalCategoryView), findsOneWidget);
    expect(find.text('Residential Properties near me'), findsOneWidget);
    expect(find.text('Apartments & Flats'), findsWidgets);
    final housesId = catalogue
        .rentalCategory('residential')!
        .subcategories
        .first
        .id;
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rentalCategoryPath(
        'residential',
        subcategoryId: housesId,
      ),
      catalogue: catalogue,
    );
    await tester.scrollUntilVisible(
      find.text('Houses near you'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Houses near you'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No verified listings yet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No verified listings yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo rental listings show SAMPLE and the safe arrow sheet', (
    tester,
  ) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rentalCategoryPath('hotels'),
      catalogue: catalogue,
      demoListingsEnabled: true,
    );

    await tester.scrollUntilVisible(
      find.text('Places near you'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('SAMPLE'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byTooltip('Open sample listing').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byTooltip('Open sample listing').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Booking opens soon — this is sample data, nothing is booked.'),
      findsOneWidget,
    );
  });

  testWidgets('demo-off rental subcategory keeps photos and empty state', (
    tester,
  ) async {
    final subcategoryId = catalogue
        .rentalCategory('hotels')!
        .subcategories
        .first
        .id;
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rentalCategoryPath(
        'hotels',
        subcategoryId: subcategoryId,
      ),
      catalogue: catalogue,
    );

    await tester.scrollUntilVisible(
      find.text('No verified listings yet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No verified listings yet'), findsOneWidget);
    expect(find.text('Property types'), findsOneWidget);
    expect(find.text('SAMPLE'), findsNothing);
  });

  testWidgets('marketplace screens fit compact and large phone sizes', (
    tester,
  ) async {
    addTearDown(() => resetMarketplaceTestSurface(tester));
    const sizes = [Size(320, 640), Size(360, 640), Size(430, 932)];
    final routes = [
      AppRoutes.logistics,
      AppRoutes.services,
      AppRoutes.servicesCategoryPath('home_repair'),
      AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'),
      AppRoutes.servicesSearchPath('wedding'),
      AppRoutes.servicesBookings,
      AppRoutes.servicesSaved,
      AppRoutes.rental,
      AppRoutes.rentalCategoryPath('residential'),
    ];

    for (final size in sizes) {
      setMarketplaceTestSurface(tester, size);
      for (final location in routes) {
        await pumpMarketplaceRoute(
          tester,
          location: location,
          catalogue: catalogue,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: '$location at $size');
        await tester.pumpWidget(const SizedBox.shrink());
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: OraTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: RentalFilterSheet(initialValue: RentalFilterState()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'rental filters at $size');
    }
  });

  testWidgets('demo listing cards fit a 360px phone at text scale 1.3', (
    tester,
  ) async {
    addTearDown(() => resetMarketplaceTestSurface(tester));
    setMarketplaceTestSurface(tester, const Size(360, 740));

    final sampleRoutes = [
      AppRoutes.rentalCategoryPath('hotels'),
      AppRoutes.servicesSubcategoryPath('home_repair', 'plumbing'),
    ];
    for (final location in sampleRoutes) {
      await pumpMarketplaceRoute(
        tester,
        location: location,
        catalogue: catalogue,
        demoListingsEnabled: true,
        textScale: 1.3,
      );
      if (location.startsWith('/rental/')) {
        await tester.scrollUntilVisible(
          find.text('Places near you'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      } else {
        await tester.scrollUntilVisible(
          find.text('Find experts'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: location);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
