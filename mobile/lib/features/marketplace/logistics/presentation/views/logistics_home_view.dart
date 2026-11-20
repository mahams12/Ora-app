import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../../super_app/domain/ride_type_catalogue.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../../../super_app/presentation/widgets/ride_service_tiles.dart';
import '../../../../super_app/presentation/widgets/ride_type_photo_card.dart';
import '../../../../super_app/recent/recent_activity.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';

/// Passenger Logistics — same shape as the Rides hub: hero, service
/// tiles and a vehicle picker grid. Every card deep-links into the
/// shared ride request composer (`?service=move` / courier / buy_deliver)
/// so delivery requests flow through the same dispatch pipeline the
/// logistics partners watch — no listings, no posting.
class LogisticsHomeView extends ConsumerWidget {
  const LogisticsHomeView({super.key});

  void _openComposer(
    BuildContext context,
    WidgetRef ref, {
    required String service,
    required String recentId,
    required String title,
    required String subtitle,
    required String imageAsset,
  }) {
    final route = AppRoutes.rideRequestUri(service: service);
    ref
        .read(recentActivityProvider.notifier)
        .record(
          RecentActivity(
            kind: RecentActivityKind.logistics,
            id: recentId,
            title: title,
            subtitle: subtitle,
            imageAsset: imageAsset,
            route: route,
            atMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    unawaited(context.push<void>(route));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Logistics')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.logistics,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  OraSpacing.md,
                  padding,
                  OraSpacing.md,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _LogisticsHero(),
                      const SizedBox(height: OraSpacing.lg),
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: RideServiceTile(
                                  title: 'Move cargo',
                                  subtitle: 'Trucks, vans & freight',
                                  imageAsset:
                                      AppConstants.serviceMoveAsset,
                                  icon: Icons.local_shipping_rounded,
                                  badgeColor: OraColors.primary,
                                  onTap: () => _openComposer(
                                    context,
                                    ref,
                                    service: 'move',
                                    recentId: 'move',
                                    title: 'Move cargo',
                                    subtitle: 'Book a delivery',
                                    imageAsset:
                                        AppConstants.serviceMoveAsset,
                                  ),
                                ),
                              ),
                              const SizedBox(width: OraSpacing.sm),
                              Expanded(
                                child: RideServiceTile(
                                  title: 'Send parcel',
                                  subtitle: 'Same-day courier',
                                  imageAsset:
                                      AppConstants.serviceCourierAsset,
                                  icon: Icons.inventory_2_outlined,
                                  badgeColor: OraColors.accentPurple,
                                  onTap: () => _openComposer(
                                    context,
                                    ref,
                                    service: 'courier',
                                    recentId: 'courier',
                                    title: 'Send parcel',
                                    subtitle: 'Same-day courier',
                                    imageAsset:
                                        AppConstants.serviceCourierAsset,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: OraSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: RideServiceTile(
                                  title: 'Buy & Deliver',
                                  subtitle: 'We shop, you relax',
                                  imageAsset:
                                      'assets/marketplace/logistics/bikes.webp',
                                  icon: Icons.shopping_bag_outlined,
                                  badgeColor: OraColors.info,
                                  onTap: () => _openComposer(
                                    context,
                                    ref,
                                    service: 'buy_deliver',
                                    recentId: 'buy_deliver',
                                    title: 'Buy & Deliver',
                                    subtitle: 'We shop, you relax',
                                    imageAsset:
                                        'assets/marketplace/logistics/bikes.webp',
                                  ),
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      const OraSectionHeader(title: 'Choose a vehicle'),
                    ],
                  ),
                ),
              ),
              catalogue.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(OraSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, stackTrace) => const SliverToBoxAdapter(
                  child: MarketplaceEmptyState(
                    title: 'Catalogue unavailable',
                    message: 'Please try again later.',
                  ),
                ),
                data: (data) => SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: OraSpacing.sm,
                          mainAxisSpacing: OraSpacing.sm,
                          childAspectRatio: 1.08,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final category = data.logistics[index];
                      final image =
                          'assets/marketplace/${category.image}';
                      return RideTypePhotoCard(
                        option: RideTypeOption(
                          id: category.id,
                          name: category.name,
                          blurb: category.blurb,
                          image: image,
                          action: RideCategoryAction(category.id),
                        ),
                        onTap: () => _openComposer(
                          context,
                          ref,
                          service: 'move',
                          recentId: 'move_${category.id}',
                          title: category.name,
                          subtitle: 'Book a delivery',
                          imageAsset: image,
                        ),
                      );
                    }, childCount: data.logistics.length),
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: OraSpacing.xxl),
              ),
            ],
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
            const Positioned.fill(
              child: ColoredBox(color: OraColors.primaryMuted),
            ),
            Image.asset(
              'assets/brand/mod_logistics.webp',
              cacheWidth: 720,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Colors.transparent, Color(0x73000000)],
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
                    style: OraTypography.headline(OraColors.onPhoto),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    'Move anything, from a parcel to a container.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.body(OraColors.onPhotoMuted),
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
