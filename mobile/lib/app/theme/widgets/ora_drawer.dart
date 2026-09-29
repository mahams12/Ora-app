import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

/// Side navigation drawer chrome matching the Ora HTML prototype.
class OraDrawerShell extends StatelessWidget {
  const OraDrawerShell({
    required this.avatarInitials,
    required this.displayName,
    required this.children,
    this.subtitle = 'View profile',
    this.onProfileTap,
    this.showProfileStar = true,
    super.key,
  });

  final String avatarInitials;
  final String displayName;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onProfileTap;
  final bool showProfileStar;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.78;
    return Drawer(
      backgroundColor: OraColors.surface,
      width: width,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(26)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.lg,
                OraSpacing.xl,
                OraSpacing.lg,
                OraSpacing.lg,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [OraColors.navy, OraColors.navyElevated],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [OraColors.gold, OraColors.goldDeep],
                      ),
                    ),
                    child: Text(
                      avatarInitials,
                      style: OraTypography.title(OraColors.primaryForeground)
                          .copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.title(OraColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: onProfileTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showProfileStar) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: OraColors.gold,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(OraColors.goldSoft),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: OraSpacing.md,
                  vertical: OraSpacing.md,
                ),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OraDrawerItem extends StatelessWidget {
  const OraDrawerItem({
    required this.title,
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.showChevron = false,
    this.danger = false,
    this.bareIcon = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showChevron;
  final bool danger;

  /// Prototype "Switch to driver" uses a plain car icon (no rounded tile).
  final bool bareIcon;

  @override
  Widget build(BuildContext context) {
    final titleColor = danger ? OraColors.danger : OraColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.xxs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.xs,
              vertical: OraSpacing.sm,
            ),
            child: Row(
              children: [
                if (bareIcon)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(icon, color: iconColor, size: 20),
                  )
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(OraRadius.sm),
                    ),
                    child: Icon(icon, color: iconColor, size: 18),
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
                        style: OraTypography.bodyEmphasis(titleColor),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
                if (showChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: OraColors.textMuted,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OraDrawerSeparator extends StatelessWidget {
  const OraDrawerSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: OraSpacing.sm),
      child: Divider(height: 1, color: OraColors.border),
    );
  }
}
