import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

class RentalCategoryView extends ConsumerWidget {
  const RentalCategoryView({
    required this.categoryId,
    this.subcategoryId,
    super.key,
  });

  final String categoryId;
  final String? subcategoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = Responsive.horizontalPadding(context);
    final catalogue = ref.watch(catalogueProvider);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Rental')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.rental,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final category = data.rentalCategory(categoryId);
          if (category == null) {
            return const MarketplaceEmptyState(title: 'Category not found');
          }
          RentalSubcategory? selectedSubcategory;
          for (final item in category.subcategories) {
            if (item.id == subcategoryId) {
              selectedSubcategory = item;
              break;
            }
          }
          if (subcategoryId != null && selectedSubcategory == null) {
            return const MarketplaceEmptyState(
              title: 'Property type not found',
            );
          }
          if (selectedSubcategory != null) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  child: MarketplaceEmptyState(
                    title: 'No verified listings yet',
                    message:
                        'There are no verified ${selectedSubcategory.name.toLowerCase()} listings yet.',
                    icon: Icons.home_work_outlined,
                  ),
                ),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  OraSpacing.md,
                  padding,
                  OraSpacing.xxl,
                ),
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
                  const SizedBox(height: OraSpacing.md),
                  for (final subcategory in category.subcategories) ...[
                    Semantics(
                      button: true,
                      label: '${subcategory.name}, no verified listings yet',
                      child: Card(
                        color: OraColors.surfaceElevated,
                        child: InkWell(
                          onTap: () => context.push(
                            AppRoutes.rentalCategoryPath(
                              category.id,
                              subcategoryId: subcategory.id,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(OraRadius.card),
                          child: Padding(
                            padding: const EdgeInsets.all(OraSpacing.md),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.home_work_outlined,
                                  color: OraColors.teal,
                                ),
                                const SizedBox(width: OraSpacing.sm),
                                Expanded(
                                  child: Text(
                                    subcategory.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: OraTypography.bodyEmphasis(
                                      OraColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: OraColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: OraSpacing.xs),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
