import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';
import 'ora_button.dart';

Future<T?> showOraDialog<T>({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String? cancelLabel,
  VoidCallback? onConfirm,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return AlertDialog(
        backgroundColor: isDark ? OraColors.surfaceElevated : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OraRadius.modal),
        ),
        title: Text(
          title,
          style: OraTypography.title(
            isDark ? OraColors.textPrimary : OraColors.textPrimaryLight,
          ),
        ),
        content: Text(
          message,
          style: OraTypography.body(
            isDark ? OraColors.textSecondary : OraColors.textSecondaryLight,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          OraSpacing.md,
          0,
          OraSpacing.md,
          OraSpacing.md,
        ),
        actions: [
          if (cancelLabel != null)
            OraButton(
              label: cancelLabel,
              expand: false,
              variant: OraButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          OraButton(
            label: confirmLabel,
            expand: false,
            onPressed: () {
              onConfirm?.call();
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
