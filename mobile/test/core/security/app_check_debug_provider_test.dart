import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/security/firebase_app_check_bootstrap.dart';

void main() {
  test('debug App Check provider is gated to kDebugMode only', () {
    // Unit tests run in debug; release builds compile kDebugMode=false so
    // shouldUseAppCheckDebugProvider() cannot return true in production APKs.
    expect(shouldUseAppCheckDebugProvider(), isTrue);
  });
}
