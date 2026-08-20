import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/config/api_base_url_guard.dart';
import 'package:ora/app/config/environment.dart';

void main() {
  group('resolveApiBaseUrl', () {
    test('allows http in development', () {
      expect(
        resolveApiBaseUrl(
          environment: AppEnvironment.development,
          apiBaseUrl: 'http://10.0.2.2:8080/v1',
        ),
        'http://10.0.2.2:8080/v1',
      );
    });

    test('rejects http in production', () {
      expect(
        () => resolveApiBaseUrl(
          environment: AppEnvironment.production,
          apiBaseUrl: 'http://evil.example/v1',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects http in release mode even for development env', () {
      expect(
        () => resolveApiBaseUrl(
          environment: AppEnvironment.development,
          apiBaseUrl: 'http://10.0.2.2:8080/v1',
          isReleaseMode: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('requires https for staging unless allowInsecureHttp', () {
      expect(
        () => resolveApiBaseUrl(
          environment: AppEnvironment.staging,
          apiBaseUrl: 'http://10.0.2.2:8080/v1',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        resolveApiBaseUrl(
          environment: AppEnvironment.staging,
          apiBaseUrl: 'http://10.0.2.2:8080/v1',
          allowInsecureHttp: true,
        ),
        'http://10.0.2.2:8080/v1',
      );
    });

    test('accepts https production URL', () {
      expect(
        resolveApiBaseUrl(
          environment: AppEnvironment.production,
          apiBaseUrl: 'https://api.ora.app/v1/',
        ),
        'https://api.ora.app/v1',
      );
    });
  });
}
