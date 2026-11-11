import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/demo/demo_listings.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../../../shared/widgets/provider_card.dart';
import '../widgets/subcategory_photo_card.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

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
    final demoEnabled = ref.watch(demoListingsEnabledProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Services')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.services,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const MarketplaceEmptyState(
          title: 'Catalogue unavailable',
          message: 'Please try again later.',
        ),
        data: (data) {
          final nearYouProviders = demoEnabled && data.services.isNotEmpty
              ? demoServiceProviders(
                  data.services.first.subcategories.first,
                ).take(2).toList()
              : const <ServiceProviderSummary>[];
          return Center(
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
                            onChanged: (value) =>
                                setState(() => _query = value),
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
                          const OraSectionHeader(title: 'Categories'),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 116,
                      child: ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        scrollDirection: Axis.horizontal,
                        itemCount: data.services.length,
                        itemBuilder: (context, index) {
                          final category = data.services[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              right: OraSpacing.sm,
                            ),
                            child: _ServiceCategoryTile(
                              category: category,
                              icon:
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
                  if (nearYouProviders.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        OraSpacing.lg,
                        padding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const OraSectionHeader(title: 'Near you'),
                            const SizedBox(height: OraSpacing.sm),
                            for (final provider in nearYouProviders) ...[
                              ProviderCard(
                                model: provider,
                                isSample: true,
                                onBookmark: () => showDemoBookingSheet(context),
                                onContact: () => showDemoBookingSheet(context),
                                onViewProfile: () =>
                                    showDemoBookingSheet(context),
                              ),
                              const SizedBox(height: OraSpacing.sm),
                            ],
                          ],
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      OraSpacing.lg,
                      0,
                      OraSpacing.xxl,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final category = data.services[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: OraSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: padding,
                                ),
                                child: OraSectionHeader(
                                  title: category.name,
                                  action: TextButton(
                                    onPressed: () => context.push(
                                      AppRoutes.servicesCategoryPath(
                                        category.id,
                                      ),
                                    ),
                                    child: const Text('See all'),
                                  ),
                                ),
                              ),
                              const SizedBox(height: OraSpacing.sm),
                              SizedBox(
                                height: 124,
                                child: ListView.builder(
                                  key: PageStorageKey<String>(
                                    'services-${category.id}-subcategories',
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: padding,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: category.subcategories.length,
                                  itemBuilder: (context, subcategoryIndex) {
                                    final subcategory = category
                                        .subcategories[subcategoryIndex];
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        right: OraSpacing.sm,
                                      ),
                                      child: SizedBox(
                                        width: 168,
                                        child: SubcategoryPhotoCard(
                                          subcategory: subcategory,
                                          onTap: () => context.push(
                                            AppRoutes.servicesSubcategoryPath(
                                              category.id,
                                              subcategory.id,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }, childCount: data.services.length),
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

class _ServiceCategoryTile extends StatelessWidget {
  const _ServiceCategoryTile({
    required this.category,
    required this.icon,
    required this.onTap,
  });

  final ServiceCategory category;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return Semantics(
      button: true,
      label: category.name,
      onTap: onTap,
      child: SizedBox(
        width: 96,
        height: 108,
        child: Material(
          color: OraColors.surfaceElevated,
          borderRadius: radius,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(OraSpacing.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 26, color: OraColors.primary),
                  const SizedBox(height: OraSpacing.xs),
                  Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: OraTypography.caption(OraColors.textPrimary),
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
