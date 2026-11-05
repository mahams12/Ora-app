import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../../super_app/presentation/widgets/ora_module_grid.dart';
import '../../../super_app/presentation/widgets/saved_places_section.dart';
import '../view_models/home_view_model.dart';

/// Authenticated passenger Home — matches the Ora HTML prototype shell.
class PassengerHomeView extends StatelessWidget {
  const PassengerHomeView({
    required this.state,
    required this.onOpenDrawer,
    required this.onRetryProfile,
    required this.onRequestRideEntry,
    required this.onOpenProfile,
    required this.onOpenRides,
    required this.onSwitchToDriver,
    required this.onUnavailableFeature,
    super.key,
  });

  final HomeUiState state;
  final VoidCallback onOpenDrawer;
  final VoidCallback onRetryProfile;
  final void Function(String? categoryId, {String? serviceType})
      onRequestRideEntry;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRides;
  final VoidCallback onSwitchToDriver;
  final ValueChanged<String> onUnavailableFeature;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    if (state.loadStatus == HomeLoadStatus.loading &&
        state.displayName == null) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading your home…'),
      );
    }

    if (state.loadStatus == HomeLoadStatus.error &&
        state.displayName == null) {
      return OraErrorState(
        title: 'Home unavailable',
        message: state.loadError ?? 'Something went wrong.',
        onRetry: onRetryProfile,
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _HomeHeroHeader(
            state: state,
            onOpenDrawer: onOpenDrawer,
            onOpenProfile: onOpenProfile,
            onSearchTap: () => onRequestRideEntry(null),
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
              _PromoCard(
                onTap: () => onRequestRideEntry(
                  null,
                  serviceType: 'intercity',
                ),
              ),
              const SizedBox(height: OraSpacing.md),
              OraCard(
                onTap: onSwitchToDriver,
                padding: const EdgeInsets.all(OraSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: OraColors.navy,
                        borderRadius: BorderRadius.circular(OraRadius.sm),
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        color: OraColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Earn on ${AppConstants.appName}',
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Passenger & driver — switch anytime',
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
              const OraSectionHeader(title: 'Explore ORA'),
              const SizedBox(height: OraSpacing.sm),
              const OraModuleGrid(),
              const SizedBox(height: OraSpacing.lg),
              SavedPlacesSection(
                onUnavailable: onUnavailableFeature,
                onSavedPlaceTap: () => onRequestRideEntry(null),
              ),
              const SizedBox(height: OraSpacing.lg),
              const OraSectionHeader(title: 'Quick actions'),
              const SizedBox(height: OraSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionTile(
                      icon: Icons.history_rounded,
                      label: 'My rides',
                      color: OraColors.info,
                      onTap: onOpenRides,
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickActionTile(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Wallet',
                      color: OraColors.tealBright,
                      onTap: () => onUnavailableFeature('Wallet'),
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickActionTile(
                      icon: Icons.shield_rounded,
                      label: 'Safety',
                      color: OraColors.goldSoft,
                      onTap: () => onUnavailableFeature('Safety centre'),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HomeHeroHeader extends StatelessWidget {
  const _HomeHeroHeader({
    required this.state,
    required this.onOpenDrawer,
    required this.onOpenProfile,
    required this.onSearchTap,
  });

  final HomeUiState state;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenProfile;
  final VoidCallback onSearchTap;

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
          colors: [OraColors.navy, OraColors.navyElevated],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Menu',
                  onPressed: onOpenDrawer,
                  icon: const Icon(Icons.menu_rounded),
                  color: OraColors.textPrimary,
                ),
                Expanded(
                  child: Text(
                    AppConstants.appName,
                    textAlign: TextAlign.center,
                    style: OraTypography.title(OraColors.textPrimary).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
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
                      gradient: LinearGradient(
                        colors: [OraColors.gold, OraColors.goldDeep],
                      ),
                    ),
                    child: Text(
                      state.avatarInitials,
                      style: OraTypography.label(
                        OraColors.primaryForeground,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: OraSpacing.md),
            Material(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(OraRadius.lg),
              child: InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(OraRadius.lg),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OraSpacing.md,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(OraRadius.lg),
                    border: Border.all(color: const Color(0x1FFFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: OraColors.primaryMuted,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: OraColors.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: OraSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Where are you headed?',
                              style: OraTypography.bodyEmphasis(
                                OraColors.textPrimary,
                              ).copyWith(fontSize: 13.5),
                            ),
                            Text(
                              'Set pickup & destination',
                              style: OraTypography.caption(
                                const Color(0xFFB9BDD1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                OraColors.navy,
                OraColors.navyElevated,
                Color(0xFF1B75AE),
              ],
              stops: [0, 0.55, 1],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOW AVAILABLE',
                style: OraTypography.sectionTitle(OraColors.goldSoft),
              ),
              const SizedBox(height: 4),
              Text(
                'Intercity trips across Pakistan cities',
                style: OraTypography.title(OraColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OraRadius.lg),
            border: Border.all(color: OraColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
