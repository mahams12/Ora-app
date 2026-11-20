import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../view_models/driver_earnings_view_model.dart';
import '../widgets/driver_ui_kit.dart';

/// Driver "My Profile" hub — avatar + edit pencil, verified badge, menu
/// rows (vehicle/docs, personal info, wallet, settings, help) and logout.
/// Same visual language as the rest of the driver redesign: floating cream
/// cards, orange accents, tap-scale feedback.
class DriverProfileView extends ConsumerWidget {
  const DriverProfileView({
    required this.onEditProfile,
    required this.onOpenWallet,
    required this.onUnavailable,
    required this.onSignOut,
    required this.signingOut,
    this.roleLabel = 'Driver',
    this.roleIcon = Icons.directions_car_filled_rounded,
    this.fallbackName = 'ORA driver',
    this.headerSubtitle = 'Manage your account, vehicle and driver details',
    this.vehicleDocsSubtitle = 'Your vehicle and driver documents',
    this.approvalOf,
    this.statusOf,
    super.key,
  });

  /// Avatar pencil / "Personal Information" → pushes the profile editor.
  final VoidCallback onEditProfile;

  /// "Wallet & Payouts" → earnings page.
  final VoidCallback onOpenWallet;

  /// Feature-not-wired bottom sheet.
  final ValueChanged<String> onUnavailable;

  final VoidCallback onSignOut;
  final bool signingOut;

  /// Copy + approval overrides — logistics partners show their own badge
  /// and verify against the cargo vendor application instead of driverStatus.
  final String roleLabel;
  final IconData roleIcon;
  final String fallbackName;
  final String headerSubtitle;
  final String vehicleDocsSubtitle;
  final bool Function(UserProfile profile)? approvalOf;
  final String? Function(UserProfile profile)? statusOf;

  String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'DR';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionUserProfileProvider);
    final earnings = ref.watch(driverEarningsViewModelProvider);
    final name = (profile?.displayName?.trim().isNotEmpty == true)
        ? profile!.displayName!.trim()
        : fallbackName;
    final verified = profile == null
        ? false
        : (approvalOf ?? (p) => p.isApprovedDriver)(profile);
    final statusRaw = profile == null
        ? null
        : (statusOf ?? (p) => p.driverStatus)(profile);
    final status = (statusRaw?.trim().isNotEmpty == true)
        ? statusRaw!.trim()
        : 'unverified';
    final walletSubtitle =
        earnings.phase == DriverEarningsPhase.ready && earnings.summary != null
        ? 'Lifetime payout: Rs ${_formatRupees(earnings.summary!.allTime.payoutMinor ~/ 100)}'
        : 'Balance & payouts';

    return Column(
      children: [
        DriverHeroArtHeader(
          title: 'My Profile',
          subtitle: headerSubtitle,
          showLogo: true,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              OraSpacing.md,
              OraSpacing.md,
              OraSpacing.md,
              OraSpacing.xxl,
            ),
            children: [
              Transform.translate(
                offset: Offset.zero,
                child: Center(
                  child: Column(
                    children: [
                      Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onEditProfile();
                          },
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3.5,
                                  ),
                                  boxShadow: OraElevation.cardShadow,
                                ),
                                child: OraAvatar(
                                  initials: _initials(profile?.displayName),
                                  avatarData: profile?.avatarData,
                                  size: 88,
                                  fontSize: 30,
                                ),
                              ),
                              const Positioned(
                                right: -10,
                                bottom: -10,
                                child: DriverIconBadge(
                                  icon: Icons.edit_rounded,
                                  size: 30,
                                  iconSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      name,
                      style: OraTypography.title(OraColors.textPrimary)
                          .copyWith(
                            fontFamily: OraTypography.displayFamily,
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: OraColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(OraRadius.pill),
                        border: Border.all(color: OraColors.border),
                        boxShadow: OraElevation.cardShadow,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            roleIcon,
                            size: 13,
                            color: OraColors.goldSharp,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            roleLabel,
                            style: OraTypography.caption(
                              OraColors.goldSharp,
                            ).copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '   |   ',
                            style: OraTypography.caption(
                              OraColors.border,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            verified ? 'Verified' : status,
                            style: OraTypography.caption(
                              verified
                                  ? const Color(0xFF16A34A)
                                  : OraColors.textSecondary,
                            ).copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          if (verified) ...[
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 13,
                              color: Color(0xFF16A34A),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: OraSpacing.lg),
              _ProfileRow(
                icon: roleIcon,
                title: 'Vehicle & Documents',
                subtitle: verified
                    ? vehicleDocsSubtitle
                    : 'Verification: $status',
                trailing: verified ? const _VerifiedPill() : null,
                onTap: () => onUnavailable('Vehicle & documents'),
              ),
              const SizedBox(height: OraSpacing.sm),
              _ProfileRow(
                icon: Icons.person_rounded,
                title: 'Personal Information',
                subtitle: '$name • ${profile?.phoneNumber ?? ''}',
                onTap: onEditProfile,
              ),
              const SizedBox(height: OraSpacing.sm),
              _ProfileRow(
                icon: Icons.account_balance_wallet_rounded,
                title: 'Wallet & Payouts',
                subtitle: walletSubtitle,
                onTap: onOpenWallet,
              ),
              const SizedBox(height: OraSpacing.sm),
              _ProfileRow(
                icon: Icons.settings_rounded,
                title: 'Settings',
                subtitle: 'App, notifications and preferences',
                onTap: () => onUnavailable('Settings'),
              ),
              const SizedBox(height: OraSpacing.sm),
              _ProfileRow(
                icon: Icons.headset_mic_rounded,
                title: 'Help & Support',
                subtitle: 'Get help, FAQs or contact support',
                onTap: () => onUnavailable('Help & support'),
              ),
              const SizedBox(height: OraSpacing.xl),
              OraTapScale(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: signingOut
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            onSignOut();
                          },
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                    child: Ink(
                      height: 54,
                      decoration: BoxDecoration(
                        color: OraColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(OraRadius.pill),
                        border: Border.all(
                          color: OraColors.danger.withValues(alpha: 0.55),
                          width: 1.4,
                        ),
                        boxShadow: OraElevation.cardShadow,
                      ),
                      child: Center(
                        child: signingOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: OraColors.danger,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.logout_rounded,
                                    size: 19,
                                    color: OraColors.danger,
                                  ),
                                  const SizedBox(width: OraSpacing.xs),
                                  Text(
                                    'Log Out',
                                    style:
                                        OraTypography.button(
                                          OraColors.danger,
                                        ).copyWith(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Floating cream menu row — icon in a soft peach circle, title + subtitle,
/// trailing chevron (or custom widget like the green verified check).
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      downScale: 0.97,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(OraRadius.card),
          child: Ink(
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.md,
              vertical: OraSpacing.sm + 4,
            ),
            decoration: BoxDecoration(
              color: OraColors.surfaceElevated,
              borderRadius: BorderRadius.circular(OraRadius.card),
              border: Border.all(color: OraColors.border),
              boxShadow: OraElevation.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OraColors.primaryMuted,
                    border: Border.all(color: OraColors.border),
                  ),
                  child: Icon(icon, size: 20, color: OraColors.goldDeep),
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.body(
                          OraColors.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: OraColors.textMuted,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Green "✓ Verified" pill used on the Vehicle & Documents row.
class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1F22C55E),
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: const Color(0x6622C55E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 13,
            color: Color(0xFF16A34A),
          ),
          const SizedBox(width: 4),
          Text(
            'Verified',
            style: OraTypography.caption(const Color(0xFF16A34A)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// 7752 → "7,752".
String _formatRupees(int value) {
  final digits = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buf.write(digits[i]);
    if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(',');
  }
  return buf.toString();
}
