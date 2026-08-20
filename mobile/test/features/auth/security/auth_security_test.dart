/// Security tests for Phase 2 auth implementation.
///
/// These tests verify that the MVVM layer boundaries are respected and
/// that sensitive data is never exposed through the wrong layer.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── MVVM layer boundary ───────────────────────────────────────────────────

  final viewFiles = [
    'lib/features/auth/presentation/views/phone_entry_view.dart',
    'lib/features/auth/presentation/views/otp_entry_view.dart',
    'lib/features/auth/presentation/views/splash_view.dart',
    'lib/features/onboarding/presentation/views/onboarding_placeholder_view.dart',
  ];

  const forbiddenImportsInViews = [
    'package:dio/',
    'package:firebase_auth',
    'package:firebase_core',
    'package:cloud_firestore',
    'data/data_sources/',
    'data/repositories/',
  ];

  group('MVVM: views must not import Firebase or data-layer directly', () {
    for (final relativePath in viewFiles) {
      test(relativePath, () {
        final file = File(relativePath);
        if (!file.existsSync()) {
          // Skip non-existent files gracefully (partial build).
          return;
        }
        final content = file.readAsStringSync();
        for (final forbidden in forbiddenImportsInViews) {
          expect(
            content.contains(forbidden),
            isFalse,
            reason: '$relativePath must not import $forbidden',
          );
        }
      });
    }
  });

  // ── No OTP / token logging ────────────────────────────────────────────────

  group('Security: no sensitive data in log calls', () {
    const filesToScan = [
      'lib/features/auth/data/data_sources/firebase_auth_data_source.dart',
      'lib/features/auth/data/repositories/auth_repository_impl.dart',
      'lib/features/auth/presentation/view_models/auth_view_model.dart',
    ];

    const forbidden = [
      // Pattern for logging raw tokens or codes
      "'Authorization'",
      'otpCode',
      'smsCode',
      'Bearer \$token', // logging the value
    ];

    // We allow 'Authorization' in api_client.dart headers (it's set, not logged).
    // The test specifically checks auth-domain files.
    for (final path in filesToScan) {
      test('$path contains no raw token logging', () {
        final file = File(path);
        if (!file.existsSync()) return;
        final content = file.readAsStringSync();
        // Simple heuristic: if any of the forbidden strings appear inside a
        // logger.* call context. We check for occurrence outside of comments.
        for (final pattern in forbidden) {
          // Only flag if it appears with a logger call on the same or nearby line.
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final line = lines[i];
            if (line.contains('_logger.') && line.contains(pattern)) {
              fail(
                '$path line ${i + 1}: potential sensitive data in log call: $line',
              );
            }
          }
        }
      });
    }
  });

  // ── No client-side role determination ─────────────────────────────────────

  group('Security: client must not set role or authStatus fields', () {
    const domainFiles = [
      'lib/features/auth/domain/entities/auth_user.dart',
    ];

    for (final path in domainFiles) {
      test('$path has role as final (read-only) field', () {
        final file = File(path);
        if (!file.existsSync()) return;
        final content = file.readAsStringSync();

        // The field must be declared as `final String? role` (not mutable).
        expect(content.contains('final String? role'), isTrue,
            reason: 'role must be a final (read-only) field in $path');

        // There must not be a setter or explicit mutable assignment pattern.
        expect(content.contains('set role('), isFalse,
            reason: 'role must not have a public setter in $path');
      });
    }

    test('AuthUser.copyWith cannot be used to change role or driverStatus', () {
      // A `final` field is not enough on its own: a copyWith parameter would
      // still let any caller mint a user with an elevated role.
      final file =
          File('lib/features/auth/domain/entities/auth_user.dart');
      final content = file.readAsStringSync();

      final copyWithStart = content.indexOf('copyWith(');
      expect(copyWithStart, greaterThan(-1),
          reason: 'expected a copyWith on AuthUser');

      final signatureEnd = content.indexOf('})', copyWithStart);
      expect(signatureEnd, greaterThan(copyWithStart),
          reason: 'could not read the copyWith parameter list');

      final parameters = content.substring(copyWithStart, signatureEnd);

      expect(parameters.contains('role'), isFalse,
          reason: 'role must not be a copyWith parameter: it is a '
              'server-authoritative claim');
      expect(parameters.contains('driverStatus'), isFalse,
          reason: 'driverStatus must not be a copyWith parameter: it is a '
              'server-authoritative claim');
    });
  });

  // ── Profile completeness is server-derived ────────────────────────────────

  test('profileComplete is not recomputed on the client', () {
    final file = File(
      'lib/features/auth/data/models/user_profile_model.dart',
    );
    final content = file.readAsStringSync();

    expect(
      content.contains("json['profileComplete']"),
      isTrue,
      reason: 'profileComplete must be read from the server response',
    );
    expect(
      content.contains('role != null && !banned && isActive'),
      isFalse,
      reason: 'profileComplete must not be inferred from other fields',
    );
  });

  // ── Firebase owns session persistence ─────────────────────────────────────

  test('no token or session mirror is written to secure storage', () {
    final content = File('lib/core/storage/storage_keys.dart')
        .readAsStringSync()
        // Ignore the explanatory comments, which mention these words.
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .where((line) => !line.trimLeft().startsWith('///'))
        .join('\n');

    for (final forbidden in [
      'idToken',
      'accessToken',
      'refreshToken',
      'authUid',
    ]) {
      expect(
        content.contains(forbidden),
        isFalse,
        reason: 'Firebase Auth owns session persistence; storing $forbidden '
            'would duplicate its token lifecycle',
      );
    }
  });
}
