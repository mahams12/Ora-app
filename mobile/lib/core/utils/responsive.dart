import 'package:flutter/widgets.dart';

class Responsive {
  Responsive._();

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 768;

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 768) {
      return 32;
    }
    if (width >= 400) {
      return 20;
    }
    return 16;
  }

  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 768) {
      return 560;
    }
    return width;
  }
}
