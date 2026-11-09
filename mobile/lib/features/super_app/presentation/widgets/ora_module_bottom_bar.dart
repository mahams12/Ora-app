import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import 'unavailable_feature_sheet.dart';

enum OraModuleDestination { rides, logistics, rental, services }

class OraModuleBottomBar extends StatelessWidget {
  const OraModuleBottomBar({this.selected, super.key});

  final OraModuleDestination? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: OraColors.navy,
          border: Border(top: BorderSide(color: OraColors.border)),
        ),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _ModuleItem(
                icon: Icons.directions_car_outlined,
                selectedIcon: Icons.directions_car_rounded,
                label: 'Rides',
                selected: selected == OraModuleDestination.rides,
                onTap: () => _replace(context, AppRoutes.ridesHub),
              ),
              _ModuleItem(
                icon: Icons.local_shipping_outlined,
                selectedIcon: Icons.local_shipping_rounded,
                label: 'Logistics',
                selected: selected == OraModuleDestination.logistics,
                onTap: () => _replace(context, AppRoutes.logistics),
              ),
              _ModuleItem(
                icon: Icons.apartment_outlined,
                selectedIcon: Icons.apartment_rounded,
                label: 'Rental',
                selected: selected == OraModuleDestination.rental,
                onTap: () => _replace(context, AppRoutes.rental),
              ),
              _ModuleItem(
                icon: Icons.handyman_outlined,
                selectedIcon: Icons.handyman_rounded,
                label: 'Services',
                selected: selected == OraModuleDestination.services,
                onTap: () => _replace(context, AppRoutes.services),
              ),
              _ModuleItem(
                icon: Icons.account_balance_wallet_outlined,
                selectedIcon: Icons.account_balance_wallet_rounded,
                label: 'Wallet',
                selected: false,
                onTap: () =>
                    unawaited(showUnavailableFeatureSheet(context, 'Wallet')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _replace(BuildContext context, String route) {
    context.pushReplacement(route);
  }
}

class _ModuleItem extends StatelessWidget {
  const _ModuleItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? OraColors.primary : OraColors.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: OraSpacing.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? selectedIcon : icon, size: 20, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(color).copyWith(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
