import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MVVM layer boundaries', () {
    final viewFiles = [
      'lib/features/auth/presentation/views/splash_view.dart',
      'lib/features/auth/presentation/views/phone_entry_view.dart',
      'lib/features/auth/presentation/views/otp_entry_view.dart',
      'lib/features/onboarding/presentation/views/onboarding_placeholder_view.dart',
      'lib/features/passenger/presentation/views/home_shell_view.dart',
    ];

    const forbiddenImports = [
      'package:dio/',
      'package:firebase_',
      'package:cloud_firestore',
      'package:firebase_database',
      'data/data_sources/',
      'data/repositories/',
    ];

    for (final relativePath in viewFiles) {
      test('$relativePath has no direct infrastructure imports', () {
        final file = File(relativePath);
        final content = file.readAsStringSync();

        for (final forbidden in forbiddenImports) {
          expect(
            content.contains(forbidden),
            isFalse,
            reason: '$relativePath must not import $forbidden',
          );
        }
      });
    }
  });
}
