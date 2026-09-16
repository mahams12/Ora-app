import 'package:flutter/animation.dart';

/// Short, purposeful motion durations for design-system interactions.
class OraMotion {
  OraMotion._();

  static const Duration press = Duration(milliseconds: 120);
  static const Duration select = Duration(milliseconds: 180);
  static const Duration sheet = Duration(milliseconds: 280);
  static const Duration fade = Duration(milliseconds: 200);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
}
