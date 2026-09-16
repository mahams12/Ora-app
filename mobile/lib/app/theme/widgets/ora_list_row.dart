import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

/// Settings / menu / option list row primitive.
class OraListRow extends StatelessWidget {
  const OraListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.showDivider = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool enabled;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = !enabled
        ? OraColors.disabledForeground
        : isDark
        ? OraColors.textPrimary
        : OraColors.textPrimaryLight;
    final subtitleColor = isDark
        ? OraColors.textMuted
        : OraColors.textSecondaryLight;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.xs,
        vertical: OraSpacing.sm,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: OraSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: OraTypography.bodyEmphasis(titleColor)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: OraTypography.caption(subtitleColor)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: OraSpacing.xs),
            trailing!,
          ] else if (onTap != null) ...[
            Icon(Icons.chevron_right_rounded, color: subtitleColor, size: 20),
          ],
        ],
      ),
    );

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? OraColors.primaryMuted : Colors.transparent,
        borderRadius: BorderRadius.circular(OraRadius.sm),
      ),
      child: row,
    );

    Widget content = decorated;
    if (onTap != null && enabled) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OraRadius.sm),
        child: decorated,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: onTap != null,
          enabled: enabled,
          selected: selected,
          label: subtitle == null ? title : '$title, $subtitle',
          child: content,
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: isDark ? OraColors.divider : const Color(0xFFE4E7EC),
          ),
      ],
    );
  }
}

/// Circular icon badge commonly used as [OraListRow.leading].
class OraIconBadge extends StatelessWidget {
  const OraIconBadge({
    required this.icon,
    super.key,
    this.backgroundColor = OraColors.primaryMuted,
    this.iconColor = OraColors.primary,
    this.size = 40,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(OraRadius.sm),
      ),
      child: Icon(icon, color: iconColor, size: size * 0.45),
    );
  }
}
