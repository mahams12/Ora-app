import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

class LogisticsCategoryView extends ConsumerWidget {
  const LogisticsCategoryView({required this.categoryId, super.key});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Vehicle types')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.logistics,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const MarketplaceEmptyState(
          title: 'Catalogue unavailable',
          message: 'Please try again later.',
        ),
        data: (data) {
          final category = data.logisticsCategory(categoryId);
          if (category == null) {
            return const MarketplaceEmptyState(title: 'Category not found');
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.md,
                      padding,
                      OraSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: OraTypography.headline(OraColors.textPrimary),
                        ),
                        const SizedBox(height: OraSpacing.xs),
                        Text(
                          category.blurb,
                          style: OraTypography.body(OraColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        0,
                        padding,
                        OraSpacing.xxl,
                      ),
                      itemCount: category.types.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: OraSpacing.xs),
                      itemBuilder: (context, index) => _VehicleTypeTile(
                        category: category,
                        type: category.types[index],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VehicleTypeTile extends StatelessWidget {
  const _VehicleTypeTile({required this.category, required this.type});

  final LogisticsCategory category;
  final LogisticsVehicleType type;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${type.name}, quotation',
      child: Card(
        color: OraColors.navyElevated,
        child: InkWell(
          onTap: () =>
              context.push(AppRoutes.logisticsQuotePath(category.id, type.id)),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(OraSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: OraColors.info,
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Text(
                    type.name,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                ),
                const StatusPill.quotation(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
