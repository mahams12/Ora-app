import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/widgets/ora_section_header.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/provider_card.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

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
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  if (previewBannerLabel != null)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(
                          OraSpacing.md,
                          OraSpacing.md,
                          OraSpacing.md,
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
                    padding: const EdgeInsets.fromLTRB(
                      OraSpacing.md,
                      OraSpacing.md,
                      OraSpacing.md,
                      OraSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OraSectionHeader(
                            eyebrow: 'Find experts',
                            title: subcategory.name,
                          ),
                          const SizedBox(height: OraSpacing.sm),
                          const Wrap(
                            spacing: OraSpacing.xs,
                            children: [
                              FilterChip(
                                label: Text('Sort'),
                                selected: false,
                                onSelected: null,
                              ),
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
                  ),
                  if (providers.isEmpty)
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
                      padding: const EdgeInsets.fromLTRB(
                        OraSpacing.md,
                        OraSpacing.sm,
                        OraSpacing.md,
                        OraSpacing.xl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: OraSpacing.sm,
                            ),
                            child: ProviderCard(model: providers[index]),
                          );
                        }, childCount: providers.length),
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
