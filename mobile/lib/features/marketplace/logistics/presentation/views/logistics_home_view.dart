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
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/illustrated_category_card.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';

const _logisticsCategoryIcons = <String, IconData>{
  'bikes': Icons.two_wheeler,
  'three_wheeler': Icons.electric_rickshaw,
  'pickups': Icons.local_shipping,
  'vans': Icons.airport_shuttle,
  'trucks': Icons.local_shipping,
  'trailers': Icons.rv_hookup,
  'specialized': Icons.construction,
  'freight': Icons.sailing,
};

class LogisticsHomeView extends ConsumerStatefulWidget {
  const LogisticsHomeView({super.key});

  @override
  ConsumerState<LogisticsHomeView> createState() => _LogisticsHomeViewState();
}

class _LogisticsHomeViewState extends ConsumerState<LogisticsHomeView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Logistics')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.logistics,
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
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    OraSpacing.md,
                    padding,
                    OraSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LogisticsHero(),
                        const SizedBox(height: OraSpacing.md),
                        Text(
                          'Move anything, from a parcel to a container',
                          style: OraTypography.headline(OraColors.textPrimary),
                        ),
                        const SizedBox(height: OraSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(OraSpacing.sm),
                          decoration: BoxDecoration(
                            color: OraColors.infoMuted,
                            borderRadius: BorderRadius.circular(OraRadius.card),
                            border: Border.all(
                              color: OraColors.info.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: OraColors.info,
                              ),
                              SizedBox(width: OraSpacing.xs),
                              Expanded(
                                child: Text(
                                  'Quotation requests open soon — nothing is '
                                  'booked or sent yet',
                                  style: TextStyle(
                                    color: OraColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: OraSpacing.md),
                        MarketplaceSearchField(
                          hintText: 'Search vehicle types',
                          onChanged: (value) => setState(() => _query = value),
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              context.push(
                                AppRoutes.logisticsSearchPath(value.trim()),
                              );
                            }
                          },
                        ),
                        if (_query.trim().isNotEmpty) ...[
                          const SizedBox(height: OraSpacing.xs),
                          Text(
                            'Press search to view matching vehicle types.',
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                        const SizedBox(height: OraSpacing.lg),
                        Text(
                          'Vehicle categories',
                          style: OraTypography.title(OraColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    0,
                    padding,
                    OraSpacing.lg,
                  ),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: OraSpacing.sm,
                          mainAxisSpacing: OraSpacing.sm,
                          mainAxisExtent: 184,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final category = data.logistics[index];
                      return IllustratedCategoryCard(
                        imageAsset: 'assets/marketplace/${category.image}',
                        title: category.name,
                        countLine: '${category.types.length} vehicle types',
                        badgeIcon:
                            _logisticsCategoryIcons[category.id] ??
                            Icons.category_outlined,
                        height: 184,
                        onTap: () => context.push(
                          AppRoutes.logisticsCategoryPath(category.id),
                        ),
                      );
                    }, childCount: data.logistics.length),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    0,
                    padding,
                    OraSpacing.xxl,
                  ),
                  sliver: const SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OraSectionHeader(title: 'Operators near you'),
                        SizedBox(height: OraSpacing.sm),
                        MarketplaceEmptyState(
                          title: 'No verified operators yet',
                          message:
                              'Verified logistics operators will appear here '
                              'when they are available.',
                          icon: Icons.local_shipping_outlined,
                        ),
                      ],
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

class _LogisticsHero extends StatelessWidget {
  const _LogisticsHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(OraRadius.card),
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/marketplace/modules/logistics.webp',
              cacheWidth: 720,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Color(0x000A1025), Color(0xE60A1025)],
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
                    'Logistics',
                    style: OraTypography.headline(Colors.white),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    'Move goods with a vehicle that fits.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.body(Colors.white70),
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
