import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

enum PassengerTab { home, rides, account }

class PassengerBottomNav extends StatelessWidget {
  const PassengerBottomNav({
    required this.current,
    required this.onSelect,
    super.key,
  });

  final PassengerTab current;
  final ValueChanged<PassengerTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: OraColors.surfaceElevated,
      elevation: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: OraColors.border)),
          color: OraColors.surfaceElevated,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            OraSpacing.sm,
            OraSpacing.xs,
            OraSpacing.sm,
            OraSpacing.xs + bottom,
          ),
          child: Row(
            children: [
              _NavItem(
                label: 'Home',
                icon: Icons.home_rounded,
                selected: current == PassengerTab.home,
                onTap: () => onSelect(PassengerTab.home),
              ),
              _NavItem(
                label: 'Rides',
                icon: Icons.receipt_long_rounded,
                selected: current == PassengerTab.rides,
                onTap: () => onSelect(PassengerTab.rides),
              ),
              _NavItem(
                label: 'Account',
                icon: Icons.person_rounded,
                selected: current == PassengerTab.account,
                onTap: () => onSelect(PassengerTab.account),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.md),
          child: AnimatedContainer(
            duration: OraMotion.select,
            curve: OraMotion.standard,
            padding: const EdgeInsets.symmetric(vertical: OraSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: OraTypography.caption(color).copyWith(
                    fontFamily: OraTypography.displayFamily,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
