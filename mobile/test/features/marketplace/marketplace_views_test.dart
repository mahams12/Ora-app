import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/router/routes.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/app/theme/widgets/ora_button.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/logistics/presentation/views/quote_request_form.dart';
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
    expect(find.text('Wallet'), findsOneWidget);
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

    await tester.ensureVisible(find.text('See all').first);
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
    await tester.ensureVisible(card);
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
    expect(find.text('FIND EXPERTS'), findsOneWidget);
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

  testWidgets(
    'module navigation switches modules and keeps Wallet unavailable',
    (tester) async {
      await pumpMarketplaceRoute(
        tester,
        location: AppRoutes.services,
        catalogue: catalogue,
      );

      await tester.tap(find.text('Logistics'));
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(LogisticsHomeView), findsOneWidget);

      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Wallet is planned for Ora but is not wired to the backend '
          'in this build. Nothing is faked.',
        ),
        findsOneWidget,
      );
    },
  );

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

  testWidgets('rental property listing action is coming later', (tester) async {
    await pumpMarketplaceRoute(
      tester,
      location: AppRoutes.rental,
      catalogue: catalogue,
    );
    await tester.scrollUntilVisible(
      find.text('List your property'),
      160,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('List your property'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'List your property is planned for Ora but is not wired to the backend '
        'in this build. Nothing is faked.',
      ),
      findsOneWidget,
    );
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
    expect(find.text('Residential Properties'), findsOneWidget);
    expect(find.text('Apartments & Flats'), findsOneWidget);
    await tester.tap(find.text('Houses'));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No verified listings yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marketplace screens fit compact and large phone sizes', (
    tester,
  ) async {
    addTearDown(() => resetMarketplaceTestSurface(tester));
    const sizes = [Size(320, 640), Size(360, 640), Size(430, 932)];
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
}
