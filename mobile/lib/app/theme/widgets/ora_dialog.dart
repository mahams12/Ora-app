import 'package:flutter/material.dart';

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
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        if (cancelLabel != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(cancelLabel),
          ),
        FilledButton(
          onPressed: () {
            onConfirm?.call();
            Navigator.of(context).pop();
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
