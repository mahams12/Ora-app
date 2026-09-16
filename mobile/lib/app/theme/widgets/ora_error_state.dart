import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';
import 'ora_button.dart';

class OraErrorState extends StatelessWidget {
  const OraErrorState({
    required this.title,
    super.key,
    this.message,
    this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;

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
            const Icon(Icons.error_outline, size: 48, color: OraColors.danger),
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
            if (onRetry != null) ...[
              const SizedBox(height: OraSpacing.lg),
              OraButton(
                label: 'Try again',
                onPressed: onRetry,
                variant: OraButtonVariant.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
