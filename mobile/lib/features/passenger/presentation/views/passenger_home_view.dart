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
            onHeroTap: () => onRequestRideEntry(null, serviceType: 'intercity'),
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
    required this.onHeroTap,
    this.avatarData,
    this.profileDisplayName,
  });

  final HomeUiState state;
  final String? avatarData;
  final String? profileDisplayName;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenProfile;
  final VoidCallback onHeroTap;

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
    return Column(
      children: [
        Container(
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
        ),
        _BlendedHeroArt(onTap: onHeroTap),
      ],
    );
  }
}

/// Full-bleed 3D road art that melts into the page gradient — the tagline
/// floats freely on the blended area like the reference hero.
class _BlendedHeroArt extends StatelessWidget {
  const _BlendedHeroArt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final height = (MediaQuery.sizeOf(context).height * 0.32).clamp(
      230.0,
      310.0,
    );
    return Semantics(
      button: true,
      label: 'Intercity rides',
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.42, 0.9],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.14, 0.8, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: Image.asset(
                    AppConstants.homeIntercityRoadAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.high,
                    cacheWidth: 1100,
                  ),
                ),
              ),
              Positioned(
                left: padding + 4,
                right: padding + 24,
                bottom: height * 0.12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORA',
                      style: OraTypography.sectionTitle(OraColors.goldDeep),
                    ),
                    const SizedBox(height: OraSpacing.xxs),
                    Text(
                      'Your World.\nOne App.',
                      style: OraTypography.display(OraColors.ink),
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Container(
                      width: 34,
                      height: 3,
                      decoration: BoxDecoration(
                        color: OraColors.gold,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

