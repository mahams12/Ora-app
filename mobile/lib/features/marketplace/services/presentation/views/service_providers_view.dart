import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/demo/demo_listings.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/provider_card.dart';

class ServiceProvidersView extends ConsumerWidget {
  const ServiceProvidersView({
    required this.categoryId,
    required this.subcategoryId,
    this.providers = const [],
    this.previewBannerLabel,
    super.key,
  });

  final String categoryId;
  final String subcategoryId;
  final List<ServiceProviderSummary> providers;
  final String? previewBannerLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          final visibleProviders = providers.isNotEmpty
              ? providers
              : demoEnabled
              ? demoServiceProviders(subcategory)
              : const <ServiceProviderSummary>[];
          final isSample = demoEnabled;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  if (previewBannerLabel != null)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: EdgeInsets.fromLTRB(
                          padding,
                          OraSpacing.md,
                          padding,
                          0,
                        ),
                        padding: const EdgeInsets.all(OraSpacing.sm),
                        decoration: BoxDecoration(
                          color: OraColors.warning,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          previewBannerLabel!,
                          style: const TextStyle(
                            color: OraColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.md,
                      padding,
                      OraSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _ServiceProviderHero(subcategory: subcategory),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.xs,
                      padding,
                      OraSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: OraSpacing.xs,
                        runSpacing: OraSpacing.xs,
                        children: [
                          Text(
                            'Find experts',
                            style: OraTypography.title(OraColors.textPrimary),
                          ),
                          const FilterChip(
                            label: Text('Sort'),
                            selected: false,
                            onSelected: null,
                          ),
                          const FilterChip(
                            label: Text('Filter'),
                            selected: false,
                            onSelected: null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (visibleProviders.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: MarketplaceEmptyState(
                        title: 'No verified providers yet',
                        message:
                            'Verified providers for ${subcategory.name} will '
                            'appear here when available.',
                        icon: Icons.people_outline_rounded,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        OraSpacing.xs,
                        padding,
                        OraSpacing.xl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final provider = visibleProviders[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: OraSpacing.sm,
                            ),
                            child: ProviderCard(
                              model: provider,
                              isSample: isSample,
                              onBookmark: isSample
                                  ? () => showDemoBookingSheet(context)
                                  : null,
                              onContact: isSample
                                  ? () => showDemoBookingSheet(context)
                                  : null,
                              onViewProfile: isSample
                                  ? () => showDemoBookingSheet(context)
                                  : null,
                            ),
                          );
                        }, childCount: visibleProviders.length),
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

class _ServiceProviderHero extends StatelessWidget {
  const _ServiceProviderHero({required this.subcategory});

  final ServiceSubcategory subcategory;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(OraRadius.card),
      child: SizedBox(
        height: 172,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/marketplace/${subcategory.image}',
              cacheWidth: 960,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: OraColors.navyElevated),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Color(0x0012182B), Color(0xE612182B)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(OraSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find expert ${subcategory.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.headline(Colors.white),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  const Text(
                    'Local service providers',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
