import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/config/environment.dart';
import 'package:ora/core/errors/app_failure.dart';
import 'package:ora/core/logging/app_logger.dart';
import 'package:ora/core/logging/log_record.dart';
import 'package:ora/core/network/api_client.dart';
import 'package:ora/core/network/auth_token_provider.dart';
import 'package:ora/core/network/network_config.dart';

/// Adapter that rejects stale bearer tokens with 401 and accepts fresh ones,
/// standing in for the Ora backend's token validation.
class _TokenCheckingAdapter implements HttpClientAdapter {
  _TokenCheckingAdapter({required this.acceptedToken, this.responseDelay});

  final String acceptedToken;
  final Duration? responseDelay;

  final List<String?> seenAuthorizationHeaders = [];

  int get callCount => seenAuthorizationHeaders.length;

  static final _jsonHeaders = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seenAuthorizationHeaders.add(options.headers['Authorization'] as String?);

    if (responseDelay != null) {
      await Future<void>.delayed(responseDelay!);
    }

    if (options.headers['Authorization'] == 'Bearer $acceptedToken') {
      return ResponseBody.fromString(
        '{"uid":"uid-1"}',
        200,
        headers: _jsonHeaders,
      );
    }

    return ResponseBody.fromString(
      '{"error":{"code":"SESSION_EXPIRED","message":"token expired"}}',
      401,
      headers: _jsonHeaders,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SilentLogger extends AppLogger {
  @override
  void log(LogRecord record) {}
}

void main() {
  final config = NetworkConfig.fromEnvironment(AppEnvironment.development);

  /// Token provider that hands out a stale token until forced to refresh.
  /// [refreshCount] records how many actual refresh calls were made.
  ({FirebaseAuthTokenProvider provider, int Function() refreshCount})
      tokenProvider({Duration refreshDuration = Duration.zero}) {
    var refreshes = 0;
    final provider = FirebaseAuthTokenProvider(
      getIdToken: (forceRefresh) async {
        if (!forceRefresh) return 'stale';
        refreshes++;
        await Future<void>.delayed(refreshDuration);
        return 'fresh';
      },
    );
    return (provider: provider, refreshCount: () => refreshes);
  }

  ApiClient buildClient(
    _TokenCheckingAdapter adapter,
    AuthTokenProvider provider,
  ) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test/v1'))
      ..httpClientAdapter = adapter;
    return ApiClient(
      config: config,
      authTokenProvider: provider,
      logger: _SilentLogger(),
      dio: dio,
    );
  }

  group('401 recovery', () {
    test('a 401 triggers one refresh and the retry succeeds', () async {
      final adapter = _TokenCheckingAdapter(acceptedToken: 'fresh');
      final token = tokenProvider();
      final client = buildClient(adapter, token.provider);

      final response = await client.get<Map<String, dynamic>>('/auth/me');

      expect(response.statusCode, 200);
      expect(response.data?['uid'], 'uid-1');
      expect(token.refreshCount(), 1, reason: 'exactly one refresh');
      expect(adapter.callCount, 2, reason: 'original request plus one retry');
      expect(
        adapter.seenAuthorizationHeaders,
        ['Bearer stale', 'Bearer fresh'],
      );
    });

    test('the retry is attempted only once, then the 401 surfaces', () async {
      // The refreshed token is still rejected, so the request must not loop.
      final adapter = _TokenCheckingAdapter(acceptedToken: 'never-issued');
      final token = tokenProvider();
      final client = buildClient(adapter, token.provider);

      await expectLater(
        client.get<Map<String, dynamic>>('/auth/me'),
        throwsA(isA<AppFailure>()),
      );

      expect(adapter.callCount, 2, reason: 'no retry storm');
      expect(token.refreshCount(), 1);
    });

    test('no refresh is attempted when no token provider is wired', () async {
      final adapter = _TokenCheckingAdapter(acceptedToken: 'fresh');
      final client = buildClient(adapter, const NoAuthTokenProvider());

      await expectLater(
        client.get<Map<String, dynamic>>('/auth/me'),
        throwsA(isA<SessionExpiredFailure>()),
      );

      expect(adapter.callCount, 1, reason: 'no retry without a refreshable token');
    });
  });

  group('concurrent 401 recovery is single-flight', () {
    test('two simultaneous 401s cause exactly one token refresh', () async {
      // Both the backend and the refresh are slowed so the two requests
      // genuinely overlap.
      final adapter = _TokenCheckingAdapter(
        acceptedToken: 'fresh',
        responseDelay: const Duration(milliseconds: 20),
      );
      final token = tokenProvider(
        refreshDuration: const Duration(milliseconds: 40),
      );
      final client = buildClient(adapter, token.provider);

      final responses = await Future.wait([
        client.get<Map<String, dynamic>>('/auth/me'),
        client.get<Map<String, dynamic>>('/auth/me'),
      ]);

      expect(
        token.refreshCount(),
        1,
        reason: 'the second caller must join the in-flight refresh',
      );
      for (final response in responses) {
        expect(response.statusCode, 200, reason: 'both requests recover');
        expect(response.data?['uid'], 'uid-1');
      }
      expect(adapter.callCount, 4, reason: '2 original + 2 retries');
    });

    test('five simultaneous 401s still cause exactly one refresh', () async {
      final adapter = _TokenCheckingAdapter(
        acceptedToken: 'fresh',
        responseDelay: const Duration(milliseconds: 20),
      );
      final token = tokenProvider(
        refreshDuration: const Duration(milliseconds: 40),
      );
      final client = buildClient(adapter, token.provider);

      final responses = await Future.wait([
        for (var i = 0; i < 5; i++)
          client.get<Map<String, dynamic>>('/auth/me'),
      ]);

      expect(token.refreshCount(), 1);
      expect(responses.every((r) => r.statusCode == 200), isTrue);
    });

    test('a later 401 refreshes again once the first flight has finished',
        () async {
      final adapter = _TokenCheckingAdapter(acceptedToken: 'fresh');
      final token = tokenProvider();
      final client = buildClient(adapter, token.provider);

      await client.get<Map<String, dynamic>>('/auth/me');
      await client.get<Map<String, dynamic>>('/auth/me');

      // The single-flight guard must not latch permanently.
      expect(token.refreshCount(), 2);
    });
  });
}
