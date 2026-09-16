import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../view_models/home_view_model.dart';
import '../widgets/passenger_bottom_nav.dart';
import 'passenger_home_view.dart';
import '../../../../features/ride/presentation/views/ride_history_view.dart';

/// Authenticated passenger shell: Home + My Rides history + Account.
///
/// Replaces the Phase 2C placeholder. Route path remains [AppRoutes.home].
class HomeShellView extends ConsumerStatefulWidget {
  const HomeShellView({super.key});

  @override
  ConsumerState<HomeShellView> createState() => _HomeShellViewState();
}

class _HomeShellViewState extends ConsumerState<HomeShellView> {
  PassengerTab _tab = PassengerTab.home;

  void _selectTab(PassengerTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
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
                '$feature is not available in this build. Ora will not invent '
                'data or pretend the feature works.',
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

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeViewModelProvider);
    final vm = ref.read(homeViewModelProvider.notifier);

    return Scaffold(
      backgroundColor: OraColors.background,
      body: IndexedStack(
        index: _tab.index,
        children: [
          PassengerHomeView(
            state: homeState,
            onRetryProfile: vm.loadProfile,
            onRequestRideEntry: _openRideRequest,
            onOpenRidesTab: () => _selectTab(PassengerTab.rides),
            onOpenAccountTab: () => _selectTab(PassengerTab.account),
            onUnavailableFeature: _showUnavailable,
          ),
          RideHistoryView(active: _tab == PassengerTab.rides),
          _AccountTab(
            state: homeState,
            isApprovedDriver:
                ref.watch(sessionUserProfileProvider)?.isApprovedDriver == true,
            onOpenDriverTools: () => context.go(AppRoutes.driverHome),
            onSignOut: homeState.signingOut ? null : vm.logout,
            onBackHome: () => _selectTab(PassengerTab.home),
          ),
        ],
      ),
      bottomNavigationBar: PassengerBottomNav(
        current: _tab,
        onSelect: _selectTab,
      ),
    );
  }
}

class _AccountTab extends StatelessWidget {
  const _AccountTab({
    required this.state,
    required this.isApprovedDriver,
    required this.onOpenDriverTools,
    required this.onSignOut,
    required this.onBackHome,
  });

  final HomeUiState state;
  final bool isApprovedDriver;
  final VoidCallback onOpenDriverTools;
  final VoidCallback? onSignOut;
  final VoidCallback onBackHome;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(OraSpacing.lg),
        children: [
          Text('Account', style: OraTypography.headline(OraColors.textPrimary)),
          const SizedBox(height: OraSpacing.md),
          OraCard(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [OraColors.gold, OraColors.goldDeep],
                    ),
                  ),
                  child: Text(
                    state.avatarInitials,
                    style: OraTypography.title(OraColors.primaryForeground),
                  ),
                ),
                const SizedBox(width: OraSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.displayName?.trim().isNotEmpty == true
                            ? state.displayName!.trim()
                            : 'Ora passenger',
                        style: OraTypography.bodyEmphasis(
                          OraColors.textPrimary,
                        ),
                      ),
                      if (state.phoneNumber != null)
                        Text(
                          _maskPhone(state.phoneNumber!),
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OraSpacing.lg),
          Text(
            'Profile editing, wallet, and safety centre arrive in later '
            'slices. You can sign out below.',
            style: OraTypography.body(OraColors.textMuted),
          ),
          if (isApprovedDriver) ...[
            const SizedBox(height: OraSpacing.lg),
            OraListRow(
              title: 'Driver tools',
              subtitle:
                  'Assigned rides, progression, and direct offer by known rideId',
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: OraColors.textMuted,
              ),
              onTap: onOpenDriverTools,
              showDivider: true,
            ),
          ],
          const SizedBox(height: OraSpacing.xl),
          OraButton(
            label: 'Sign out',
            variant: OraButtonVariant.outline,
            isLoading: state.signingOut,
            onPressed: onSignOut,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Back to Home',
            variant: OraButtonVariant.ghost,
            onPressed: onBackHome,
          ),
        ],
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '${phone.substring(0, 4)}••••${phone.substring(phone.length - 2)}';
  }
}
