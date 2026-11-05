import 'package:flutter/material.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import 'ora_module_card.dart';

class OraModuleGrid extends StatelessWidget {
  const OraModuleGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OraModuleCard(
                title: 'Rides',
                subtitle: 'City, intercity & courier',
                imageAsset: 'assets/marketplace/modules/rides.webp',
                route: AppRoutes.ridesHub,
                accent: OraColors.gold,
                badgeIcon: Icons.directions_car,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: OraModuleCard(
                title: 'Logistics',
                subtitle: 'Trucks, cargo & freight',
                imageAsset: 'assets/marketplace/modules/logistics.webp',
                route: AppRoutes.logistics,
                accent: OraColors.info,
                badgeIcon: Icons.local_shipping,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OraModuleCard(
                title: 'Rental',
                subtitle: 'Homes & stays',
                imageAsset: 'assets/marketplace/modules/rental.webp',
                route: AppRoutes.rental,
                accent: OraColors.teal,
                badgeIcon: Icons.apartment,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: OraModuleCard(
                title: 'Services',
                subtitle: 'Experts at your door',
                imageAsset: 'assets/marketplace/modules/services.webp',
                route: AppRoutes.services,
                accent: OraColors.accentPurple,
                badgeIcon: Icons.handyman,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
