import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../widgets/services_module_navigation.dart';

class ServiceProvidersView extends ConsumerWidget {
  const ServiceProvidersView({
    required this.categoryId,
    required this.subcategoryId,
    super.key,
  });

  final String categoryId;
  final String subcategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Providers')),
      bottomNavigationBar: const ServicesModuleNavigation(
        selected: ServicesNavigationDestination.explore,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final category = data.serviceCategory(categoryId);
          ServiceSubcategory? subcategory;
          if (category != null) {
            for (final item in category.subcategories) {
              if (item.id == subcategoryId) {
                subcategory = item;
                break;
              }
            }
          }
          if (category == null || subcategory == null) {
            return const MarketplaceEmptyState(title: 'Service not found');
          }
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(OraSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subcategory.name,
                        style: OraTypography.headline(OraColors.textPrimary),
                      ),
                      const SizedBox(height: OraSpacing.xxs),
                      Text(
                        category.name,
                        style: OraTypography.body(OraColors.textSecondary),
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const Row(
                        children: [
                          FilterChip(
                            label: Text('Sort'),
                            selected: false,
                            onSelected: null,
                          ),
                          SizedBox(width: OraSpacing.xs),
                          FilterChip(
                            label: Text('Filter'),
                            selected: false,
                            onSelected: null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: OraSpacing.xl),
                  child: MarketplaceEmptyState(
                    title: 'No verified providers for ${subcategory.name} yet',
                    message:
                        'Provider search will be available once providers are '
                        'onboarded',
                    icon: Icons.people_outline_rounded,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
