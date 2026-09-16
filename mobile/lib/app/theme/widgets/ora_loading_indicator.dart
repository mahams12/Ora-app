import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

class OraLoadingIndicator extends StatelessWidget {
  const OraLoadingIndicator({super.key, this.message, this.expand = true});

  final String? message;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messageColor = isDark
        ? OraColors.textMuted
        : OraColors.textSecondaryLight;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: OraColors.primary,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: OraSpacing.md),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: OraTypography.body(messageColor),
          ),
        ],
      ],
    );

    if (!expand) {
      return content;
    }

    return Center(child: content);
  }
}
