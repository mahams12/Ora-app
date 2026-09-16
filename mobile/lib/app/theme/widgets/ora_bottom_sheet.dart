import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';

/// Shows an Ora-styled modal bottom sheet with handle, safe area, and keyboard inset.
Future<T?> showOraBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
  bool enableDrag = true,
  double? maxHeightFactor,
}) {
  final factor = maxHeightFactor ?? 0.92;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      final maxHeight = MediaQuery.sizeOf(context).height * factor;
      return Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: OraBottomSheetScaffold(child: child),
          ),
        ),
      );
    },
  );
}

/// Visual sheet chrome — rounded top, handle, elevated surface.
class OraBottomSheetScaffold extends StatelessWidget {
  const OraBottomSheetScaffold({
    required this.child,
    super.key,
    this.showHandle = true,
    this.padding = const EdgeInsets.fromLTRB(
      OraSpacing.sheetHorizontal,
      OraSpacing.xs,
      OraSpacing.sheetHorizontal,
      OraSpacing.md,
    ),
  });

  final Widget child;
  final bool showHandle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? OraColors.surfaceElevated : Colors.white;

    return Material(
      color: bg,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [if (showHandle) const OraSheetHandle(), child],
          ),
        ),
      ),
    );
  }
}

class OraSheetHandle extends StatelessWidget {
  const OraSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.sm),
      child: Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: isDark ? OraColors.border : const Color(0xFFD0D5DD),
            borderRadius: BorderRadius.circular(OraRadius.pill),
          ),
        ),
      ),
    );
  }
}
