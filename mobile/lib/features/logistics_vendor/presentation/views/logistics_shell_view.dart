import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../driver/presentation/view_models/driver_availability_view_model.dart';
import '../../../driver/presentation/views/driver_assigned_rides_view.dart';
import '../../../driver/presentation/views/driver_earnings_view.dart';
import '../../../driver/presentation/views/driver_home_view.dart';
import '../../../driver/presentation/views/driver_open_rides_view.dart';
import '../../../driver/presentation/views/driver_profile_view.dart';
import '../../../driver/presentation/views/driver_wallet_view.dart';
import '../../../driver/presentation/widgets/driver_nav_bar.dart';
import '../../../driver/presentation/widgets/driver_ui_kit.dart';
import '../../../driver/recent/driver_recents.dart';

enum LogisticsShellPage { home, open, assigned, earnings, wallet, profile }

/// Logistics partner shell — the approved-cargo-vendor counterpart of
/// [DriverShellView]. Reuses the driver views/providers verbatim so
/// realtime delivery offers, invite countdowns, assigned jobs, earnings,
/// wallet and profile behave exactly like the driver side; only copy,
/// artwork and role gates differ.
class LogisticsShellView extends ConsumerStatefulWidget {
  const LogisticsShellView({
    super.key,
    this.initialTab = LogisticsShellPage.home,
  });

  /// Kept for route compatibility; maps legacy tab names to pages.
  final LogisticsShellPage initialTab;

  @override
  ConsumerState<LogisticsShellView> createState() =>
      _LogisticsShellViewState();
}

class _LogisticsShellViewState extends ConsumerState<LogisticsShellView>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late LogisticsShellPage _page;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncDispatchFcmToken(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Presence publisher only runs in foreground (no background location).
    if (ref.exists(driverPresenceProvider)) {
      ref
          .read(driverPresenceProvider.notifier)
          .onAppLifecycle(state == AppLifecycleState.resumed);
    }
  }

  Future<void> _syncDispatchFcmToken() async {
    final profile = ref.read(sessionUserProfileProvider);
    final deliveryOperator =
        profile?.isApprovedDriver == true ||
        profile?.isApprovedVendor('cargo') == true;
    if (!deliveryOperator) {
      return;
    }
    await ref.read(dispatchFcmServiceProvider).syncDriverTokenRegistration();
  }

  @override
  void didUpdateWidget(LogisticsShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != _page) {
      setState(() => _page = widget.initialTab);
    }
  }

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _selectPage(LogisticsShellPage page) {
    _closeDrawer();
    if (_page == page) return;
    final recent = switch (page) {
      LogisticsShellPage.open => DriverRecentDestination.requests,
      LogisticsShellPage.assigned => DriverRecentDestination.bookings,
      LogisticsShellPage.earnings => DriverRecentDestination.earnings,
      LogisticsShellPage.wallet => DriverRecentDestination.wallet,
      LogisticsShellPage.profile => DriverRecentDestination.profile,
      LogisticsShellPage.home => null,
    };
    if (recent != null) {
      ref.read(driverRecentsProvider.notifier).record(recent);
    }
    setState(() => _page = page);
  }

  void _openProfile() {
    _closeDrawer();
    context.push(AppRoutes.profile);
  }

  Future<void> _showUnavailable(String feature) {
    _closeDrawer();
    return showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OraSectionHeader(
            eyebrow: 'Coming later',
            title: feature,
            description:
                '$feature is in the Ora logistics prototype but is not wired '
                'to the backend in this build. Nothing is faked.',
          ),
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Switch to Passenger — POST /v1/auth/mode. The server durably takes the
  /// operator offline (ghost-presence guard) and refuses with ACTIVE_JOB
  /// while a delivery is in flight.
  Future<void> _onSwitchToPassenger() async {
    _closeDrawer();
    if (_signingOut) return;
    try {
      final profile = await ref.read(switchModeUseCaseProvider)(
        mode: 'passenger',
      );
      ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
      // Refresh availability → presence publisher stops (isOnline=false).
      unawaited(ref.read(driverAvailabilityProvider.notifier).refresh());
      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      final failure = ref.read(failureMapperProvider).fromException(error);
      final isActiveJob =
          failure is ConflictFailure && failure.code == 'ACTIVE_JOB';
      await showOraBottomSheet<void>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OraSectionHeader(
              eyebrow: 'Switch to passenger',
              title: isActiveJob
                  ? 'Active delivery in progress'
                  : 'Cannot switch to passenger mode',
              description: isActiveJob
                  ? 'You have an active delivery. Finish it before switching '
                        'to passenger mode — the job is kept in '
                        'My Deliveries.'
                  : failure.userMessage,
            ),
            const SizedBox(height: OraSpacing.lg),
            if (isActiveJob)
              OraButton(
                label: 'Go to My Deliveries',
                onPressed: () {
                  Navigator.of(context).pop();
                  _selectPage(LogisticsShellPage.assigned);
                },
              ),
            const SizedBox(height: OraSpacing.xs),
            OraButton(
              label: 'Stay in logistics mode',
              variant: OraButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _signOut() async {
    _closeDrawer();
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      if (ref.exists(driverPresenceProvider)) {
        ref.read(driverPresenceProvider.notifier).onSignedOut();
      }
      await ref.read(dispatchFcmServiceProvider).clearRegisteredToken();
      await ref.read(logoutUseCaseProvider)();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'LG';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionUserProfileProvider);
    final displayName = (profile?.displayName?.trim().isNotEmpty == true)
        ? profile!.displayName!.trim()
        : 'ORA logistics partner';
    final initials = _initials(profile?.displayName);
    // Watching keeps the shell-scoped presence publisher alive; its gates are
    // driven by the availability provider + app lifecycle.
    ref.watch(driverPresenceProvider);
    final availability = ref.watch(driverAvailabilityProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: DriverNavBar(
        tripsLabel: 'Jobs',
        selected: switch (_page) {
          LogisticsShellPage.home => DriverNavDestination.home,
          LogisticsShellPage.assigned => DriverNavDestination.trips,
          LogisticsShellPage.earnings => DriverNavDestination.earnings,
          LogisticsShellPage.wallet => DriverNavDestination.wallet,
          LogisticsShellPage.profile => DriverNavDestination.profile,
          LogisticsShellPage.open => null,
        },
        onSelect: (dest) => switch (dest) {
          DriverNavDestination.home => _selectPage(LogisticsShellPage.home),
          DriverNavDestination.trips => _selectPage(
            LogisticsShellPage.assigned,
          ),
          DriverNavDestination.earnings => _selectPage(
            LogisticsShellPage.earnings,
          ),
          DriverNavDestination.wallet => _selectPage(LogisticsShellPage.wallet),
          DriverNavDestination.profile => _selectPage(
            LogisticsShellPage.profile,
          ),
        },
      ),
      drawer: OraDrawerShell(
        avatarInitials: initials,
        avatarData: profile?.avatarData,
        displayName: displayName,
        subtitle: 'Logistics Partner profile',
        onProfileTap: _openProfile,
        children: [
          OraDrawerItem(
            title: 'Logistics home',
            icon: Icons.local_shipping_outlined,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _selectPage(LogisticsShellPage.home),
          ),
          OraDrawerItem(
            title: 'Delivery requests',
            icon: Icons.travel_explore_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _selectPage(LogisticsShellPage.open),
          ),
          OraDrawerItem(
            title: 'My Deliveries',
            icon: Icons.route_rounded,
            iconBackground: OraColors.infoMuted,
            iconColor: OraColors.info,
            onTap: () => _selectPage(LogisticsShellPage.assigned),
          ),
          OraDrawerItem(
            title: 'Earnings',
            icon: Icons.show_chart_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _selectPage(LogisticsShellPage.earnings),
          ),
          OraDrawerItem(
            title: 'Wallet',
            icon: Icons.account_balance_wallet_rounded,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.goldSoft,
            onTap: () => _selectPage(LogisticsShellPage.wallet),
          ),
          OraDrawerItem(
            title: 'Vehicle',
            icon: Icons.local_shipping_rounded,
            iconBackground: OraColors.navy,
            iconColor: OraColors.textPrimary,
            onTap: () => _showUnavailable('Vehicle'),
          ),
          OraDrawerItem(
            title: 'Documents',
            icon: Icons.description_outlined,
            iconBackground: OraColors.infoMuted,
            iconColor: OraColors.info,
            onTap: () => _showUnavailable('Documents'),
          ),
          const OraDrawerSeparator(),
          OraDrawerItem(
            title: 'Switch to passenger mode',
            subtitle: 'Book your own rides',
            icon: Icons.person_rounded,
            iconBackground: Colors.transparent,
            iconColor: OraColors.goldSoft,
            bareIcon: true,
            showChevron: true,
            onTap: _onSwitchToPassenger,
          ),
          OraDrawerItem(
            title: 'Partner settings',
            icon: Icons.settings_rounded,
            iconBackground: OraColors.surfaceElevated,
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Partner settings'),
          ),
          OraDrawerItem(
            title: 'Partner help',
            icon: Icons.help_outline_rounded,
            iconBackground: OraColors.surfaceElevated,
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Partner help'),
          ),
          OraDrawerItem(
            title: 'Log out',
            icon: Icons.logout_rounded,
            iconBackground: OraColors.dangerMuted,
            iconColor: OraColors.danger,
            danger: true,
            onTap: _signingOut ? () {} : _signOut,
          ),
        ],
      ),
      body: IndexedStack(
        index: _page.index,
        children: [
          DriverHomeView(
            displayName: displayName,
            avatarInitials: initials,
            avatarData: profile?.avatarData,
            onSwitchToPassenger: _onSwitchToPassenger,
            onOpenProfile: _openProfile,
            onOpenRideRequests: () => _selectPage(LogisticsShellPage.open),
            onOpenAssignedTrips: () =>
                _selectPage(LogisticsShellPage.assigned),
            onOpenEarnings: () => _selectPage(LogisticsShellPage.earnings),
            onUnavailable: _showUnavailable,
            heroAsset: 'assets/logistics/logistics_hero.jpg',
            requestsTileLabel: 'Delivery requests',
            requestsTileAsset: 'assets/logistics/logistics_truck.png',
            tripsTileLabel: 'My Deliveries',
            tripsTileAsset: 'assets/logistics/logistics_truck.png',
            todayTripsLabel: 'Today\'s Deliveries',
            onOpenWallet: () => _selectPage(LogisticsShellPage.wallet),
            availabilityOnline: availability.isOnline,
            availabilityBusy: availability.busy,
            availabilityLoaded: availability.loaded,
            onToggleAvailability: () => unawaited(
              ref.read(driverAvailabilityProvider.notifier).toggle(),
            ),
          ),
          _LogisticsSubpage(
            title: 'Delivery Requests',
            child: DriverOpenRidesView(
              active: _page == LogisticsShellPage.open,
              infoText:
                  'Available delivery requests from Ora\'s servers for '
                  'approved logistics partners.',
              sheetTitle: 'New Delivery Request',
              offerLabel: 'Customer Offer',
              invitesSectionLabel: 'Delivery requests for you',
            ),
          ),
          _LogisticsSubpage(
            title: 'My Deliveries',
            child: DriverAssignedRidesView(
              active: _page == LogisticsShellPage.assigned,
              ridePathFor: AppRoutes.logisticsDeliveryPath,
              jobSingular: 'delivery',
              jobPlural: 'deliveries',
            ),
          ),
          _LogisticsSubpage(
            title: 'My Earnings',
            subtitle: 'Track your income, deliveries and performance',
            artHeader: true,
            onBell: () => _selectPage(LogisticsShellPage.open),
            child: DriverEarningsView(
              active: _page == LogisticsShellPage.earnings,
              ridePathFor: AppRoutes.logisticsDeliveryPath,
              tripsLabel: 'Total Deliveries',
              tripsIcon: Icons.local_shipping_rounded,
              emptyTitle: 'No completed deliveries yet',
              emptyMessage:
                  'Deliveries you complete will appear here with their '
                  'agreed fare. Only finished jobs count toward totals.',
            ),
          ),
          const DriverWalletView(
            homeRoute: AppRoutes.logisticsVendorHome,
            addPointsRoute: AppRoutes.logisticsVendorWalletAddPoints,
          ),
          DriverProfileView(
            onEditProfile: _openProfile,
            onOpenWallet: () => _selectPage(LogisticsShellPage.wallet),
            onUnavailable: _showUnavailable,
            onSignOut: _signOut,
            signingOut: _signingOut,
            roleLabel: 'Logistics Partner',
            roleIcon: Icons.local_shipping_rounded,
            fallbackName: 'ORA logistics partner',
            headerSubtitle:
                'Manage your account, vehicle and partner details',
            vehicleDocsSubtitle: 'Your vehicle and partner documents',
            approvalOf: (p) => p.isApprovedVendor('cargo'),
            statusOf: (p) => p.vendorStatusFor('cargo'),
          ),
        ],
      ),
    );
  }
}

class _LogisticsSubpage extends StatelessWidget {
  const _LogisticsSubpage({
    required this.title,
    required this.child,
    this.subtitle,
    this.artHeader = false,
    this.onBell,
  });

  final String title;
  final String? subtitle;
  final bool artHeader;
  final VoidCallback? onBell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (artHeader)
          DriverHeroArtHeader(
            title: title,
            subtitle: subtitle,
            trailingIcon: Icons.notifications_outlined,
            trailingTooltip: 'Delivery requests',
            onTrailing: onBell,
          )
        else
          DriverOrangeTopBar(title: title),
        Expanded(child: child),
      ],
    );
  }
}
