import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../widgets/subcategory_photo_card.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

class ServicesCategoryView extends ConsumerWidget {
  const ServicesCategoryView({required this.categoryId, super.key});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Services')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.services,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final category = data.serviceCategory(categoryId);
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
                      OraSpacing.sm,
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
                    child: GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        0,
                        padding,
                        OraSpacing.lg,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: OraSpacing.sm,
                            mainAxisSpacing: OraSpacing.sm,
                            childAspectRatio: 168 / 124,
                          ),
                      itemCount: category.subcategories.length,
                      itemBuilder: (context, index) {
                        final subcategory = category.subcategories[index];
                        return SubcategoryPhotoCard(
                          subcategory: subcategory,
                          onTap: () => context.push(
                            AppRoutes.servicesSubcategoryPath(
                              category.id,
                              subcategory.id,
                            ),
                          ),
                        );
                      },
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
