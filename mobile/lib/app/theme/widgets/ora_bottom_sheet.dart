import 'package:flutter/material.dart';

import '../ora_radius.dart';

Future<T?> showOraBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(OraRadius.xl)),
    ),
    builder: (context) => SafeArea(child: child),
  );
}
