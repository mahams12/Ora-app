import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_provider.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_search.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/service_subcategory_icons.dart';

void main() {
  late MarketplaceCatalogue catalogue;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final jsonText = await rootBundle.loadString(
      'assets/marketplace/catalogue_v1.json',
    );
    catalogue = MarketplaceCatalogue.fromJson(
      jsonDecode(jsonText) as Map<String, dynamic>,
    );
  });

  test('catalogue contains the authoritative counts and unique IDs', () {
    expect(catalogue.logistics, hasLength(8));
    expect(
      catalogue.logistics.fold<int>(0, (sum, item) => sum + item.types.length),
      42,
    );
    expect(catalogue.services, hasLength(11));
    expect(
      catalogue.services.fold<int>(
        0,
        (sum, item) => sum + item.subcategories.length,
      ),
      88,
    );

    final logisticsIds = [
      ...catalogue.logistics.map((item) => item.id),
      ...catalogue.logistics.expand(
        (item) => item.types.map((type) => type.id),
      ),
    ];
    final serviceIds = [
      ...catalogue.services.map((item) => item.id),
      ...catalogue.services.expand(
        (item) => item.subcategories.map((subcategory) => subcategory.id),
      ),
    ];
    expect(logisticsIds.toSet(), hasLength(logisticsIds.length));
    expect(serviceIds.toSet(), hasLength(serviceIds.length));
  });

  test(
    'catalogue provider loads the asset and every service has an icon',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loaded = await container.read(catalogueProvider.future);

      expect(loaded.logistics, hasLength(8));
      expect(loaded.services, hasLength(11));
      for (final category in loaded.services) {
        for (final subcategory in category.subcategories) {
          expect(serviceSubcategoryIcons, contains(subcategory.id));
        }
      }
    },
  );

  test('AC gas ranks AC first', () {
    final results = CatalogueSearch.search(catalogue, 'AC gas');
    expect(results.services.first.id, 'ac');
  });

  test('pipe leakage matches plumbing', () {
    final results = CatalogueSearch.search(catalogue, 'pipe leakage');
    expect(results.services.first.id, 'plumbing');
  });

  test('wedding finds all five matching services', () {
    final ids = CatalogueSearch.search(
      catalogue,
      'wedding',
    ).services.map((item) => item.id);
    expect(
      ids,
      containsAll([
        'makeup',
        'mehndi',
        'events_catering',
        'wedding_photography',
        'tent_marquee',
      ]),
    );
  });

  test('TOW matches both logistics and services towing entries', () {
    final results = CatalogueSearch.search(catalogue, 'TOW');
    expect(
      results.logistics.map((match) => match.id),
      contains('recovery_towing'),
    );
    expect(results.services.map((match) => match.id), contains('towing'));
  });

  test('search results are capped at thirty across both modules', () {
    final results = CatalogueSearch.search(catalogue, 'a');
    expect(
      results.logistics.length + results.services.length,
      lessThanOrEqualTo(30),
    );
  });

  test('blank and nonsense searches return nothing', () {
    expect(CatalogueSearch.search(catalogue, '').isEmpty, isTrue);
    expect(CatalogueSearch.search(catalogue, 'zzzxqv').isEmpty, isTrue);
  });
}
