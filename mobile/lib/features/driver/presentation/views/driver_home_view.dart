import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';

/// Prototype-faithful driver home (teal header + map stub + quick actions).
///
/// Live capabilities are opened via callbacks; unreleased product areas use
/// [onUnavailable] — no fabricated earnings or online state.
class DriverHomeView extends StatelessWidget {
  const DriverHomeView({
    required this.displayName,
    required this.avatarInitials,
    required this.onOpenDrawer,
    required this.onOpenProfile,
    required this.onOpenRideRequests,
    required this.onOpenAssignedTrips,
    required this.onOpenDirectOffer,
    required this.onUnavailable,
    super.key,
  });

  final String displayName;
  final String avatarInitials;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRideRequests;
  final VoidCallback onOpenAssignedTrips;
  final VoidCallback onOpenDirectOffer;
  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _DriverHero(
            avatarInitials: avatarInitials,
            onOpenDrawer: onOpenDrawer,
            onOpenProfile: onOpenProfile,
            onEarningsTap: () => onUnavailable('Earnings'),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding,
            OraSpacing.md,
            padding,
            OraSpacing.xxl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const _MapStub(),
              const SizedBox(height: OraSpacing.md),
              _AvailabilityCard(
                onTap: () => onUnavailable('Go online / offline'),
              ),
              const SizedBox(height: OraSpacing.md),
              OraCard(
                onTap: onOpenRideRequests,
                padding: const EdgeInsets.all(OraSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: OraColors.secondaryMuted,
                        borderRadius: BorderRadius.circular(OraRadius.sm),
                      ),
                      child: const Icon(
                        Icons.travel_explore_rounded,
                        color: OraColors.tealBright,
                      ),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open ride requests',
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Server open-ride list for approved drivers',
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: OraColors.textMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OraSpacing.lg),
              Text(
                'Quick actions',
                style: OraTypography.title(OraColors.textPrimary).copyWith(
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: OraSpacing.sm,
                crossAxisSpacing: OraSpacing.sm,
                childAspectRatio: 1.05,
                children: [
                  _QuickTile(
                    icon: Icons.show_chart_rounded,
                    label: 'Earnings',
                    color: OraColors.tealBright,
                    onTap: () => onUnavailable('Earnings'),
                  ),
                  _QuickTile(
                    icon: Icons.route_rounded,
                    label: 'My trips',
                    color: OraColors.info,
                    onTap: onOpenAssignedTrips,
                  ),
                  _QuickTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Payouts',
                    color: OraColors.primary,
                    onTap: () => onUnavailable('Payouts'),
                  ),
                  _QuickTile(
                    icon: Icons.directions_car_filled_rounded,
                    label: 'Vehicle',
                    color: OraColors.textPrimary,
                    onTap: () => onUnavailable('Vehicle'),
                  ),
                  _QuickTile(
                    icon: Icons.bolt_rounded,
                    label: 'Bonuses',
                    color: OraColors.accentCoral,
                    onTap: () => onUnavailable('Bonuses'),
                  ),
                  _QuickTile(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Hot zones',
                    color: OraColors.goldSoft,
                    onTap: () => onUnavailable('Hot zones'),
                  ),
                  _QuickTile(
                    icon: Icons.local_offer_outlined,
                    label: 'Direct offer',
                    color: OraColors.primary,
                    onTap: onOpenDirectOffer,
                  ),
                  _QuickTile(
                    icon: Icons.star_rounded,
                    label: 'Ratings',
                    color: OraColors.primary,
                    onTap: () => onUnavailable('Ratings'),
                  ),
                  _QuickTile(
                    icon: Icons.shield_rounded,
                    label: 'Safety',
                    color: OraColors.tealBright,
                    onTap: () => onUnavailable('Driver safety'),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.md),
              Text(
                'Signed in as $displayName',
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _DriverHero extends StatelessWidget {
  const _DriverHero({
    required this.avatarInitials,
    required this.onOpenDrawer,
    required this.onOpenProfile,
    required this.onEarningsTap,
  });

  final String avatarInitials;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenProfile;
  final VoidCallback onEarningsTap;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        padding,
        OraSpacing.sm,
        padding,
        OraSpacing.lg,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OraColors.teal, OraColors.tealDeep],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Menu',
                  onPressed: onOpenDrawer,
                  icon: const Icon(Icons.menu_rounded),
                  color: Colors.white,
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1FFFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: OraColors.tealBright,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Driver',
                            style: OraTypography.caption(Colors.white).copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: onOpenProfile,
                  borderRadius: BorderRadius.circular(OraRadius.avatar),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: OraColors.gold,
                    ),
                    child: Text(
                      avatarInitials,
                      style: OraTypography.label(Colors.white).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OraSpacing.md),
            InkWell(
              onTap: onEarningsTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's earnings",
                    style: OraTypography.caption(const Color(0xFFB9BDD1)),
                  ),
                  Text(
                    '—',
                    style: OraTypography.display(Colors.white).copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Live payouts connect in a later slice · not invented',
                    style: OraTypography.caption(const Color(0xFFB9BDD1)),
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

class _MapStub extends StatelessWidget {
  const _MapStub();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OraColors.navyElevated, OraColors.surfaceStrong],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Container(height: 5, color: const Color(0x1FFFFFFF)),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 120,
            child: Container(width: 5, color: const Color(0x1FFFFFFF)),
          ),
          Positioned(
            top: 60,
            left: 150,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: OraColors.teal,
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xE612182B),
                borderRadius: BorderRadius.circular(OraRadius.sm),
              ),
              child: Text(
                'Map zones · coming later',
                style: OraTypography.caption(Colors.white).copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available for trips',
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
                Text(
                  'Go online connects in a later slice',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: OraColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: OraColors.slateMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OraColors.surfaceElevated,
      borderRadius: BorderRadius.circular(OraRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OraRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OraRadius.lg),
            border: Border.all(color: OraColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OraTypography.caption(OraColors.textPrimary).copyWith(
                  fontFamily: OraTypography.displayFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
