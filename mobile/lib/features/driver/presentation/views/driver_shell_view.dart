import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import 'driver_assigned_rides_view.dart';
import 'driver_direct_offer_view.dart';
import 'driver_open_rides_view.dart';

enum DriverShellTab { open, assigned, offer, account }

/// Driver shell — Open rides | Assigned | Direct offer | Account.
class DriverShellView extends ConsumerStatefulWidget {
  const DriverShellView({super.key, this.initialTab = DriverShellTab.open});

  final DriverShellTab initialTab;

  @override
  ConsumerState<DriverShellView> createState() => _DriverShellViewState();
}

class _DriverShellViewState extends ConsumerState<DriverShellView> {
  late DriverShellTab _tab;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
  }

  @override
  void didUpdateWidget(DriverShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != _tab) {
      setState(() => _tab = widget.initialTab);
    }
  }

  void _selectTab(DriverShellTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(logoutUseCaseProvider)();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Driver',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Passenger home',
          onPressed: () => context.go(AppRoutes.home),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: IndexedStack(
        index: _tab.index,
        children: [
          DriverOpenRidesView(active: _tab == DriverShellTab.open),
          DriverAssignedRidesView(active: _tab == DriverShellTab.assigned),
          const DriverDirectOfferView(),
          _DriverAccountTab(
            signingOut: _signingOut,
            onSignOut: _signingOut ? null : _signOut,
            onBackPassenger: () => context.go(AppRoutes.home),
          ),
        ],
      ),
      bottomNavigationBar: _DriverBottomNav(
        current: _tab,
        onSelect: _selectTab,
      ),
    );
  }
}

class _DriverAccountTab extends StatelessWidget {
  const _DriverAccountTab({
    required this.signingOut,
    required this.onSignOut,
    required this.onBackPassenger,
  });

  final bool signingOut;
  final VoidCallback? onSignOut;
  final VoidCallback onBackPassenger;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(OraSpacing.lg),
        children: [
          Text(
            'Account',
            style: OraTypography.headline(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.md),
          Text(
            'Driver tools use your approved-driver session from /me. '
            'Open rides lists server-provided requests; assigned rides shows '
            'your jobs. Offer by known rideId remains available as a direct tool.',
            style: OraTypography.body(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.xl),
          OraButton(
            label: 'Sign out',
            variant: OraButtonVariant.outline,
            isLoading: signingOut,
            onPressed: onSignOut,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Back to passenger Home',
            variant: OraButtonVariant.ghost,
            onPressed: onBackPassenger,
          ),
        ],
      ),
    );
  }
}

class _DriverBottomNav extends StatelessWidget {
  const _DriverBottomNav({
    required this.current,
    required this.onSelect,
  });

  final DriverShellTab current;
  final ValueChanged<DriverShellTab> onSelect;

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
                label: 'Open',
                icon: Icons.travel_explore_rounded,
                selected: current == DriverShellTab.open,
                onTap: () => onSelect(DriverShellTab.open),
              ),
              _NavItem(
                label: 'Assigned',
                icon: Icons.assignment_turned_in_rounded,
                selected: current == DriverShellTab.assigned,
                onTap: () => onSelect(DriverShellTab.assigned),
              ),
              _NavItem(
                label: 'Offer',
                icon: Icons.local_offer_outlined,
                selected: current == DriverShellTab.offer,
                onTap: () => onSelect(DriverShellTab.offer),
              ),
              _NavItem(
                label: 'Account',
                icon: Icons.person_rounded,
                selected: current == DriverShellTab.account,
                onTap: () => onSelect(DriverShellTab.account),
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
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(color).copyWith(
                    fontFamily: OraTypography.displayFamily,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 11,
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
