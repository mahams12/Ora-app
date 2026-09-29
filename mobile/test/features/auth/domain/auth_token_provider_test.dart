import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/network/auth_token_provider.dart';

void main() {
  group('FirebaseAuthTokenProvider', () {
    test('getAccessToken returns token from getIdToken(false)', () async {
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (forceRefresh) async =>
            forceRefresh ? 'refreshed' : 'current',
      );
      expect(await provider.getAccessToken(), 'current');
    });

    test('forceRefresh calls getIdToken(true)', () async {
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (forceRefresh) async =>
            forceRefresh ? 'refreshed' : 'current',
      );
      expect(await provider.forceRefresh(), 'refreshed');
    });

    test('concurrent forceRefresh calls are single-flight', () async {
      var callCount = 0;
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (forceRefresh) async {
          if (forceRefresh) callCount++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'token';
        },
      );

      // Issue 3 concurrent refresh requests.
      final results = await Future.wait([
        provider.forceRefresh(),
        provider.forceRefresh(),
        provider.forceRefresh(),
      ]);

      // Only one refresh call should have been made.
      expect(callCount, 1);
      expect(results, everyElement('token'));
    });

    test('getIdToken hang times out instead of blocking forever', () async {
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (_) async {
          await Future<void>.delayed(const Duration(seconds: 30));
          return 'late';
        },
        idTokenTimeout: const Duration(milliseconds: 50),
      );
      expect(await provider.getAccessToken(), isNull);
    });

    test('concurrent callers recover when refresh times out', () async {
      var refreshCalls = 0;
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (forceRefresh) async {
          if (forceRefresh) {
            refreshCalls++;
            await Future<void>.delayed(const Duration(seconds: 30));
            return 'refreshed';
          }
          return 'cached';
        },
        idTokenTimeout: const Duration(milliseconds: 50),
      );

      final refresh = provider.forceRefresh();
      final joined = provider.getAccessToken();
      expect(await refresh, isNull);
      expect(await joined, isNull);
      expect(refreshCalls, 1);
      expect(await provider.getAccessToken(), 'cached');
    });

    test('after refresh completes, second forceRefresh issues new call', () async {
      var callCount = 0;
      final provider = FirebaseAuthTokenProvider(
        getIdToken: (forceRefresh) async {
          if (forceRefresh) callCount++;
          return 'token_$callCount';
        },
      );

      await provider.forceRefresh(); // first
      await provider.forceRefresh(); // second — new flight
      expect(callCount, 2);
    });
  });

  group('NoAuthTokenProvider', () {
    test('returns null', () async {
      const provider = NoAuthTokenProvider();
      expect(await provider.getAccessToken(), isNull);
    });
  });
}
