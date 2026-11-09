import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_card.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/ride_type_catalogue.dart';
import '../widgets/ora_module_bottom_bar.dart';
import '../widgets/ride_service_tiles.dart';
import '../widgets/ride_type_photo_card.dart';
import '../widgets/saved_places_section.dart';
import '../widgets/service_coming_later_sheet.dart';
import '../widgets/unavailable_feature_sheet.dart';

class RidesHubView extends StatelessWidget {
  const RidesHubView({super.key});

  @override
  Widget build(BuildContext context) {
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
                        onCityRides: () => unawaited(
                          context.push<void>(AppRoutes.rideRequestUri()),
                        ),
                        onIntercity: () => unawaited(
                          context.push<void>(
                            AppRoutes.rideRequestUri(service: 'intercity'),
                          ),
                        ),
                        onCourier: () => unawaited(
                          showServiceComingLaterSheet(context, 'Courier'),
                        ),
                        onMove: () => unawaited(
                          showServiceComingLaterSheet(context, 'Move'),
                        ),
                        courierStatusLabel: 'Coming later',
                        moveStatusLabel: 'Coming later',
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
                          unawaited(
                            context.push<void>(
                              AppRoutes.rideRequestUri(
                                category: action.categoryId,
                              ),
                            ),
                          );
                        } else if (action is RideIntercityAction) {
                          unawaited(
                            context.push<void>(
                              AppRoutes.rideRequestUri(service: 'intercity'),
                            ),
                          );
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
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  OraSpacing.lg,
                  padding,
                  OraSpacing.md,
                ),
                sliver: SliverToBoxAdapter(
                  child: SavedPlacesSection(
                    onUnavailable: (feature) => unawaited(
                      showUnavailableFeatureSheet(context, feature),
                    ),
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
                  child: Semantics(
                    button: true,
                    label: 'Logistics — trucks, cargo & freight catalogue',
                    child: OraCard(
                      onTap: () =>
                          unawaited(context.push<void>(AppRoutes.logistics)),
                      padding: const EdgeInsets.all(OraSpacing.md),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: OraColors.infoMuted,
                              borderRadius: BorderRadius.circular(OraRadius.sm),
                            ),
                            child: const Icon(
                              Icons.local_shipping_outlined,
                              color: OraColors.info,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Text(
                              'Explore Logistics',
                              style: OraTypography.bodyEmphasis(
                                OraColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: OraSpacing.xs),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: OraColors.textMuted,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
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
