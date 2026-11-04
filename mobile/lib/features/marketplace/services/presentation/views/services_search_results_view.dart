import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../catalogue/catalogue_search.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../widgets/services_module_navigation.dart';

class ServicesSearchResultsView extends ConsumerWidget {
  const ServicesSearchResultsView({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Service search')),
      bottomNavigationBar: const ServicesModuleNavigation(
        selected: ServicesNavigationDestination.explore,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final results = CatalogueSearch.search(data, query).services;
          if (results.isEmpty) {
            return const MarketplaceEmptyState(title: 'No matching services');
          }
          final grouped = <String, List<ServiceSearchMatch>>{};
          for (final match in results) {
            grouped.putIfAbsent(match.category.id, () => []).add(match);
          }
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    OraSpacing.md,
                    OraSpacing.md,
                    OraSpacing.md,
                    OraSpacing.sm,
                  ),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final matches = grouped.values.elementAt(index);
                    final category = matches.first.category;
                    return Card(
                      color: OraColors.navyElevated,
                      child: Padding(
                        padding: const EdgeInsets.all(OraSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.name,
                              style: OraTypography.bodyEmphasis(
                                OraColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: OraSpacing.xxs),
                            for (final match in matches)
                              _SearchResultTile(match: match),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                  OraSpacing.md,
                  0,
                  OraSpacing.md,
                  OraSpacing.md,
                ),
                padding: const EdgeInsets.all(OraSpacing.sm),
                decoration: BoxDecoration(
                  color: OraColors.infoMuted,
                  borderRadius: BorderRadius.circular(OraRadius.card),
                ),
                child: const Text(
                  'Provider search will be available once providers are '
                  'onboarded',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.match});

  final ServiceSearchMatch match;

  @override
  Widget build(BuildContext context) {
    final subcategory = match.subcategory;
    final label = subcategory?.name ?? match.category.name;
    return Semantics(
      button: true,
      label: '$label, ${match.category.name}',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          subcategory == null
              ? Icons.category_outlined
              : Icons.miscellaneous_services_outlined,
          color: OraColors.info,
        ),
        title: Text(label),
        subtitle: subcategory == null
            ? Text('${match.category.subcategories.length} services')
            : null,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: OraColors.textMuted,
        ),
        onTap: () => context.push(
          subcategory == null
              ? AppRoutes.servicesCategoryPath(match.category.id)
              : AppRoutes.servicesSubcategoryPath(
                  match.category.id,
                  subcategory.id,
                ),
        ),
      ),
    );
  }
}
