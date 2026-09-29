import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/home_view_model.dart';

/// Visual-only ride category (fares come from backend estimate — never fabricated).
class _RideCategory {
  const _RideCategory({
    required this.id,
    required this.name,
    required this.blurb,
    required this.icon,
  });

  final String id;
  final String name;
  final String blurb;
  final IconData icon;
}

const _categories = <_RideCategory>[
  _RideCategory(
    id: 'zip',
    name: 'Zip',
    blurb: 'Bike, fastest way',
    icon: Icons.two_wheeler_rounded,
  ),
  _RideCategory(
    id: 'trio',
    name: 'Trio',
    blurb: 'Rickshaw, 3 seats',
    icon: Icons.airport_shuttle_rounded,
  ),
  _RideCategory(
    id: 'easy',
    name: 'Easy',
    blurb: 'Compact',
    icon: Icons.directions_car_rounded,
  ),
  _RideCategory(
    id: 'breeze',
    name: 'Breeze',
    blurb: 'AC comfort car',
    icon: Icons.ac_unit_rounded,
  ),
  _RideCategory(
    id: 'executive',
    name: 'Executive',
    blurb: 'Big trunk · events',
    icon: Icons.airport_shuttle_outlined,
  ),
  _RideCategory(
    id: 'premium',
    name: 'Premium',
    blurb: 'Luxury feel ride',
    icon: Icons.workspace_premium_rounded,
  ),
];

/// Authenticated passenger Home — matches the Ora HTML prototype shell.
class PassengerHomeView extends StatefulWidget {
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
  final ValueChanged<String?> onRequestRideEntry;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRides;
  final VoidCallback onSwitchToDriver;
  final ValueChanged<String> onUnavailableFeature;

  @override
  State<PassengerHomeView> createState() => _PassengerHomeViewState();
}

class _PassengerHomeViewState extends State<PassengerHomeView> {
  String _selectedCategoryId = 'easy';

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    if (widget.state.loadStatus == HomeLoadStatus.loading &&
        widget.state.displayName == null) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading your home…'),
      );
    }

    if (widget.state.loadStatus == HomeLoadStatus.error &&
        widget.state.displayName == null) {
      return OraErrorState(
        title: 'Home unavailable',
        message: widget.state.loadError ?? 'Something went wrong.',
        onRetry: widget.onRetryProfile,
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _HomeHeroHeader(
            state: widget.state,
            onOpenDrawer: widget.onOpenDrawer,
            onOpenProfile: widget.onOpenProfile,
            onSearchTap: () => widget.onRequestRideEntry(null),
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
                onTap: () => widget.onUnavailableFeature('Intercity'),
              ),
              const SizedBox(height: OraSpacing.md),
              OraCard(
                onTap: widget.onSwitchToDriver,
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
              const OraSectionHeader(title: 'Services'),
              const SizedBox(height: OraSpacing.sm),
              _ServicesGrid(
                onCityRides: () => widget.onRequestRideEntry(null),
                onUnavailable: widget.onUnavailableFeature,
              ),
              const SizedBox(height: OraSpacing.lg),
              OraSectionHeader(
                title: 'Choose a ride',
                action: Text(
                  '${_categories.length} options',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              SizedBox(
                height: 156,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: OraSpacing.sm),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final selected = cat.id == _selectedCategoryId;
                    return _CategoryCard(
                      category: cat,
                      selected: selected,
                      onTap: () {
                        setState(() => _selectedCategoryId = cat.id);
                        widget.onRequestRideEntry(cat.id);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: OraSpacing.lg),
              OraSectionHeader(
                title: 'Saved places',
                action: GestureDetector(
                  onTap: () => widget.onUnavailableFeature('Saved places'),
                  child: Text(
                    'See all',
                    style: OraTypography.caption(OraColors.primary).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              OraCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: OraSpacing.sm,
                  vertical: OraSpacing.xxs,
                ),
                child: Column(
                  children: [
                    _SavedPlaceRow(
                      icon: Icons.home_rounded,
                      title: 'Home',
                      subtitle: 'DHA Phase 5, Lahore',
                      onTap: () => widget.onRequestRideEntry(null),
                    ),
                    const Divider(height: 1, color: OraColors.border),
                    _SavedPlaceRow(
                      icon: Icons.work_outline_rounded,
                      title: 'Work',
                      subtitle: 'MM Alam Road, Gulberg',
                      onTap: () => widget.onRequestRideEntry(null),
                    ),
                  ],
                ),
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
                      onTap: widget.onOpenRides,
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickActionTile(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'Wallet',
                      color: OraColors.tealBright,
                      onTap: () => widget.onUnavailableFeature('Wallet'),
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickActionTile(
                      icon: Icons.shield_rounded,
                      label: 'Safety',
                      color: OraColors.goldSoft,
                      onTap: () =>
                          widget.onUnavailableFeature('Safety centre'),
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
                'COMING LATER',
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

class _ServicesGrid extends StatelessWidget {
  const _ServicesGrid({required this.onCityRides, required this.onUnavailable});

  final VoidCallback onCityRides;
  final ValueChanged<String> onUnavailable;

  @override
  Widget build(BuildContext context) {
    // Fixed 112px tiles (prototype) — avoid GridView aspect-ratio overflow.
    Widget row(_ServiceImageTile a, _ServiceImageTile b) {
      return Row(
        children: [
          Expanded(child: a),
          const SizedBox(width: OraSpacing.sm),
          Expanded(child: b),
        ],
      );
    }

    return Column(
      children: [
        row(
          _ServiceImageTile(
            title: 'City rides',
            subtitle: 'Zip to Premium',
            imageAsset: AppConstants.serviceCityRidesAsset,
            icon: Icons.directions_car_filled_rounded,
            badgeColor: OraColors.primary,
            onTap: onCityRides,
          ),
          _ServiceImageTile(
            title: 'Intercity',
            subtitle: 'City to city',
            imageAsset: AppConstants.serviceIntercityAsset,
            icon: Icons.alt_route_rounded,
            badgeColor: OraColors.info,
            onTap: () => onUnavailable('Intercity'),
          ),
        ),
        const SizedBox(height: OraSpacing.sm),
        row(
          _ServiceImageTile(
            title: 'Courier',
            subtitle: 'Send anything same day',
            imageAsset: AppConstants.serviceCourierAsset,
            icon: Icons.inventory_2_outlined,
            badgeColor: OraColors.accentPurple,
            onTap: () => onUnavailable('Courier'),
          ),
          _ServiceImageTile(
            title: 'Move',
            subtitle: 'Truck + helpers',
            imageAsset: AppConstants.serviceMoveAsset,
            icon: Icons.local_shipping_outlined,
            badgeColor: OraColors.tealBright,
            onTap: () => onUnavailable('Move'),
          ),
        ),
      ],
    );
  }
}

class _ServiceImageTile extends StatelessWidget {
  const _ServiceImageTile({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.icon,
    required this.badgeColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final IconData icon;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
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
                        colors: [
                          Color(0x26140F05),
                          Color(0xC7140F05),
                        ],
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
                          style:
                              OraTypography.bodyEmphasis(Colors.white).copyWith(
                            fontSize: 14,
                            height: 1.1,
                          ),
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
    );
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(OraRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x0FFFFFFF),
              ),
              child: Icon(icon, size: 18, color: OraColors.textSecondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary)
                        .copyWith(fontSize: 13.5),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.textMuted)
                        .copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: OraColors.textMuted,
              size: 16,
            ),
          ],
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _RideCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: Material(
        color: selected ? OraColors.primaryMuted : OraColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? OraColors.primary : OraColors.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  color:
                      selected ? OraColors.primary : OraColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(height: 10),
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary)
                      .copyWith(fontSize: 13.5, height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  category.blurb,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.textMuted).copyWith(
                    fontSize: 11,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fare on request',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(OraColors.primary).copyWith(
                    fontSize: 11,
                    height: 1.1,
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

