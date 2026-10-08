import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import 'passenger_home_view.dart';
import '../../../../features/ride/presentation/views/ride_history_view.dart';

enum PassengerShellPage { home, rides }

/// Authenticated passenger shell — prototype drawer navigation (no bottom bar).
class HomeShellView extends ConsumerStatefulWidget {
  const HomeShellView({super.key});

  @override
  ConsumerState<HomeShellView> createState() => _HomeShellViewState();
}

class _HomeShellViewState extends ConsumerState<HomeShellView> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  PassengerShellPage _page = PassengerShellPage.home;

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  void _selectPage(PassengerShellPage page) {
    _closeDrawer();
    if (_page == page) return;
    setState(() => _page = page);
  }

  void _openRideRequest([String? categoryId]) {
    final uri = Uri(
      path: AppRoutes.rideRequest,
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty) 'category': categoryId,
      },
    );
    context.push(uri.toString());
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
                '$feature is planned for Ora but is not wired to the backend '
                'in this build. Nothing is faked.',
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

  void _openDriverTools() {
    _closeDrawer();
    context.go(AppRoutes.driverHome);
  }

  Future<void> _onSwitchToDriver() async {
    _closeDrawer();
    // Role/driverStatus can change server-side after bootstrap (e.g. ops approval).
    // Refresh authoritative GET /v1/auth/me before gating driver shell entry.
    try {
      await ref.read(authStateNotifierProvider.notifier).refreshCanonicalProfile();
    } catch (_) {
      // Fall through — gate uses last known session profile.
    }

    final profile = ref.read(sessionUserProfileProvider);
    ref.read(appLoggerProvider).info(
      'driver_mode_gate',
      metadata: {
        'uid': profile?.uid,
        'role': profile?.role,
        'driverStatus': profile?.driverStatus,
        'profileComplete': profile?.profileComplete,
        'isApprovedDriver': profile?.isApprovedDriver == true,
      },
    );

    if (profile?.isApprovedDriver == true) {
      _openDriverTools();
      return;
    }
    await _showUnavailable('Driver mode');
  }

  Future<void> _signOut() async {
    _closeDrawer();
    final vm = ref.read(homeViewModelProvider.notifier);
    await vm.logout();
  }

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeViewModelProvider);
    final vm = ref.read(homeViewModelProvider.notifier);
    final isApprovedDriver =
        ref.watch(sessionUserProfileProvider)?.isApprovedDriver == true;
    final displayName = homeState.displayName?.trim().isNotEmpty == true
        ? homeState.displayName!.trim()
        : 'ORA passenger';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: OraColors.background,
      drawer: OraDrawerShell(
        avatarInitials: homeState.avatarInitials,
        displayName: displayName,
        subtitle: 'View profile',
        onProfileTap: () {
          _closeDrawer();
          _showUnavailable('Profile');
        },
        children: [
          OraDrawerItem(
            title: 'Home',
            icon: Icons.home_rounded,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.goldSoft,
            onTap: () => _selectPage(PassengerShellPage.home),
          ),
          OraDrawerItem(
            title: 'My rides',
            icon: Icons.history_rounded,
            iconBackground: OraColors.infoMuted,
            iconColor: OraColors.info,
            onTap: () => _selectPage(PassengerShellPage.rides),
          ),
          OraDrawerItem(
            title: 'Saved places',
            icon: Icons.bookmark_rounded,
            iconBackground: const Color(0x37A78BFA),
            iconColor: OraColors.accentPurple,
            onTap: () => _showUnavailable('Saved places'),
          ),
          OraDrawerItem(
            title: 'Wallet',
            icon: Icons.account_balance_wallet_rounded,
            iconBackground: OraColors.secondaryMuted,
            iconColor: OraColors.tealBright,
            onTap: () => _showUnavailable('Wallet'),
          ),
          OraDrawerItem(
            title: 'Refer & earn',
            icon: Icons.card_giftcard_rounded,
            iconBackground: const Color(0x33F08A6A),
            iconColor: OraColors.accentCoral,
            subtitle: 'Get Rs 200 per friend',
            onTap: () => _showUnavailable('Refer & earn'),
          ),
          OraDrawerItem(
            title: 'Safety centre',
            icon: Icons.shield_rounded,
            iconBackground: const Color(0x33D9F2EA),
            iconColor: const Color(0xFF8A6423),
            onTap: () => _showUnavailable('Safety centre'),
          ),
          const OraDrawerSeparator(),
          OraDrawerItem(
            title: 'Switch to driver mode',
            subtitle: isApprovedDriver
                ? 'Earn with the same account'
                : 'Register your vehicle',
            icon: Icons.directions_car_filled_rounded,
            iconBackground: Colors.transparent,
            iconColor: OraColors.textPrimary,
            bareIcon: true,
            showChevron: true,
            onTap: _onSwitchToDriver,
          ),
          OraDrawerItem(
            title: 'MapLibre PoC',
            subtitle: 'Disposable renderer test — not production',
            icon: Icons.map_outlined,
            iconBackground: const Color(0x384FA3D9),
            iconColor: OraColors.info,
            onTap: () {
              _closeDrawer();
              context.push(AppRoutes.mapLibrePoc);
            },
          ),
          OraDrawerItem(
            title: 'Settings',
            icon: Icons.settings_rounded,
            iconBackground: const Color(0x14FFFFFF),
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Settings'),
          ),
          OraDrawerItem(
            title: 'Help centre',
            icon: Icons.help_outline_rounded,
            iconBackground: const Color(0x14FFFFFF),
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Help centre'),
          ),
          OraDrawerItem(
            title: 'Log out',
            icon: Icons.logout_rounded,
            iconBackground: OraColors.dangerMuted,
            iconColor: OraColors.danger,
            danger: true,
            onTap: homeState.signingOut ? () {} : _signOut,
          ),
        ],
      ),
      body: IndexedStack(
        index: _page.index,
        children: [
          PassengerHomeView(
            state: homeState,
            onOpenDrawer: _openDrawer,
            onRetryProfile: vm.loadProfile,
            onRequestRideEntry: _openRideRequest,
            onOpenProfile: () => _showUnavailable('Profile'),
            onOpenRides: () => _selectPage(PassengerShellPage.rides),
            onSwitchToDriver: _onSwitchToDriver,
            onUnavailableFeature: _showUnavailable,
          ),
          RideHistoryView(
            active: _page == PassengerShellPage.rides,
            onOpenDrawer: _openDrawer,
          ),
        ],
      ),
    );
  }
}
