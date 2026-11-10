import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/constants/app_constants.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_models.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_provider.dart';
import 'package:ora/features/marketplace/catalogue/catalogue_search.dart';
import 'package:ora/features/marketplace/rental/domain/rental_catalogue_search.dart';
import 'package:ora/features/marketplace/services/presentation/widgets/service_subcategory_icons.dart';
import 'package:ora/features/super_app/domain/ride_type_catalogue.dart';

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
    expect(catalogue.rental.map((category) => category.name), [
      'Residential Properties',
      'Vacation & Holiday Stays',
      'Hotels & Guest Accommodation',
      'Commercial Properties',
      'Event & Function Venues',
      'Workspaces & Meeting Spaces',
      'Land & Outdoor Spaces',
      'Parking & Storage Properties',
    ]);
    expect(
      catalogue.rental.fold<int>(
        0,
        (sum, item) => sum + item.subcategories.length,
      ),
      37,
    );
    const rentalSubcategories = <String, List<String>>{
      'residential': [
        'Houses',
        'Apartments & Flats',
        'Studios',
        'Rooms & Shared Rooms',
        'Portions',
      ],
      'vacation': [
        'Villas',
        'Farmhouses',
        'Cottages & Cabins',
        'Beach Houses',
        'Resorts',
      ],
      'hotels': [
        'Hotels',
        'Motels',
        'Guest Houses',
        'Hostels',
        'Serviced Apartments',
      ],
      'commercial': [
        'Offices',
        'Shops & Retail Spaces',
        'Showrooms',
        'Factories',
        'Warehouses',
      ],
      'events': [
        'Wedding Halls',
        'Marquees',
        'Banquet Halls',
        'Party Venues',
        'Outdoor Event Spaces',
      ],
      'workspaces': [
        'Coworking Spaces',
        'Meeting Rooms',
        'Conference Halls',
        'Training Rooms',
      ],
      'land': ['Agricultural Land', 'Farm Plots', 'Gardens', 'Private Grounds'],
      'parking_storage': [
        'Private Parking',
        'Garages',
        'Storage Units',
        'Storage Facilities',
      ],
    };
    for (final category in catalogue.rental) {
      expect(
        category.subcategories.map((subcategory) => subcategory.name),
        rentalSubcategories[category.id],
      );
    }

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
    final rentalIds = [
      ...catalogue.rental.map((item) => item.id),
      ...catalogue.rental.expand(
        (item) => item.subcategories.map((subcategory) => subcategory.id),
      ),
    ];
    expect(logisticsIds.toSet(), hasLength(logisticsIds.length));
    expect(serviceIds.toSet(), hasLength(serviceIds.length));
    expect(rentalIds.toSet(), hasLength(rentalIds.length));
  });

  test(
    'catalogue provider loads the asset and every service has an icon',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loaded = await container.read(catalogueProvider.future);

      expect(loaded.logistics, hasLength(8));
      expect(loaded.services, hasLength(11));
      expect(loaded.rental, hasLength(8));
      for (final category in loaded.services) {
        for (final subcategory in category.subcategories) {
          expect(serviceSubcategoryIcons, contains(subcategory.id));
        }
      }
    },
  );

  test('catalogue and ride image paths exist', () {
    for (final category in catalogue.logistics) {
      for (final type in category.types) {
        expect(type.image, 'logistics/types/${type.id}.webp');
      }
    }
    for (final category in catalogue.rental) {
      for (final subcategory in category.subcategories) {
        expect(subcategory.image, 'rental/subs/${subcategory.id}.webp');
      }
    }
    final imagePaths = [
      ...catalogue.logistics.map((category) => category.image),
      ...catalogue.logistics.expand(
        (category) =>
            category.types.map((type) => type.image ?? category.image),
      ),
      ...catalogue.services.map((category) => category.image),
      ...catalogue.rental.map((category) => category.image),
      ...catalogue.rental.expand(
        (category) => category.subcategories.map(
          (subcategory) => subcategory.image ?? category.image,
        ),
      ),
      ...kRideTypeCatalogue.map((option) => option.image),
      AppConstants.homeIntercityRoadAsset,
    ];
    for (final imagePath in imagePaths) {
      expect(
        File(
          imagePath.startsWith('assets/')
              ? imagePath
              : 'assets/marketplace/$imagePath',
        ).existsSync(),
        isTrue,
        reason: imagePath,
      );
    }
  });

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

  test('rental search matches flats and shaadi halls locally', () {
    final flats = RentalCatalogueSearch.search(catalogue.rental, 'flat');
    expect(flats.first.id, 'apartments_flats');
    final halls = RentalCatalogueSearch.search(catalogue.rental, 'shaadi hall');
    expect(halls.first.id, 'wedding_halls');
  });
}
