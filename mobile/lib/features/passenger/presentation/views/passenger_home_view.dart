import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../view_models/home_view_model.dart';

/// Visual-only ride category (no fare / no booking side effects).
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
    blurb: 'Bike',
    icon: Icons.two_wheeler_rounded,
  ),
  _RideCategory(
    id: 'trio',
    name: 'Trio',
    blurb: 'Rickshaw',
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
    blurb: 'AC comfort',
    icon: Icons.ac_unit_rounded,
  ),
  _RideCategory(
    id: 'executive',
    name: 'Executive',
    blurb: 'Larger',
    icon: Icons.airport_shuttle_outlined,
  ),
  _RideCategory(
    id: 'premium',
    name: 'Premium',
    blurb: 'Luxury feel',
    icon: Icons.workspace_premium_rounded,
  ),
];

/// Authenticated passenger Home — prototype-faithful, backend-honest.
class PassengerHomeView extends StatefulWidget {
  const PassengerHomeView({
    required this.state,
    required this.onRetryProfile,
    required this.onRequestRideEntry,
    required this.onOpenRidesTab,
    required this.onOpenAccountTab,
    required this.onUnavailableFeature,
    super.key,
  });

  final HomeUiState state;
  final VoidCallback onRetryProfile;
  final ValueChanged<String?> onRequestRideEntry;
  final VoidCallback onOpenRidesTab;
  final VoidCallback onOpenAccountTab;
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
        SliverToBoxAdapter(child: _HomeHeroHeader(state: widget.state)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding,
            OraSpacing.md,
            padding,
            OraSpacing.xxl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _DestinationSearchCard(onTap: () => widget.onRequestRideEntry(null)),
              const SizedBox(height: OraSpacing.md),
              const _InfoBanner(
                title: 'Compose a ride',
                body:
                    'Set pickup and destination next. Live pricing is not '
                    'available yet, so Ora will not send a create request.',
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
                description: 'Categories only — fares come from Ora pricing.',
                action: Text(
                  '${_categories.length} options',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              SizedBox(
                height: 148,
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
                action: Text(
                  'Soon',
                  style: OraTypography.caption(OraColors.primary),
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              OraCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No saved places yet',
                      style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    ),
                    const SizedBox(height: OraSpacing.xxs),
                    Text(
                      'Saved places are not connected in this build. '
                      'Nothing is stored locally as a stand-in.',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                    const SizedBox(height: OraSpacing.sm),
                    OraButton(
                      label: 'Notify me later',
                      variant: OraButtonVariant.ghost,
                      onPressed: () =>
                          widget.onUnavailableFeature('Saved places'),
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
                    child: _QuickAction(
                      icon: Icons.history_rounded,
                      label: 'Trips',
                      color: OraColors.info,
                      onTap: widget.onOpenRidesTab,
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallet',
                      color: OraColors.tealBright,
                      onTap: () => widget.onUnavailableFeature('Wallet'),
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.shield_outlined,
                      label: 'Safety',
                      color: OraColors.goldSoft,
                      onTap: () => widget.onUnavailableFeature('Safety'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.md),
              OraListRow(
                title: 'Account',
                subtitle: 'Sign out and preferences',
                leading: const OraIconBadge(
                  icon: Icons.person_outline_rounded,
                  backgroundColor: OraColors.primaryMuted,
                  iconColor: OraColors.primary,
                ),
                onTap: widget.onOpenAccountTab,
              ),
            ]),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 72)),
      ],
    );
  }
}

class _HomeHeroHeader extends StatelessWidget {
  const _HomeHeroHeader({required this.state});

  final HomeUiState state;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        padding,
        OraSpacing.md,
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
          bottom: Radius.circular(OraRadius.xxl),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppConstants.appName,
                    style: OraTypography.title(OraColors.textPrimary),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
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
              ],
            ),
            const SizedBox(height: OraSpacing.md),
            Text(
              'Hello, ${state.greetingName}',
              style: OraTypography.headline(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Where can Ora take you?',
              style: OraTypography.body(OraColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationSearchCard extends StatelessWidget {
  const _DestinationSearchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: OraColors.primaryMuted,
              borderRadius: BorderRadius.circular(OraRadius.sm),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: OraColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where are you headed?',
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Set pickup & destination when booking opens',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: OraColors.textMuted),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(OraSpacing.md),
      decoration: BoxDecoration(
        color: OraColors.primaryMuted,
        borderRadius: BorderRadius.circular(OraRadius.card),
        border: Border.all(color: OraColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: OraTypography.sectionTitle(OraColors.primary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(body, style: OraTypography.body(OraColors.goldSoft)),
        ],
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
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: OraSpacing.sm,
      crossAxisSpacing: OraSpacing.sm,
      childAspectRatio: 1.35,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ServiceTile(
          title: 'City rides',
          subtitle: 'Zip to Premium',
          icon: Icons.directions_car_filled_rounded,
          accent: OraColors.primary,
          onTap: onCityRides,
        ),
        _ServiceTile(
          title: 'Intercity',
          subtitle: 'Coming later',
          icon: Icons.alt_route_rounded,
          accent: OraColors.info,
          onTap: () => onUnavailable('Intercity'),
        ),
        _ServiceTile(
          title: 'Courier',
          subtitle: 'Coming later',
          icon: Icons.inventory_2_outlined,
          accent: OraColors.accentPurple,
          onTap: () => onUnavailable('Courier'),
        ),
        _ServiceTile(
          title: 'Move',
          subtitle: 'Coming later',
          icon: Icons.local_shipping_outlined,
          accent: OraColors.tealBright,
          onTap: () => onUnavailable('Move'),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(OraRadius.sm),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const Spacer(),
          Text(title, style: OraTypography.bodyEmphasis(OraColors.textPrimary)),
          Text(subtitle, style: OraTypography.caption(OraColors.textMuted)),
        ],
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
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: OraMotion.select,
      child: SizedBox(
        width: 112,
        child: OraCard(
          selected: selected,
          onTap: onTap,
          padding: const EdgeInsets.all(OraSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                category.icon,
                color: selected ? OraColors.primary : OraColors.textSecondary,
                size: 22,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                  Text(
                    category.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Price TBD',
                    style: OraTypography.caption(OraColors.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
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
    return OraCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        vertical: OraSpacing.md,
        horizontal: OraSpacing.xs,
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: OraSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: OraTypography.caption(OraColors.textPrimary).copyWith(
              fontFamily: OraTypography.displayFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
