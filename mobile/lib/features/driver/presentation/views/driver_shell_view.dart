import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import 'driver_assigned_rides_view.dart';
import 'driver_direct_offer_view.dart';
import 'driver_home_view.dart';
import 'driver_open_rides_view.dart';

enum DriverShellPage { home, open, assigned, offer }

/// Driver shell — prototype drawer navigation (no bottom bar).
class DriverShellView extends ConsumerStatefulWidget {
  const DriverShellView({super.key, this.initialTab = DriverShellPage.home});

  /// Kept for route compatibility; maps legacy tab names to pages.
  final DriverShellPage initialTab;

  @override
  ConsumerState<DriverShellView> createState() => _DriverShellViewState();
}

class _DriverShellViewState extends ConsumerState<DriverShellView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late DriverShellPage _page;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDispatchFcmToken());
  }

  Future<void> _syncDispatchFcmToken() async {
    final profile = ref.read(sessionUserProfileProvider);
    if (profile?.isApprovedDriver != true) {
      return;
    }
    await ref.read(dispatchFcmServiceProvider).syncDriverTokenRegistration();
  }

  @override
  void didUpdateWidget(DriverShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != _page) {
      setState(() => _page = widget.initialTab);
    }
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _selectPage(DriverShellPage page) {
    _closeDrawer();
    if (_page == page) return;
    setState(() => _page = page);
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
                '$feature is in the Ora driver prototype but is not wired to '
                'the backend in this build. Nothing is faked.',
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

  Future<void> _signOut() async {
    _closeDrawer();
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
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
    if (parts.isEmpty) return 'DR';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionUserProfileProvider);
    final displayName = (profile?.displayName?.trim().isNotEmpty == true)
        ? profile!.displayName!.trim()
        : 'ORA driver';
    final initials = _initials(profile?.displayName);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OraColors.background,
      drawer: OraDrawerShell(
        avatarInitials: initials,
        displayName: displayName,
        subtitle: 'Driver profile',
        onProfileTap: () => _showUnavailable('Driver profile'),
        children: [
          OraDrawerItem(
            title: 'Driver home',
            icon: Icons.speed_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _selectPage(DriverShellPage.home),
          ),
          OraDrawerItem(
            title: 'Open ride requests',
            icon: Icons.travel_explore_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _selectPage(DriverShellPage.open),
          ),
          OraDrawerItem(
            title: 'My trips',
            icon: Icons.route_rounded,
            iconBackground: OraColors.infoMuted,
            iconColor: OraColors.info,
            onTap: () => _selectPage(DriverShellPage.assigned),
          ),
          OraDrawerItem(
            title: 'Direct offer',
            icon: Icons.local_offer_outlined,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.goldSoft,
            subtitle: 'Lab / known rideId',
            onTap: () => _selectPage(DriverShellPage.offer),
          ),
          OraDrawerItem(
            title: 'Earnings',
            icon: Icons.show_chart_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _showUnavailable('Earnings'),
          ),
          OraDrawerItem(
            title: 'Payouts',
            icon: Icons.account_balance_wallet_rounded,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.goldSoft,
            onTap: () => _showUnavailable('Payouts'),
          ),
          OraDrawerItem(
            title: 'Vehicle',
            icon: Icons.directions_car_filled_rounded,
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
            onTap: () {
              _closeDrawer();
              context.go(AppRoutes.home);
            },
          ),
          OraDrawerItem(
            title: 'Driver settings',
            icon: Icons.settings_rounded,
            iconBackground: const Color(0x14FFFFFF),
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Driver settings'),
          ),
          OraDrawerItem(
            title: 'Driver help',
            icon: Icons.help_outline_rounded,
            iconBackground: const Color(0x14FFFFFF),
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Driver help'),
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
            onOpenDrawer: _openDrawer,
            onOpenProfile: () => _showUnavailable('Driver profile'),
            onOpenRideRequests: () => _selectPage(DriverShellPage.open),
            onOpenAssignedTrips: () => _selectPage(DriverShellPage.assigned),
            onOpenDirectOffer: () => _selectPage(DriverShellPage.offer),
            onUnavailable: _showUnavailable,
          ),
          _DriverSubpage(
            title: 'Open rides',
            onOpenDrawer: _openDrawer,
            child: DriverOpenRidesView(active: _page == DriverShellPage.open),
          ),
          _DriverSubpage(
            title: 'My trips',
            onOpenDrawer: _openDrawer,
            child: DriverAssignedRidesView(
              active: _page == DriverShellPage.assigned,
            ),
          ),
          _DriverSubpage(
            title: 'Direct offer',
            onOpenDrawer: _openDrawer,
            child: const DriverDirectOfferView(),
          ),
        ],
      ),
    );
  }
}

class _DriverSubpage extends StatelessWidget {
  const _DriverSubpage({
    required this.title,
    required this.onOpenDrawer,
    required this.child,
  });

  final String title;
  final VoidCallback onOpenDrawer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              OraSpacing.xs,
              OraSpacing.xs,
              OraSpacing.md,
              0,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Menu',
                  onPressed: onOpenDrawer,
                  icon: const Icon(Icons.menu_rounded),
                  color: OraColors.textPrimary,
                ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: OraColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Sora',
                        ),
                  ),
                ),
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: OraColors.primary,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Sora',
                      ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
