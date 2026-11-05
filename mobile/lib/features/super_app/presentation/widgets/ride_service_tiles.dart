import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../core/constants/app_constants.dart';

class RideServiceTiles extends StatelessWidget {
  const RideServiceTiles({
    required this.onCityRides,
    required this.onIntercity,
    required this.onCourier,
    required this.onMove,
    this.courierStatusLabel,
    this.moveStatusLabel,
    super.key,
  });

  final VoidCallback onCityRides;
  final VoidCallback onIntercity;
  final VoidCallback onCourier;
  final VoidCallback onMove;
  final String? courierStatusLabel;
  final String? moveStatusLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: RideServiceTile(
                title: 'City rides',
                subtitle: 'Zip to Premium',
                imageAsset: AppConstants.serviceCityRidesAsset,
                icon: Icons.directions_car_filled_rounded,
                badgeColor: OraColors.primary,
                onTap: onCityRides,
              ),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: RideServiceTile(
                title: 'Intercity',
                subtitle: 'City to city',
                imageAsset: AppConstants.serviceIntercityAsset,
                icon: Icons.alt_route_rounded,
                badgeColor: OraColors.info,
                onTap: onIntercity,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        Row(
          children: [
            Expanded(
              child: RideServiceTile(
                title: 'Courier',
                subtitle: 'Send anything same day',
                imageAsset: AppConstants.serviceCourierAsset,
                icon: Icons.inventory_2_outlined,
                badgeColor: OraColors.accentPurple,
                statusLabel: courierStatusLabel,
                onTap: onCourier,
              ),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: RideServiceTile(
                title: 'Move',
                subtitle: 'Truck + helpers',
                imageAsset: AppConstants.serviceMoveAsset,
                icon: Icons.local_shipping_outlined,
                badgeColor: OraColors.tealBright,
                statusLabel: moveStatusLabel,
                onTap: onMove,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RideServiceTile extends StatelessWidget {
  const RideServiceTile({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.icon,
    required this.badgeColor,
    required this.onTap,
    this.statusLabel,
    super.key,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final IconData icon;
  final Color badgeColor;
  final VoidCallback onTap;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final label = statusLabel == null ? title : '$title, $statusLabel';

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.card),
          child: SizedBox(
            height: 112,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(OraRadius.card),
                color: OraColors.navyElevated,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(OraRadius.card),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x26140F05), Color(0xC7140F05)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xF2FFFFFF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(icon, size: 15, color: badgeColor),
                      ),
                    ),
                    if (statusLabel != null)
                      Positioned(
                        top: 10,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xF2FFFFFF),
                            borderRadius: BorderRadius.circular(OraRadius.pill),
                          ),
                          child: Text(
                            statusLabel!,
                            maxLines: 1,
                            style: OraTypography.caption(
                              OraColors.navy,
                            ).copyWith(fontSize: 9, height: 1),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 10,
                      bottom: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(
                              Colors.white,
                            ).copyWith(fontSize: 14, height: 1.1),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(
                              const Color(0xD9FFFFFF),
                            ).copyWith(fontSize: 10.5, height: 1.15),
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
      ),
    );
  }
}
