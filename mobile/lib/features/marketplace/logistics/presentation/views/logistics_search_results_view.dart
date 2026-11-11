import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../catalogue/catalogue_search.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

class LogisticsSearchResultsView extends ConsumerWidget {
  const LogisticsSearchResultsView({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Vehicle search')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.logistics,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final results = CatalogueSearch.search(data, query).logistics;
          if (results.isEmpty) {
            return const MarketplaceEmptyState(
              title: 'No matching vehicle types',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(OraSpacing.md),
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: OraSpacing.xs),
            itemBuilder: (context, index) {
              final match = results[index];
              final isCategory = match.type == null;
              final label = isCategory ? match.category.name : match.name;
              return Semantics(
                button: true,
                label: '$label, ${match.category.name}',
                child: Card(
                  color: OraColors.navyElevated,
                  child: ListTile(
                    title: Text(
                      label,
                      style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    ),
                    subtitle: Text(
                      isCategory
                          ? '${match.category.types.length} vehicle types'
                          : match.category.name,
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: OraColors.textMuted,
                    ),
                    onTap: () => context.push(
                      isCategory
                          ? AppRoutes.logisticsCategoryPath(match.category.id)
                          : AppRoutes.logisticsQuotePath(
                              match.category.id,
                              match.type!.id,
                            ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
