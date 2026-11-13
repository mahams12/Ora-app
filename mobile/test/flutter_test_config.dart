import 'dart:async';

import 'package:ora/app/theme/widgets/ora_floaty.dart';

/// Disable the infinite float loop globally so pumpAndSettle() can settle in
/// widget tests. The dedicated floaty test re-enables it to verify motion.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  OraFloaty.debugSkipRepeat = true;
  await testMain();
}
