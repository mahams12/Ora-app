import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_motion.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

enum OraChipVariant { filter, status, category, compact }

/// Selectable / status chip matching prototype chip language.
class OraChip extends StatelessWidget {
  const OraChip({
    required this.label,
    super.key,
    this.selected = false,
    this.onTap,
    this.variant = OraChipVariant.filter,
    this.leading,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final OraChipVariant variant;
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = variant == OraChipVariant.compact;

    final bg = !enabled
        ? OraColors.disabled.withValues(alpha: 0.35)
        : selected
        ? OraColors.primaryMuted
        : isDark
        ? OraColors.surfaceElevated
        : Colors.white;

    final border = !enabled
        ? OraColors.disabled
        : selected
        ? OraColors.primary
        : OraColors.border;

    final fg = !enabled
        ? OraColors.disabledForeground
        : selected
        ? OraColors.primary
        : isDark
        ? OraColors.textPrimary
        : OraColors.textPrimaryLight;

    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: OraSpacing.xs, vertical: 6)
        : const EdgeInsets.symmetric(
            horizontal: OraSpacing.sm,
            vertical: OraSpacing.xs,
          );

    final content = AnimatedContainer(
      duration: OraMotion.select,
      curve: OraMotion.standard,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(
          variant == OraChipVariant.status ? OraRadius.pill : OraRadius.chip,
        ),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: OraSpacing.xxs),
          ],
          Text(
            label,
            style:
                (compact ? OraTypography.caption(fg) : OraTypography.label(fg))
                    .copyWith(
                      fontFamily: OraTypography.displayFamily,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
          ),
        ],
      ),
    );

    if (onTap == null || !enabled) return content;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(OraRadius.chip),
        child: content,
      ),
    );
  }
}
