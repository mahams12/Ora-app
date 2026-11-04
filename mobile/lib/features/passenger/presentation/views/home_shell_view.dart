import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../driver/presentation/widgets/driver_onboarding_sheet.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncPassengerFcmToken());
  }

  /// NOTIF-RS-PUSH — passengers register an FCM token so ride-state nudges
  /// can reach them. Role-gated server-side; failures are non-fatal.
  Future<void> _syncPassengerFcmToken() async {
    final profile = ref.read(sessionUserProfileProvider);
    // Dual-role accounts: approved drivers in passenger mode also need
    // passenger ride nudges — the server gate allows driverStatus=approved.
    if (profile?.role != 'passenger' && profile?.isApprovedDriver != true) {
      return;
    }
    try {
      await ref
          .read(dispatchFcmServiceProvider)
          .syncPassengerTokenRegistration();
    } catch (_) {
      // Token sync is best-effort; ride state stays authoritative over HTTP.
    }
  }

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

  void _openRideRequest(String? categoryId, {String? serviceType}) {
    final uri = Uri(
      path: AppRoutes.rideRequest,
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty) 'category': categoryId,
        if (serviceType != null && serviceType.isNotEmpty)
          'service': serviceType,
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

    final driverStatus = profile?.driverStatus ?? 'none';
    if (driverStatus == 'pending') {
      await _showDriverStatusSheet(
        title: 'Application under review',
        description:
            'Your driver application is still being reviewed. You will be '
            'able to switch to driver mode once it is approved.',
      );
      return;
    }
    if (driverStatus == 'suspended') {
      await _showDriverStatusSheet(
        title: 'Driver access suspended',
        description:
            'Your driver access has been suspended. Contact your '
            'administrator for more information.',
      );
      return;
    }
    if (profile?.isApprovedDriver != true) {
      // driverStatus 'none' — first-time driver onboarding.
      await _startDriverOnboarding();
      return;
    }
    await _switchToDriverMode();
  }

  /// Approved driver → POST /v1/auth/mode then enter the driver shell.
  /// ACTIVE_JOB means a live passenger booking must be finished first.
  Future<void> _switchToDriverMode() async {
    try {
      final profile =
          await ref.read(switchModeUseCaseProvider)(mode: 'driver');
      ref.read(sessionUserProfileProvider.notifier).setProfile(profile);
      if (!mounted) return;
      _openDriverTools();
    } catch (error) {
      if (!mounted) return;
      final failure = ref.read(failureMapperProvider).fromException(error);
      await _showDriverStatusSheet(
        title: 'Cannot switch to driver mode',
        description: failure.userMessage,
      );
    }
  }

  /// First-time driver: collect vehicle details → submit → 'pending'.
  Future<void> _startDriverOnboarding() async {
    final result = await DriverOnboardingSheet.show(context);
    if (result == null || !mounted) return;
    try {
      await ref.read(submitDriverOnboardingUseCaseProvider)(
        vehicleType: result.vehicleType,
        vehicleModel:
            result.vehicleModel?.isNotEmpty == true ? result.vehicleModel : null,
        plateNumber:
            result.plateNumber?.isNotEmpty == true ? result.plateNumber : null,
        homeCity: result.homeCity?.isNotEmpty == true ? result.homeCity : null,
      );
      if (!mounted) return;
      await _showDriverStatusSheet(
        title: 'Application submitted',
        description:
            'Your driver application has been submitted for review. You will '
            'be able to switch to driver mode once it is approved.',
      );
    } catch (error) {
      if (!mounted) return;
      final failure = ref.read(failureMapperProvider).fromException(error);
      await _showDriverStatusSheet(
        title: 'Application failed',
        description: failure.userMessage,
      );
    }
  }

  Future<void> _showDriverStatusSheet({
    required String title,
    required String description,
  }) {
    return showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OraSectionHeader(
            eyebrow: 'Switch to driver',
            title: title,
            description: description,
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
    if (ref.read(sessionUserProfileProvider)?.role == 'passenger') {
      await ref.read(dispatchFcmServiceProvider).clearRegisteredToken();
    }
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
