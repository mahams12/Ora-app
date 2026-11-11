import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/ride_type_catalogue.dart';
import '../../recent/recent_activity.dart';
import '../widgets/ora_module_bottom_bar.dart';
import '../widgets/ride_service_tiles.dart';
import '../widgets/ride_type_photo_card.dart';
import '../widgets/service_coming_later_sheet.dart';

class RidesHubView extends ConsumerWidget {
  const RidesHubView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Rides'), leading: const BackButton()),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.rides,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppConstants.maxContentWidth,
          ),
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
                      const _RidesHero(),
                      const SizedBox(height: OraSpacing.lg),
                      RideServiceTiles(
                        onCityRides: () {
                          final route = AppRoutes.rideRequestUri();
                          ref
                              .read(recentActivityProvider.notifier)
                              .record(
                                RecentActivity(
                                  kind: RecentActivityKind.ride,
                                  id: 'city_rides',
                                  title: 'City rides',
                                  subtitle: 'Book a ride',
                                  imageAsset:
                                      AppConstants.serviceCityRidesAsset,
                                  route: route,
                                  atMs: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                          unawaited(context.push<void>(route));
                        },
                        onIntercity: () {
                          final route = AppRoutes.rideRequestUri(
                            service: 'intercity',
                          );
                          ref
                              .read(recentActivityProvider.notifier)
                              .record(
                                RecentActivity(
                                  kind: RecentActivityKind.intercity,
                                  id: 'intercity',
                                  title: 'Intercity',
                                  subtitle: 'Book a ride',
                                  imageAsset:
                                      AppConstants.serviceIntercityAsset,
                                  route: route,
                                  atMs: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                          unawaited(context.push<void>(route));
                        },
                        onCourier: () => unawaited(
                          showServiceComingLaterSheet(context, 'Courier'),
                        ),
                        onMove: () =>
                            unawaited(context.push<void>(AppRoutes.logistics)),
                        courierStatusLabel: 'Coming later',
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      const OraSectionHeader(title: 'Choose a ride'),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: padding),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: OraSpacing.sm,
                    mainAxisSpacing: OraSpacing.sm,
                    childAspectRatio: 1.08,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final option = kRideTypeCatalogue[index];
                    return RideTypePhotoCard(
                      option: option,
                      onTap: () {
                        final action = option.action;
                        if (action is RideCategoryAction) {
                          final route = AppRoutes.rideRequestUri(
                            category: action.categoryId,
                          );
                          ref
                              .read(recentActivityProvider.notifier)
                              .record(
                                RecentActivity(
                                  kind: RecentActivityKind.ride,
                                  id: option.id,
                                  title: option.name,
                                  subtitle: 'Book a ride',
                                  imageAsset: option.image,
                                  route: route,
                                  atMs: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                          unawaited(context.push<void>(route));
                        } else if (action is RideIntercityAction) {
                          final route = AppRoutes.rideRequestUri(
                            service: 'intercity',
                          );
                          ref
                              .read(recentActivityProvider.notifier)
                              .record(
                                RecentActivity(
                                  kind: RecentActivityKind.intercity,
                                  id: 'intercity',
                                  title: option.name,
                                  subtitle: 'Book a ride',
                                  imageAsset: option.image,
                                  route: route,
                                  atMs: DateTime.now().millisecondsSinceEpoch,
                                ),
                              );
                          unawaited(context.push<void>(route));
                        } else {
                          unawaited(
                            showServiceComingLaterSheet(context, option.name),
                          );
                        }
                      },
                    );
                  }, childCount: kRideTypeCatalogue.length),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RidesHero extends StatelessWidget {
  const _RidesHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(OraRadius.card),
      child: SizedBox(
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/marketplace/modules/rides.webp',
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
                    'Move with ORA',
                    style: OraTypography.headline(Colors.white),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    'Choose a ride for wherever you’re headed.',
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
