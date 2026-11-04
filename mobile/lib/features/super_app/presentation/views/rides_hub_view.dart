import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_card.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../widgets/ride_service_tiles.dart';
import '../widgets/service_coming_later_sheet.dart';

class RidesHubView extends StatelessWidget {
  const RidesHubView({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Rides'), leading: const BackButton()),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.maxContentWidth,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                OraSpacing.md,
                padding,
                OraSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose a ride for wherever you’re headed.',
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
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
                    onMove: () =>
                        unawaited(showServiceComingLaterSheet(context, 'Move')),
                    courierStatusLabel: 'Coming later',
                    moveStatusLabel: 'Coming later',
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  Semantics(
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
                              'Logistics — trucks, cargo & freight catalogue',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
