import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';

/// Post-create bridge into the offers inbox (Slice E).
class RideRequestCreatedView extends StatelessWidget {
  const RideRequestCreatedView({
    required this.rideId,
    required this.serverState,
    super.key,
  });

  final String rideId;
  final String serverState;

  String get _maskedRideId {
    if (rideId.length <= 8) return rideId;
    return '${rideId.substring(0, 4)}…${rideId.substring(rideId.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final canOpenOffers = rideId.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: OraColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back to Home',
                  onPressed: () => context.go(AppRoutes.home),
                  icon: const Icon(Icons.close_rounded),
                  color: OraColors.textPrimary,
                ),
              ),
              const Spacer(),
              OraEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'Request created',
                message:
                    'Your ride request is on Ora\'s servers in state '
                    '"$serverState". Open offers to watch for real driver '
                    'responses — nothing is invented here.',
              ),
              const SizedBox(height: OraSpacing.lg),
              OraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server status',
                      style: OraTypography.label(OraColors.textSecondary),
                    ),
                    const SizedBox(height: OraSpacing.xxs),
                    Text(
                      serverState,
                      style: OraTypography.bodyEmphasis(OraColors.primary),
                    ),
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      'Reference $_maskedRideId',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              OraButton(
                label: 'View offers',
                onPressed: canOpenOffers
                    ? () => context.go(AppRoutes.offersInboxPath(rideId))
                    : null,
              ),
              const SizedBox(height: OraSpacing.sm),
              OraButton(
                label: 'Back to Home',
                variant: OraButtonVariant.ghost,
                onPressed: () => context.go(AppRoutes.home),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
