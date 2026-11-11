import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';
import '../../../super_app/presentation/widgets/ora_module_grid.dart';
import '../../../super_app/presentation/widgets/recent_activity_section.dart';
import '../view_models/home_view_model.dart';

/// Authenticated passenger Home — matches the Ora HTML prototype shell.
class PassengerHomeView extends StatelessWidget {
  const PassengerHomeView({
    required this.state,
    required this.onOpenDrawer,
    required this.onRetryProfile,
    required this.onRequestRideEntry,
    required this.onOpenProfile,
    VoidCallback? onOpenRides,
    VoidCallback? onSwitchToDriver,
    ValueChanged<String>? onUnavailableFeature,
    this.avatarData,
    this.profileDisplayName,
    super.key,
  });

  final HomeUiState state;
  final String? avatarData;
  final String? profileDisplayName;
  final VoidCallback onOpenDrawer;
  final VoidCallback onRetryProfile;
  final void Function(String? categoryId, {String? serviceType})
  onRequestRideEntry;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    if (state.loadStatus == HomeLoadStatus.loading &&
        state.displayName == null) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading your home…'),
      );
    }

    if (state.loadStatus == HomeLoadStatus.error && state.displayName == null) {
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
            avatarData: avatarData,
            profileDisplayName: profileDisplayName,
            onOpenDrawer: onOpenDrawer,
            onOpenProfile: onOpenProfile,
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
                onTap: () => onRequestRideEntry(null, serviceType: 'intercity'),
              ),
              const SizedBox(height: OraSpacing.md),
              const OraSectionHeader(title: 'Explore ORA'),
              const SizedBox(height: OraSpacing.sm),
              const OraModuleGrid(),
              const SizedBox(height: OraSpacing.lg),
              const RecentActivitySection(),
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
    this.avatarData,
    this.profileDisplayName,
  });

  final HomeUiState state;
  final String? avatarData;
  final String? profileDisplayName;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenProfile;

  String get _avatarInitials {
    final name = (profileDisplayName ?? state.displayName)?.trim();
    if (name == null || name.isEmpty) return state.avatarInitials;
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? state.avatarInitials : letters;
  }

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
          colors: [OraColors.navyElevated, OraColors.primaryMuted],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        border: Border(
          bottom: BorderSide(color: Color(0x66F88733), width: 1.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x33F88733),
            blurRadius: 18,
            offset: Offset(0, 6),
            spreadRadius: -8,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Menu',
              onPressed: onOpenDrawer,
              icon: const Icon(Icons.menu_rounded),
              color: OraColors.textPrimary,
            ),
            Expanded(
              child: Image.asset(
                AppConstants.logoAsset,
                height: 30,
                fit: BoxFit.contain,
                alignment: Alignment.center,
              ),
            ),
            InkWell(
              onTap: onOpenProfile,
              borderRadius: BorderRadius.circular(OraRadius.avatar),
              child: OraAvatar(
                initials: _avatarInitials,
                avatarData: avatarData,
                size: 38,
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
    return Semantics(
      button: true,
      label: 'Intercity rides',
      onTap: onTap,
      child: Material(
        color: OraColors.navy,
        borderRadius: BorderRadius.circular(OraRadius.lg),
        child: InkWell(
          excludeFromSemantics: true,
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.lg),
          child: SizedBox(
            height: 176,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    AppConstants.homeIntercityRoadAsset,
                    cacheWidth: 800,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [
                          Colors.transparent,
                          OraColors.photoScrimStrong,
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(OraSpacing.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ORA',
                          style: OraTypography.sectionTitle(OraColors.goldSoft),
                        ),
                        const SizedBox(height: OraSpacing.xxs),
                        Text(
                          'Your World. One App.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.title(OraColors.onPhoto),
                        ),
                        const SizedBox(height: OraSpacing.xxs),
                        Text(
                          'Wherever life takes you, ORA makes it easier.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.onPhotoMuted),
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
