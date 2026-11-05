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
import '../../../shared/widgets/illustrated_category_card.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../widgets/service_subcategory_icons.dart';
import '../widgets/services_module_navigation.dart';

const _suggestedSubcategoryIds = [
  'ac',
  'plumbing',
  'electrical',
  'house_cleaning',
  'makeup',
  'insect_control',
  'tutoring',
  'mobile_car_wash',
];

const _serviceCategoryIcons = <String, IconData>{
  'home_repair': Icons.home_repair_service,
  'cleaning': Icons.cleaning_services,
  'pest_control': Icons.pest_control,
  'beauty': Icons.face_retouching_natural,
  'solar_garden_property': Icons.solar_power,
  'professional': Icons.business_center,
  'education': Icons.school,
  'health': Icons.medical_services,
  'family_pet': Icons.pets,
  'automobile': Icons.car_repair,
  'daily_life': Icons.local_laundry_service,
};

class ServicesHomeView extends ConsumerStatefulWidget {
  const ServicesHomeView({super.key});

  @override
  ConsumerState<ServicesHomeView> createState() => _ServicesHomeViewState();
}

class _ServicesHomeViewState extends ConsumerState<ServicesHomeView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Services')),
      bottomNavigationBar: const ServicesModuleNavigation(
        selected: ServicesNavigationDestination.explore,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const MarketplaceEmptyState(
          title: 'Catalogue unavailable',
          message: 'Please try again later.',
        ),
        data: (data) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.md,
                      padding,
                      OraSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarketplaceSearchField(
                          hintText: 'Search services',
                          onChanged: (value) => setState(() => _query = value),
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              context.push(
                                AppRoutes.servicesSearchPath(value.trim()),
                              );
                            }
                          },
                        ),
                        if (_query.trim().isNotEmpty) ...[
                          const SizedBox(height: OraSpacing.xs),
                          Text(
                            'Press search to view matching services.',
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                        const SizedBox(height: OraSpacing.lg),
                        Text(
                          'Explore categories',
                          style: OraTypography.title(OraColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 184,
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      scrollDirection: Axis.horizontal,
                      itemCount: data.services.length,
                      itemBuilder: (context, index) {
                        final category = data.services[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: OraSpacing.sm),
                          child: IllustratedCategoryCard(
                            imageAsset: 'assets/marketplace/${category.image}',
                            title: category.name,
                            countLine:
                                '${category.subcategories.length} services',
                            width: 168,
                            height: 176,
                            badgeIcon:
                                _serviceCategoryIcons[category.id] ??
                                Icons.category_outlined,
                            onTap: () => context.push(
                              AppRoutes.servicesCategoryPath(category.id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    OraSpacing.lg,
                    padding,
                    OraSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Suggested services',
                      style: OraTypography.title(OraColors.textPrimary),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 124,
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      scrollDirection: Axis.horizontal,
                      itemCount: _suggestedSubcategoryIds.length,
                      itemBuilder: (context, index) {
                        final result = _findSubcategory(
                          data,
                          _suggestedSubcategoryIds[index],
                        );
                        if (result == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: OraSpacing.sm),
                          child: _SuggestedServiceCard(
                            category: result.$1,
                            subcategory: result.$2,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    OraSpacing.lg,
                    padding,
                    OraSpacing.sm,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Featured providers',
                      style: OraTypography.title(OraColors.textPrimary),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    0,
                    padding,
                    OraSpacing.xxl,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(OraSpacing.md),
                      decoration: BoxDecoration(
                        color: OraColors.navyElevated,
                        borderRadius: BorderRadius.circular(OraRadius.card),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: OraColors.info,
                          ),
                          SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Text(
                              'Verified providers are joining ORA soon',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

(ServiceCategory, ServiceSubcategory)? _findSubcategory(
  MarketplaceCatalogue catalogue,
  String id,
) {
  for (final category in catalogue.services) {
    for (final subcategory in category.subcategories) {
      if (subcategory.id == id) return (category, subcategory);
    }
  }
  return null;
}

class _SuggestedServiceCard extends StatelessWidget {
  const _SuggestedServiceCard({
    required this.category,
    required this.subcategory,
  });

  final ServiceCategory category;
  final ServiceSubcategory subcategory;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${subcategory.name}, ${category.name}',
      child: SizedBox(
        width: 190,
        child: Card(
          color: OraColors.navyElevated,
          child: InkWell(
            onTap: () => context.push(
              AppRoutes.servicesSubcategoryPath(category.id, subcategory.id),
            ),
            borderRadius: BorderRadius.circular(OraRadius.card),
            child: Padding(
              padding: const EdgeInsets.all(OraSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    serviceSubcategoryIcon(subcategory.id),
                    color: OraColors.primary,
                  ),
                  const SizedBox(width: OraSpacing.xs),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subcategory.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.bodyEmphasis(
                            OraColors.textPrimary,
                          ),
                        ),
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
