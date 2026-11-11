import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../catalogue/catalogue_models.dart';
import '../widgets/provider_card.dart';

final demoListingsEnabledProvider = Provider<bool>(
  (_) => const bool.fromEnvironment('ORA_DEMO_LISTINGS'),
);

class DemoLogisticsOperator {
  const DemoLogisticsOperator({
    required this.name,
    required this.typeId,
    required this.typeName,
    required this.imageAsset,
    required this.area,
    required this.rating,
    required this.reviewCount,
    required this.distance,
    required this.eta,
    required this.price,
  });

  final String name;
  final String typeId;
  final String typeName;
  final String imageAsset;
  final String area;
  final double rating;
  final int reviewCount;
  final String distance;
  final String eta;
  final int price;

  String get priceLabel => 'PKR ${_formatRupees(price)} / trip';
}

class DemoRentalListing {
  const DemoRentalListing({
    required this.title,
    required this.subcategoryId,
    required this.area,
    required this.imageAsset,
    required this.rating,
    required this.reviewCount,
    required this.priceLabel,
    required this.amenities,
    required this.tag,
  });

  final String title;
  final String subcategoryId;
  final String area;
  final String imageAsset;
  final double rating;
  final int reviewCount;
  final String priceLabel;
  final List<String> amenities;
  final String tag;
}

List<DemoLogisticsOperator> demoLogisticsOperators(
  LogisticsCategory category, {
  String? typeId,
}) {
  final selectedTypes = typeId == null
      ? category.types
      : category.types.where((type) => type.id == typeId).toList();
  if (selectedTypes.isEmpty) return const [];

  const names = [
    'Ravi Cargo Movers',
    'Lahore Swift Logistics',
    'Mian Haulage Services',
    'Canal View Freight Co.',
  ];
  const areas = ['Gulberg', 'Johar Town', 'DHA Phase 6', 'Model Town'];
  const ratings = [4.8, 4.6, 4.9, 4.4];
  const reviewCounts = [128, 74, 53, 41];
  const distances = ['1.8 km', '2.4 km', '3.1 km', '4.2 km'];
  const etas = ['12 min', '16 min', '21 min', '28 min'];
  const prices = [2800, 3400, 4200, 5100];
  final count = typeId == null ? 4 : 3;

  return List.generate(count, (index) {
    final type = selectedTypes[index % selectedTypes.length];
    return DemoLogisticsOperator(
      name: names[index],
      typeId: type.id,
      typeName: type.name,
      imageAsset: 'assets/marketplace/${type.image ?? category.image}',
      area: areas[index],
      rating: ratings[index],
      reviewCount: reviewCounts[index],
      distance: distances[index],
      eta: etas[index],
      price: prices[index],
    );
  }, growable: false);
}

List<DemoRentalListing> demoRentalListings(
  RentalCategory category, {
  String? subId,
}) {
  final selectedSubcategories = subId == null
      ? category.subcategories
      : category.subcategories
            .where((subcategory) => subcategory.id == subId)
            .toList();
  if (selectedSubcategories.isEmpty) return const [];

  const areas = ['Gulberg III', 'DHA Phase 6', 'Model Town', 'Johar Town'];
  const ratings = [4.9, 4.7, 4.5, 4.3];
  const reviewCounts = [96, 64, 38, 27];
  const amenitySets = [
    ['Wi-Fi', 'Parking', 'Air conditioning'],
    ['Kitchen', 'Security', 'Generator'],
    ['Ensuite', 'Parking', 'Family friendly'],
    ['Wi-Fi', 'Lounge', '24/7 support'],
  ];
  final titles = _rentalTitles[category.id] ?? _defaultRentalTitles;
  final count = subId == null ? 4 : 3;

  return List.generate(count, (index) {
    final subcategory =
        selectedSubcategories[index % selectedSubcategories.length];
    return DemoRentalListing(
      title: titles[index],
      subcategoryId: subcategory.id,
      area: '${areas[index]}, Lahore',
      imageAsset: 'assets/marketplace/${subcategory.image ?? category.image}',
      rating: ratings[index],
      reviewCount: reviewCounts[index],
      priceLabel: _rentalPrice(category.id, index),
      amenities: amenitySets[index],
      tag: index == 0 ? 'Top rated' : 'Popular choice',
    );
  }, growable: false);
}

List<ServiceProviderSummary> demoServiceProviders(
  ServiceSubcategory subcategory,
) {
  const names = [
    'Hassan Ahmad Services',
    'Zara Home Experts',
    'Mian Pro Solutions',
    'Ayesha Khalid Technical',
  ];
  const areas = ['Gulberg', 'DHA Phase 5', 'Model Town', 'Bahria Town'];
  const ratings = [4.9, 4.7, 4.5, 4.3];
  const reviewCounts = [86, 59, 42, 31];
  const jobCounts = [124, 87, 63, 39];
  const rates = [
    'PKR 1,500 / visit',
    'PKR 2,000 / visit',
    'PKR 1,800 / hour',
    'PKR 2,500 / visit',
  ];

  return List.generate(
    3,
    (index) => ServiceProviderSummary(
      name: names[index],
      specialization: '${subcategory.name} specialist',
      location: '${areas[index]}, Lahore',
      photo: AssetImage('assets/marketplace/${subcategory.image}'),
      rating: ratings[index],
      reviewCount: reviewCounts[index],
      verifiedJobCount: jobCounts[index],
      rate: rates[index],
    ),
    growable: false,
  );
}

void showDemoBookingSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: OraColors.navyElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(OraRadius.sheet),
      ),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OraSpacing.lg,
          OraSpacing.md,
          OraSpacing.lg,
          OraSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sample listing',
              style: OraTypography.title(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Booking opens soon — this is sample data, nothing is booked.',
              style: OraTypography.body(OraColors.textSecondary),
            ),
            const SizedBox(height: OraSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const _rentalTitles = <String, List<String>>{
  'residential': [
    'Gulberg Family Residence',
    'DHA Garden Apartment',
    'Model Town Corner Home',
    'Johar Town Comfort Suite',
  ],
  'vacation': [
    'Canal View Garden Retreat',
    'DHA Courtyard Villa',
    'Bahria Town Farm Stay',
    'Ravi View Holiday House',
  ],
  'hotels': [
    'Pearl View Hotel',
    'Gulberg Heritage Suites',
    'Canal Garden Guest House',
    'DHA City Stay',
  ],
  'commercial': [
    'Gulberg Business Centre',
    'DHA Retail Corner',
    'Model Town Showroom',
    'Johar Town Trade Space',
  ],
  'events': [
    'Gulberg Celebration Hall',
    'DHA Garden Marquee',
    'Model Town Banquet Suite',
    'Canal View Event Lawn',
  ],
  'workspaces': [
    'Crescent Work Lounge',
    'Gulberg Meeting Studio',
    'DHA Conference Rooms',
    'Model Town Learning Space',
  ],
  'land': [
    'Canal View Farm Plot',
    'Raiwind Green Acres',
    'Bahria Garden Grounds',
    'Bedian Road Open Land',
  ],
  'parking_storage': [
    'Gulberg Secure Parking',
    'DHA Private Garage',
    'Model Town Storage Unit',
    'Johar Town Goods Store',
  ],
};

const _defaultRentalTitles = [
  'Gulberg Comfort Residence',
  'DHA Garden Property',
  'Model Town Space',
  'Johar Town Retreat',
];

String _rentalPrice(String categoryId, int index) {
  final amount = switch (categoryId) {
    'hotels' || 'vacation' => [14500, 18500, 22000, 12000][index],
    'events' => [65000, 82000, 54000, 49000][index],
    'land' => [28000, 32000, 24000, 19000][index],
    _ => [42000, 55000, 36000, 28000][index],
  };
  final unit = switch (categoryId) {
    'hotels' || 'vacation' => '/ night',
    'events' => '/ event',
    'land' => '/ kanal / month',
    _ => '/ month',
  };
  return 'PKR ${_formatRupees(amount)} $unit';
}

String _formatRupees(int amount) {
  return amount.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}
