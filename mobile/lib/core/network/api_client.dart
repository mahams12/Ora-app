import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../errors/failure_mapper.dart';
import '../logging/app_logger.dart';
import '../security/app_check_token_provider.dart';
import 'auth_token_provider.dart';
import 'network_config.dart';
import 'request_context.dart';
import 'retry_policy.dart';

typedef RequestContextFactory = RequestContext Function({
  String? correlationId,
  String? idempotencyKey,
  String? operationId,
});

class ApiClient {
  ApiClient({
    required NetworkConfig config,
    required AuthTokenProvider authTokenProvider,
    required AppLogger logger,
    AppCheckTokenProvider? appCheckTokenProvider,
    FailureMapper? failureMapper,
    RetryPolicy? retryPolicy,
    Dio? dio,
    Uuid? uuid,
  })  : _failureMapper = failureMapper ?? const FailureMapper(),
        _retryPolicy = retryPolicy ?? const RetryPolicy(),
        _uuid = uuid ?? const Uuid(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.baseUrl,
                connectTimeout: config.connectTimeout,
                receiveTimeout: config.receiveTimeout,
                sendTimeout: config.sendTimeout,
                headers: {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            ) {
    final interceptor = _OraInterceptors(
      authTokenProvider: authTokenProvider,
      appCheckTokenProvider:
          appCheckTokenProvider ?? const NoAppCheckTokenProvider(),
      logger: logger,
      uuid: _uuid,
      enableLogging: config.enableRequestLogging,
    );
    interceptor.setDio(_dio);
    _dio.interceptors.add(interceptor);
  }

  final Dio _dio;
  final FailureMapper _failureMapper;
  final RetryPolicy _retryPolicy;
  final Uuid _uuid;

  Dio get dio => _dio;

  RequestContext newContext({
    String? correlationId,
    String? idempotencyKey,
    String? operationId,
  }) =>
      RequestContext(
        requestId: _uuid.v4(),
        correlationId: correlationId,
        idempotencyKey: idempotencyKey,
        operationId: operationId,
      );

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    RequestContext? context,
    CancelToken? cancelToken,
  }) =>
      _execute<T>(
        () => _dio.get<T>(
          path,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          options: _options(context, idempotent: true),
        ),
        idempotent: true,
      );

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    RequestContext? context,
    bool idempotent = false,
    CancelToken? cancelToken,
  }) =>
      _execute<T>(
        () => _dio.post<T>(
          path,
          data: data,
          queryParameters: queryParameters,
          cancelToken: cancelToken,
          options: _options(context, idempotent: idempotent),
        ),
        idempotent: idempotent,
      );

  Future<Response<T>> _execute<T>(
    Future<Response<T>> Function() action, {
    required bool idempotent,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } on DioException catch (error, stackTrace) {
        if (_retryPolicy.shouldRetry(error, attempt)) {
          await Future<void>.delayed(_retryPolicy.delayForAttempt(attempt));
          continue;
        }
        Error.throwWithStackTrace(
          _failureMapper.fromDioException(error),
          stackTrace,
        );
      }
    }
  }

  Options _options(RequestContext? context, {required bool idempotent}) {
    final headers = <String, dynamic>{};
    if (context != null) {
      headers['X-Request-Id'] = context.requestId;
      if (context.correlationId != null) {
        headers['X-Correlation-Id'] = context.correlationId;
      }
      if (context.idempotencyKey != null) {
        headers['Idempotency-Key'] = context.idempotencyKey;
      }
    }
    return Options(
      headers: headers,
      extra: {'idempotent': idempotent},
    );
  }
}

class _OraInterceptors extends Interceptor {
  _OraInterceptors({
    required AuthTokenProvider authTokenProvider,
    required AppCheckTokenProvider appCheckTokenProvider,
    required AppLogger logger,
    required Uuid uuid,
    required bool enableLogging,
  })  : _authTokenProvider = authTokenProvider,
        _appCheckTokenProvider = appCheckTokenProvider,
        _logger = logger,
        _uuid = uuid,
        _enableLogging = enableLogging;

  final AuthTokenProvider _authTokenProvider;
  final AppCheckTokenProvider _appCheckTokenProvider;
  final AppLogger _logger;
  final Uuid _uuid;
  final bool _enableLogging;
  Dio? _dio;

  void setDio(Dio dio) => _dio = dio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers.putIfAbsent('X-Request-Id', () => _uuid.v4());
    options.headers.putIfAbsent('X-Client-Version', () => '1.0.0');
    options.headers.putIfAbsent('X-Platform', () => _platformHeader());

    options.extra.putIfAbsent('_clientDio', () => _dio);

    final carriesRefreshedToken = options.extra['_retried'] == true &&
        options.headers.containsKey('Authorization');

    if (!carriesRefreshedToken) {
      final token = await _authTokenProvider.getAccessToken();
      if (token != null && token.isNotEmpty) {
        // NEVER log the token value.
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    // App Check — never log the token value.
    final appCheck = await _appCheckTokenProvider.getToken();
    if (appCheck != null && appCheck.isNotEmpty) {
      options.headers['X-Firebase-AppCheck'] = appCheck;
    }

    if (_enableLogging) {
      _logger.debug(
        'HTTP ${options.method} ${options.uri}',
        metadata: {
          'requestId': options.headers['X-Request-Id'],
          'idempotent': options.extra['idempotent'],
          'hasAppCheck': options.headers.containsKey('X-Firebase-AppCheck'),
        },
      );
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (_enableLogging) {
      _logger.warning(
        'HTTP error ${err.response?.statusCode ?? err.type.name}',
        metadata: {
          'requestId': err.requestOptions.headers['X-Request-Id'],
          'path': err.requestOptions.path,
        },
      );
    }

    if (err.response?.statusCode == 401 &&
        _authTokenProvider is FirebaseAuthTokenProvider &&
        err.requestOptions.extra['_retried'] != true) {
      try {
        // ignore: unnecessary_cast
        final newToken =
            await (_authTokenProvider)
                .forceRefresh();
        if (newToken != null && newToken.isNotEmpty) {
          final retryOptions = err.requestOptions.copyWith();
          retryOptions.headers['Authorization'] = 'Bearer $newToken';
          retryOptions.extra['_retried'] = true;
          final dio = err.requestOptions.extra['_clientDio'] as Dio?;
          if (dio != null) {
            final retryResponse = await dio.fetch<dynamic>(retryOptions);
            handler.resolve(retryResponse);
            return;
          }
        }
      } catch (_) {
        // Refresh failed; propagate the original 401.
      }
    }

    handler.next(err);
  }

  String _platformHeader() => 'mobile';
}
