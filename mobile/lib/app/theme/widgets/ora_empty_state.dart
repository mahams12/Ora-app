import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

class OraEmptyState extends StatelessWidget {
  const OraEmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? OraColors.textPrimary
        : OraColors.textPrimaryLight;
    final messageColor = isDark
        ? OraColors.textMuted
        : OraColors.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: OraColors.secondary),
            const SizedBox(height: OraSpacing.md),
            Text(title, style: OraTypography.title(titleColor)),
            if (message != null) ...[
              const SizedBox(height: OraSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: OraTypography.body(messageColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
