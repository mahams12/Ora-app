import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../super_app/recent/recent_activity.dart';
import '../../../super_app/presentation/widgets/unavailable_feature_sheet.dart';
import '../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import 'passenger_home_view.dart';
import '../../../../features/ride/presentation/views/ride_history_view.dart';

enum PassengerShellPage { home, rides }

/// Authenticated passenger shell with the existing prototype drawer.
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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncPassengerFcmToken(),
    );
  }

  /// NOTIF-RS-PUSH — passengers register an FCM token so ride-state nudges
  /// can reach them. Role-gated server-side; failures are non-fatal.
  Future<void> _syncPassengerFcmToken() async {
    final profile = ref.read(sessionUserProfileProvider);
    if (profile?.role != 'passenger') {
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
    final route = uri.toString();
    if (serviceType == 'intercity') {
      ref
          .read(recentActivityProvider.notifier)
          .record(
            RecentActivity(
              kind: RecentActivityKind.intercity,
              id: 'intercity',
              title: 'Intercity',
              subtitle: 'Book a ride',
              imageAsset: AppConstants.homeIntercityRoadAsset,
              route: route,
              atMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    }
    context.push(route);
  }

  Future<void> _showUnavailable(String feature) {
    _closeDrawer();
    return showUnavailableFeatureSheet(context, feature);
  }

  /// One row per earning role, gated by the server-authoritative profile:
  /// never applied → registration flow; pending → under-review state;
  /// approved → that role's posting/dashboard; rejected → re-apply;
  /// suspended → contact support. Posting pages are additionally blocked
  /// by the route guard for deep links.
  Future<void> _showEarnSheet() async {
    _closeDrawer();
    final profile = ref.read(sessionUserProfileProvider);
    String? statusOf(String type) => profile?.vendorStatusFor(type);

    Widget row({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) => OraListRow(
      leading: OraIconBadge(icon: icon),
      title: title,
      subtitle: subtitle,
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
    );

    Widget rowFor({
      required String type,
      required IconData icon,
      required String registerTitle,
      required String registerSubtitle,
      required String dashboardTitle,
      required String dashboardSubtitle,
      required String registerRoute,
      required String dashboardRoute,
      required String pendingTitle,
    }) {
      return switch (statusOf(type)) {
        'approved' => row(
          icon: icon,
          title: dashboardTitle,
          subtitle: dashboardSubtitle,
          onTap: () => context.push(dashboardRoute),
        ),
        'pending' => row(
          icon: Icons.hourglass_top_outlined,
          title: registerTitle,
          subtitle: 'Application under review',
          onTap: () => _showAccessGateSheet(
            title: pendingTitle,
            description:
                'Your application was received and is waiting for admin '
                'review. We will notify you once it is approved.',
          ),
        ),
        'suspended' => row(
          icon: Icons.block_outlined,
          title: registerTitle,
          subtitle: 'Suspended — contact support',
          onTap: () => _showAccessGateSheet(
            title: 'Access suspended',
            description:
                'This partner access is suspended. Contact ORA support '
                'for help.',
          ),
        ),
        'rejected' => row(
          icon: icon,
          title: registerTitle,
          subtitle: 'Application rejected — tap to re-apply',
          onTap: () => context.push(registerRoute),
        ),
        _ => row(
          icon: icon,
          title: registerTitle,
          subtitle: registerSubtitle,
          onTap: () => context.push(registerRoute),
        ),
      };
    }

    final driverRow = switch (profile?.driverStatus) {
      'pending' => row(
          icon: Icons.hourglass_top_outlined,
          title: 'Switch to Driver',
          subtitle: 'Application under review',
          onTap: _onSwitchToDriver,
        ),
      'suspended' => row(
          icon: Icons.block_outlined,
          title: 'Switch to Driver',
          subtitle: 'Suspended — contact support',
          onTap: _onSwitchToDriver,
        ),
      _ => row(
          icon: Icons.directions_car_filled_rounded,
          title: 'Switch to Driver',
          subtitle: profile?.isApprovedDriver == true
              ? 'Go to driver mode'
              : 'Register your vehicle',
          onTap: _onSwitchToDriver,
        ),
    };

    await showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraSectionHeader(
            eyebrow: 'Partner with ORA',
            title: 'Earn on ORA',
            description:
                'Choose how you want to earn — drive passengers, deliver '
                'cargo, list a property, or offer your services.',
          ),
          const SizedBox(height: OraSpacing.md),
          driverRow,
          const SizedBox(height: OraSpacing.xs),
          rowFor(
            type: 'cargo',
            icon: Icons.local_shipping_outlined,
            registerTitle: 'Switch to Logistics',
            registerSubtitle: 'Register your truck or cargo vehicle',
            dashboardTitle: 'Switch to Logistics',
            dashboardSubtitle: 'Post and manage transport listings',
            registerRoute: AppRoutes.cargoRegistration,
            dashboardRoute: AppRoutes.logisticsVendorHome,
            pendingTitle: 'Cargo application under review',
          ),
          const SizedBox(height: OraSpacing.xs),
          rowFor(
            type: 'rental',
            icon: Icons.home_work_outlined,
            registerTitle: 'Switch to Rental',
            registerSubtitle: 'List your property and start earning',
            dashboardTitle: 'Switch to Rental',
            dashboardSubtitle: 'Post and manage rental properties',
            registerRoute: AppRoutes.rentalRegistration,
            dashboardRoute: AppRoutes.rentalVendorHome,
            pendingTitle: 'Rental host application under review',
          ),
          const SizedBox(height: OraSpacing.xs),
          rowFor(
            type: 'service',
            icon: Icons.handyman_outlined,
            registerTitle: 'Switch to Services',
            registerSubtitle: 'Offer services on the ORA marketplace',
            dashboardTitle: 'Switch to Services',
            dashboardSubtitle: 'Post and manage your services',
            registerRoute: AppRoutes.serviceVendorRegistration,
            dashboardRoute: AppRoutes.vendorHome,
            pendingTitle: 'Service provider application under review',
          ),
        ],
      ),
    );
  }

  Future<void> _showAccessGateSheet({
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
            eyebrow: 'Partner access',
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

  void _openProfile() {
    _closeDrawer();
    context.push(AppRoutes.profile);
  }

  void _openDriverTools() {
    _closeDrawer();
    context.go(AppRoutes.driverHome);
  }

  Future<void> _showDriverGateSheet(String title) {
    return showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OraSectionHeader(eyebrow: 'Driver access', title: title),
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'Got it',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _onSwitchToDriver() async {
    _closeDrawer();
    // Role/driverStatus can change server-side after bootstrap (e.g. ops approval).
    // Refresh authoritative GET /v1/auth/me before gating driver shell entry.
    try {
      await ref
          .read(authStateNotifierProvider.notifier)
          .refreshCanonicalProfile();
    } catch (_) {
      // Fall through — gate uses last known session profile.
    }

    if (!mounted) return;
    final profile = ref.read(sessionUserProfileProvider);
    ref
        .read(appLoggerProvider)
        .info(
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
    if (profile?.driverStatus == 'pending') {
      await _showDriverGateSheet('Application under review');
      return;
    }
    if (profile?.driverStatus == 'suspended') {
      await _showDriverGateSheet('Driver account suspended — contact support');
      return;
    }
    await context.push<void>(AppRoutes.driverRegistration);
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
    final sessionProfile = ref.watch(sessionUserProfileProvider);
    final displayName = homeState.displayName?.trim().isNotEmpty == true
        ? homeState.displayName!.trim()
        : 'ORA passenger';

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      bottomNavigationBar: OraModuleBottomBar(
        selected: _page == PassengerShellPage.rides
            ? OraModuleDestination.rides
            : null,
      ),
      drawer: OraDrawerShell(
        avatarInitials: homeState.avatarInitials,
        avatarData: sessionProfile?.avatarData,
        displayName: displayName,
        subtitle: 'View profile',
        onProfileTap: _openProfile,
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
            title: 'My bookings',
            icon: Icons.event_note_rounded,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.gold,
            onTap: () {
              _closeDrawer();
              context.push(AppRoutes.myBookings);
            },
          ),
          OraDrawerItem(
            title: 'Refer & earn',
            icon: Icons.card_giftcard_rounded,
            iconBackground: OraColors.primaryMuted,
            iconColor: OraColors.accentCoral,
            subtitle: 'Get Rs 200 per friend',
            onTap: () => _showUnavailable('Refer & earn'),
          ),
          const OraDrawerSeparator(),
          OraDrawerItem(
            title: 'Earn on ORA',
            subtitle: 'Drive, deliver, host or serve',
            icon: Icons.payments_rounded,
            iconBackground: Colors.transparent,
            iconColor: OraColors.textPrimary,
            bareIcon: true,
            showChevron: true,
            onTap: _showEarnSheet,
          ),
          OraDrawerItem(
            title: 'MapLibre PoC',
            subtitle: 'Disposable renderer test — not production',
            icon: Icons.map_outlined,
            iconBackground: OraColors.infoMuted,
            iconColor: OraColors.info,
            onTap: () {
              _closeDrawer();
              context.push(AppRoutes.mapLibrePoc);
            },
          ),
          OraDrawerItem(
            title: 'Settings',
            icon: Icons.settings_rounded,
            iconBackground: OraColors.surfaceElevated,
            iconColor: OraColors.textSecondary,
            onTap: () => _showUnavailable('Settings'),
          ),
          OraDrawerItem(
            title: 'Help centre',
            icon: Icons.help_outline_rounded,
            iconBackground: OraColors.surfaceElevated,
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
            avatarData: sessionProfile?.avatarData,
            profileDisplayName: sessionProfile?.displayName,
            onOpenDrawer: _openDrawer,
            onRetryProfile: vm.loadProfile,
            onRequestRideEntry: _openRideRequest,
            onOpenProfile: _openProfile,
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
