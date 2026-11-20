import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../../recent/driver_recents.dart';
import '../view_models/driver_earnings_view_model.dart';
import '../view_models/driver_invites_view_model.dart';
import '../widgets/driver_ui_kit.dart';

/// Driver home — prototype screen: greeting + online pill, orange stat
/// cards, 3D quick-action tiles. Live capabilities open via callbacks;
/// unreleased product areas use [onUnavailable] — nothing is faked.
class DriverHomeView extends ConsumerStatefulWidget {
  const DriverHomeView({
    required this.displayName,
    required this.avatarInitials,
    this.avatarData,
    required this.onSwitchToPassenger,
    required this.onOpenProfile,
    required this.onOpenRideRequests,
    required this.onOpenAssignedTrips,
    required this.onOpenEarnings,
    required this.onUnavailable,
    required this.availabilityOnline,
    required this.availabilityBusy,
    required this.availabilityLoaded,
    required this.onToggleAvailability,
    this.heroAsset = 'assets/driver_tiles/driver_hero.png',
    this.requestsTileLabel = 'Open ride requests',
    this.requestsTileAsset = 'assets/marketplace/modules/rides.webp',
    this.tripsTileLabel = 'My Rides',
    this.tripsTileAsset = 'assets/marketplace/rides/premium.webp',
    this.todayTripsLabel = 'Today\'s Trips',
    this.onOpenWallet,
    super.key,
  });

  final String displayName;
  final String avatarInitials;
  final String? avatarData;
  final VoidCallback onSwitchToPassenger;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenRideRequests;
  final VoidCallback onOpenAssignedTrips;
  final VoidCallback onOpenEarnings;
  final ValueChanged<String> onUnavailable;
  final bool availabilityOnline;
  final bool availabilityBusy;
  final bool availabilityLoaded;
  final VoidCallback onToggleAvailability;

  /// Hero artwork + quick-tile copy — logistics partners reuse this view
  /// with their own imagery and delivery wording.
  final String heroAsset;
  final String requestsTileLabel;
  final String requestsTileAsset;
  final String tripsTileLabel;
  final String tripsTileAsset;
  final String todayTripsLabel;

  /// When set the Wallet tile opens the real wallet; otherwise it falls
  /// back to [onUnavailable] ('Wallet').
  final VoidCallback? onOpenWallet;

  @override
  ConsumerState<DriverHomeView> createState() => _DriverHomeViewState();
}

class _DriverHomeViewState extends ConsumerState<DriverHomeView> {
  bool _warmupRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmup());
  }

  /// Stat cards read the earnings summary and request tiles read the live
  /// invite count — warm both once so the header numbers are real.
  void _warmup() {
    if (_warmupRequested || !mounted) return;
    _warmupRequested = true;
    unawaited(ref.read(driverEarningsViewModelProvider.notifier).loadInitial());
    unawaited(ref.read(driverInvitesViewModelProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final earnings = ref.watch(driverEarningsViewModelProvider);
    final invites = ref.watch(driverInvitesViewModelProvider);
    final newRequests = invites.items.where((i) => i.isActionable).length;

    final todayFares = earnings.summary == null
        ? '—'
        : formatMinorFare(
                earnings.summary!.today.faresMinor,
                earnings.summary!.today.currency,
              ) ??
              '—';
    final todayTrips = earnings.summary == null
        ? '—'
        : '${earnings.summary!.today.rideCount}';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DriverHeroHeader(
                newRequests: newRequests,
                onBellTap: widget.onOpenRideRequests,
                heroAsset: widget.heroAsset,
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  OraSpacing.md,
                  padding,
                  OraSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: widget.onOpenProfile,
                          borderRadius: BorderRadius.circular(OraRadius.avatar),
                          child: OraAvatar(
                            initials: widget.avatarInitials,
                            avatarData: widget.avatarData,
                            size: 52,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(width: OraSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${widget.displayName} 👋',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    OraTypography.title(
                                      OraColors.textPrimary,
                                    ).copyWith(
                                      fontFamily: OraTypography.displayFamily,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                              ),
                              Text(
                                widget.availabilityOnline
                                    ? 'You\'re Online'
                                    : 'You\'re Offline',
                                style: OraTypography.caption(
                                  widget.availabilityOnline
                                      ? OraColors.successForeground
                                      : OraColors.textMuted,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        _OnlinePill(
                          isOnline: widget.availabilityOnline,
                          busy: widget.availabilityBusy,
                          loaded: widget.availabilityLoaded,
                          onTap: widget.onToggleAvailability,
                        ),
                      ],
                    ),
                    const SizedBox(height: OraSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: DriverStatCard(
                            label: 'Today\'s Earnings',
                            value: todayFares,
                            onTap: widget.onOpenEarnings,
                            floating: true,
                          ),
                        ),
                        const SizedBox(width: OraSpacing.sm),
                        Expanded(
                          child: DriverStatCard(
                            label: widget.todayTripsLabel,
                            value: todayTrips,
                            onTap: widget.onOpenAssignedTrips,
                            floating: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(padding, 0, padding, 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DriverQuickTile(
                        icon: Icons.travel_explore_rounded,
                        assetPath: widget.requestsTileAsset,
                        label: widget.requestsTileLabel,
                        badge: newRequests > 0 ? '($newRequests New)' : null,
                        onTap: widget.onOpenRideRequests,
                      ),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: DriverQuickTile(
                        icon: Icons.route_rounded,
                        assetPath: widget.tripsTileAsset,
                        label: widget.tripsTileLabel,
                        onTap: widget.onOpenAssignedTrips,
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DriverQuickTile(
                        icon: Icons.bar_chart_rounded,
                        assetPath:
                            'assets/marketplace/services/subs/accounting_tax.webp',
                        label: 'Earnings',
                        onTap: widget.onOpenEarnings,
                      ),
                    ),
                    const SizedBox(width: OraSpacing.sm),
                    Expanded(
                      child: DriverQuickTile(
                        icon: Icons.account_balance_wallet_rounded,
                        assetPath: 'assets/driver_tiles/wallet_3d.png',
                        label: 'Wallet',
                        onTap: widget.onOpenWallet ??
                            () => widget.onUnavailable('Wallet'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: OraSpacing.sm),
                _PassengerSwitchCard(onTap: widget.onSwitchToPassenger),
                const SizedBox(height: OraSpacing.sm),
                DriverRecentSection(onOpen: _openRecent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openRecent(DriverRecentDestination destination) {
    switch (destination) {
      case DriverRecentDestination.requests:
        widget.onOpenRideRequests();
      case DriverRecentDestination.bookings:
      case DriverRecentDestination.activeRide:
        widget.onOpenAssignedTrips();
      case DriverRecentDestination.earnings:
        widget.onOpenEarnings();
      case DriverRecentDestination.wallet:
        (widget.onOpenWallet ?? () => widget.onUnavailable('Wallet'))();
      case DriverRecentDestination.profile:
        widget.onOpenProfile();
    }
  }
}

/// Driver hero header — same structure as the passenger home: a warm
/// blended hero artwork covering the full top area, with the notification
/// bell floating over its top-right corner.
class _DriverHeroHeader extends StatelessWidget {
  const _DriverHeroHeader({
    required this.newRequests,
    required this.onBellTap,
    required this.heroAsset,
  });

  final int newRequests;
  final VoidCallback onBellTap;
  final String heroAsset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.8, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Image.asset(
            heroAsset,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.high,
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + OraSpacing.xs,
          right: OraSpacing.sm,
          child: OraTapScale(
            downScale: 0.9,
            child: GestureDetector(
              onTap: onBellTap,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OraColors.surfaceElevated,
                  border: Border.all(color: OraColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: OraColors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Center(
                      child: Icon(
                        Icons.notifications_rounded,
                        size: 20,
                        color: OraColors.goldSharp,
                      ),
                    ),
                    if (newRequests > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: OraColors.danger,
                          ),
                          child: Text(
                            newRequests > 9 ? '9+' : '$newRequests',
                            style: OraTypography.caption(Colors.white).copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Green "Online" pill switch — tap toggles driver availability.
class _OnlinePill extends StatelessWidget {
  const _OnlinePill({
    required this.isOnline,
    required this.busy,
    required this.loaded,
    required this.onTap,
  });

  final bool isOnline;
  final bool busy;
  final bool loaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final online = loaded && isOnline;
    return OraTapScale(
      downScale: 0.94,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            gradient: online
                ? const LinearGradient(
                    colors: [Color(0xFF34D399), Color(0xFF16A34A)],
                  )
                : null,
            color: online ? null : OraColors.disabled,
            borderRadius: BorderRadius.circular(OraRadius.pill),
            border: Border.all(
              color: online ? const Color(0x59FFFFFF) : OraColors.border,
            ),
            boxShadow: online
                ? const [
                    BoxShadow(
                      color: Color(0x5922C55E),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                      spreadRadius: -4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Icon(
                  busy
                      ? Icons.hourglass_top_rounded
                      : online
                      ? Icons.check_rounded
                      : Icons.power_settings_new_rounded,
                  size: 12,
                  color: online ? const Color(0xFF16A34A) : OraColors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                online ? 'Online' : 'Offline',
                style: OraTypography.caption(
                  online ? Colors.white : OraColors.textMuted,
                ).copyWith(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bright full-width card that jumps the driver over to the passenger
/// experience — book a ride with the same account.
class _PassengerSwitchCard extends StatelessWidget {
  const _PassengerSwitchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(OraSpacing.md),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
            ),
            borderRadius: BorderRadius.circular(OraRadius.card),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59FF6A0D),
                blurRadius: 16,
                offset: Offset(0, 6),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x33FFFFFF),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch to Passenger',
                      style: OraTypography.title(
                        Colors.white,
                      ).copyWith(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Book a ride with the same account',
                      style: OraTypography.caption(
                        const Color(0xE6FFFFFF),
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
