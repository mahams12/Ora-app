import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

/// Uppercase section eyebrow / label (prototype `.section-label`).
class OraSectionLabel extends StatelessWidget {
  const OraSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(
      left: OraSpacing.xxs,
      bottom: OraSpacing.sm,
    ),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? OraColors.textMuted : OraColors.textSecondaryLight;
    return Padding(
      padding: padding,
      child: Text(text.toUpperCase(), style: OraTypography.sectionTitle(color)),
    );
  }
}

/// Section title row with optional trailing action.
class OraSectionHeader extends StatelessWidget {
  const OraSectionHeader({
    required this.title,
    super.key,
    this.description,
    this.action,
    this.eyebrow,
  });

  final String title;
  final String? description;
  final Widget? action;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? OraColors.textPrimary
        : OraColors.textPrimaryLight;
    final descColor = isDark
        ? OraColors.textMuted
        : OraColors.textSecondaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) OraSectionLabel(eyebrow!),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(title, style: OraTypography.title(titleColor)),
            ),
            if (action != null) action!,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: OraSpacing.xxs),
          Text(description!, style: OraTypography.caption(descColor)),
        ],
      ],
    );
  }
}
