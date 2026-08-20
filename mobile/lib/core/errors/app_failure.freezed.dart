// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_failure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$AppFailure {
  String? get message => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppFailureCopyWith<AppFailure> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppFailureCopyWith<$Res> {
  factory $AppFailureCopyWith(
    AppFailure value,
    $Res Function(AppFailure) then,
  ) = _$AppFailureCopyWithImpl<$Res, AppFailure>;
  @useResult
  $Res call({String? message});
}

/// @nodoc
class _$AppFailureCopyWithImpl<$Res, $Val extends AppFailure>
    implements $AppFailureCopyWith<$Res> {
  _$AppFailureCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _value.copyWith(
            message: freezed == message
                ? _value.message
                : message // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$NetworkFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$NetworkFailureImplCopyWith(
    _$NetworkFailureImpl value,
    $Res Function(_$NetworkFailureImpl) then,
  ) = __$$NetworkFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, int? statusCode, String? code});
}

/// @nodoc
class __$$NetworkFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$NetworkFailureImpl>
    implements _$$NetworkFailureImplCopyWith<$Res> {
  __$$NetworkFailureImplCopyWithImpl(
    _$NetworkFailureImpl _value,
    $Res Function(_$NetworkFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = freezed,
    Object? statusCode = freezed,
    Object? code = freezed,
  }) {
    return _then(
      _$NetworkFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        statusCode: freezed == statusCode
            ? _value.statusCode
            : statusCode // ignore: cast_nullable_to_non_nullable
                  as int?,
        code: freezed == code
            ? _value.code
            : code // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$NetworkFailureImpl extends NetworkFailure {
  const _$NetworkFailureImpl({this.message, this.statusCode, this.code})
    : super._();

  @override
  final String? message;
  @override
  final int? statusCode;
  @override
  final String? code;

  @override
  String toString() {
    return 'AppFailure.network(message: $message, statusCode: $statusCode, code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NetworkFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.statusCode, statusCode) ||
                other.statusCode == statusCode) &&
            (identical(other.code, code) || other.code == code));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, statusCode, code);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NetworkFailureImplCopyWith<_$NetworkFailureImpl> get copyWith =>
      __$$NetworkFailureImplCopyWithImpl<_$NetworkFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return network(message, statusCode, code);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return network?.call(message, statusCode, code);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(message, statusCode, code);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return network(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return network?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(this);
    }
    return orElse();
  }
}

abstract class NetworkFailure extends AppFailure {
  const factory NetworkFailure({
    final String? message,
    final int? statusCode,
    final String? code,
  }) = _$NetworkFailureImpl;
  const NetworkFailure._() : super._();

  @override
  String? get message;
  int? get statusCode;
  String? get code;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NetworkFailureImplCopyWith<_$NetworkFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TimeoutFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$TimeoutFailureImplCopyWith(
    _$TimeoutFailureImpl value,
    $Res Function(_$TimeoutFailureImpl) then,
  ) = __$$TimeoutFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$TimeoutFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$TimeoutFailureImpl>
    implements _$$TimeoutFailureImplCopyWith<$Res> {
  __$$TimeoutFailureImplCopyWithImpl(
    _$TimeoutFailureImpl _value,
    $Res Function(_$TimeoutFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$TimeoutFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$TimeoutFailureImpl extends TimeoutFailure {
  const _$TimeoutFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.timeout(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TimeoutFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TimeoutFailureImplCopyWith<_$TimeoutFailureImpl> get copyWith =>
      __$$TimeoutFailureImplCopyWithImpl<_$TimeoutFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return timeout(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return timeout?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (timeout != null) {
      return timeout(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return timeout(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return timeout?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (timeout != null) {
      return timeout(this);
    }
    return orElse();
  }
}

abstract class TimeoutFailure extends AppFailure {
  const factory TimeoutFailure({final String? message}) = _$TimeoutFailureImpl;
  const TimeoutFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TimeoutFailureImplCopyWith<_$TimeoutFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$UnauthorizedFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$UnauthorizedFailureImplCopyWith(
    _$UnauthorizedFailureImpl value,
    $Res Function(_$UnauthorizedFailureImpl) then,
  ) = __$$UnauthorizedFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$UnauthorizedFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$UnauthorizedFailureImpl>
    implements _$$UnauthorizedFailureImplCopyWith<$Res> {
  __$$UnauthorizedFailureImplCopyWithImpl(
    _$UnauthorizedFailureImpl _value,
    $Res Function(_$UnauthorizedFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$UnauthorizedFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$UnauthorizedFailureImpl extends UnauthorizedFailure {
  const _$UnauthorizedFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.unauthorized(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UnauthorizedFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UnauthorizedFailureImplCopyWith<_$UnauthorizedFailureImpl> get copyWith =>
      __$$UnauthorizedFailureImplCopyWithImpl<_$UnauthorizedFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return unauthorized(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return unauthorized?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (unauthorized != null) {
      return unauthorized(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return unauthorized(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return unauthorized?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (unauthorized != null) {
      return unauthorized(this);
    }
    return orElse();
  }
}

abstract class UnauthorizedFailure extends AppFailure {
  const factory UnauthorizedFailure({final String? message}) =
      _$UnauthorizedFailureImpl;
  const UnauthorizedFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UnauthorizedFailureImplCopyWith<_$UnauthorizedFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ForbiddenFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$ForbiddenFailureImplCopyWith(
    _$ForbiddenFailureImpl value,
    $Res Function(_$ForbiddenFailureImpl) then,
  ) = __$$ForbiddenFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$ForbiddenFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$ForbiddenFailureImpl>
    implements _$$ForbiddenFailureImplCopyWith<$Res> {
  __$$ForbiddenFailureImplCopyWithImpl(
    _$ForbiddenFailureImpl _value,
    $Res Function(_$ForbiddenFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$ForbiddenFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ForbiddenFailureImpl extends ForbiddenFailure {
  const _$ForbiddenFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.forbidden(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ForbiddenFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ForbiddenFailureImplCopyWith<_$ForbiddenFailureImpl> get copyWith =>
      __$$ForbiddenFailureImplCopyWithImpl<_$ForbiddenFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return forbidden(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return forbidden?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (forbidden != null) {
      return forbidden(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return forbidden(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return forbidden?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (forbidden != null) {
      return forbidden(this);
    }
    return orElse();
  }
}

abstract class ForbiddenFailure extends AppFailure {
  const factory ForbiddenFailure({final String? message}) =
      _$ForbiddenFailureImpl;
  const ForbiddenFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ForbiddenFailureImplCopyWith<_$ForbiddenFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$NotFoundFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$NotFoundFailureImplCopyWith(
    _$NotFoundFailureImpl value,
    $Res Function(_$NotFoundFailureImpl) then,
  ) = __$$NotFoundFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$NotFoundFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$NotFoundFailureImpl>
    implements _$$NotFoundFailureImplCopyWith<$Res> {
  __$$NotFoundFailureImplCopyWithImpl(
    _$NotFoundFailureImpl _value,
    $Res Function(_$NotFoundFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$NotFoundFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$NotFoundFailureImpl extends NotFoundFailure {
  const _$NotFoundFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.notFound(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotFoundFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotFoundFailureImplCopyWith<_$NotFoundFailureImpl> get copyWith =>
      __$$NotFoundFailureImplCopyWithImpl<_$NotFoundFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return notFound(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return notFound?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (notFound != null) {
      return notFound(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return notFound(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return notFound?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (notFound != null) {
      return notFound(this);
    }
    return orElse();
  }
}

abstract class NotFoundFailure extends AppFailure {
  const factory NotFoundFailure({final String? message}) =
      _$NotFoundFailureImpl;
  const NotFoundFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotFoundFailureImplCopyWith<_$NotFoundFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ValidationFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$ValidationFailureImplCopyWith(
    _$ValidationFailureImpl value,
    $Res Function(_$ValidationFailureImpl) then,
  ) = __$$ValidationFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, Map<String, List<String>>? fieldErrors});
}

/// @nodoc
class __$$ValidationFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$ValidationFailureImpl>
    implements _$$ValidationFailureImplCopyWith<$Res> {
  __$$ValidationFailureImplCopyWithImpl(
    _$ValidationFailureImpl _value,
    $Res Function(_$ValidationFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? fieldErrors = freezed}) {
    return _then(
      _$ValidationFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        fieldErrors: freezed == fieldErrors
            ? _value._fieldErrors
            : fieldErrors // ignore: cast_nullable_to_non_nullable
                  as Map<String, List<String>>?,
      ),
    );
  }
}

/// @nodoc

class _$ValidationFailureImpl extends ValidationFailure {
  const _$ValidationFailureImpl({
    this.message,
    final Map<String, List<String>>? fieldErrors,
  }) : _fieldErrors = fieldErrors,
       super._();

  @override
  final String? message;
  final Map<String, List<String>>? _fieldErrors;
  @override
  Map<String, List<String>>? get fieldErrors {
    final value = _fieldErrors;
    if (value == null) return null;
    if (_fieldErrors is EqualUnmodifiableMapView) return _fieldErrors;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'AppFailure.validation(message: $message, fieldErrors: $fieldErrors)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ValidationFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            const DeepCollectionEquality().equals(
              other._fieldErrors,
              _fieldErrors,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    message,
    const DeepCollectionEquality().hash(_fieldErrors),
  );

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ValidationFailureImplCopyWith<_$ValidationFailureImpl> get copyWith =>
      __$$ValidationFailureImplCopyWithImpl<_$ValidationFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return validation(message, fieldErrors);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return validation?.call(message, fieldErrors);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (validation != null) {
      return validation(message, fieldErrors);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return validation(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return validation?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (validation != null) {
      return validation(this);
    }
    return orElse();
  }
}

abstract class ValidationFailure extends AppFailure {
  const factory ValidationFailure({
    final String? message,
    final Map<String, List<String>>? fieldErrors,
  }) = _$ValidationFailureImpl;
  const ValidationFailure._() : super._();

  @override
  String? get message;
  Map<String, List<String>>? get fieldErrors;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ValidationFailureImplCopyWith<_$ValidationFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ConflictFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$ConflictFailureImplCopyWith(
    _$ConflictFailureImpl value,
    $Res Function(_$ConflictFailureImpl) then,
  ) = __$$ConflictFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, String? code});
}

/// @nodoc
class __$$ConflictFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$ConflictFailureImpl>
    implements _$$ConflictFailureImplCopyWith<$Res> {
  __$$ConflictFailureImplCopyWithImpl(
    _$ConflictFailureImpl _value,
    $Res Function(_$ConflictFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? code = freezed}) {
    return _then(
      _$ConflictFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        code: freezed == code
            ? _value.code
            : code // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$ConflictFailureImpl extends ConflictFailure {
  const _$ConflictFailureImpl({this.message, this.code}) : super._();

  @override
  final String? message;
  @override
  final String? code;

  @override
  String toString() {
    return 'AppFailure.conflict(message: $message, code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConflictFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.code, code) || other.code == code));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, code);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConflictFailureImplCopyWith<_$ConflictFailureImpl> get copyWith =>
      __$$ConflictFailureImplCopyWithImpl<_$ConflictFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return conflict(message, code);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return conflict?.call(message, code);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (conflict != null) {
      return conflict(message, code);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return conflict(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return conflict?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (conflict != null) {
      return conflict(this);
    }
    return orElse();
  }
}

abstract class ConflictFailure extends AppFailure {
  const factory ConflictFailure({final String? message, final String? code}) =
      _$ConflictFailureImpl;
  const ConflictFailure._() : super._();

  @override
  String? get message;
  String? get code;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConflictFailureImplCopyWith<_$ConflictFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ServerFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$ServerFailureImplCopyWith(
    _$ServerFailureImpl value,
    $Res Function(_$ServerFailureImpl) then,
  ) = __$$ServerFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, int? statusCode});
}

/// @nodoc
class __$$ServerFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$ServerFailureImpl>
    implements _$$ServerFailureImplCopyWith<$Res> {
  __$$ServerFailureImplCopyWithImpl(
    _$ServerFailureImpl _value,
    $Res Function(_$ServerFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? statusCode = freezed}) {
    return _then(
      _$ServerFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        statusCode: freezed == statusCode
            ? _value.statusCode
            : statusCode // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$ServerFailureImpl extends ServerFailure {
  const _$ServerFailureImpl({this.message, this.statusCode}) : super._();

  @override
  final String? message;
  @override
  final int? statusCode;

  @override
  String toString() {
    return 'AppFailure.server(message: $message, statusCode: $statusCode)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ServerFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.statusCode, statusCode) ||
                other.statusCode == statusCode));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, statusCode);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ServerFailureImplCopyWith<_$ServerFailureImpl> get copyWith =>
      __$$ServerFailureImplCopyWithImpl<_$ServerFailureImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return server(message, statusCode);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return server?.call(message, statusCode);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (server != null) {
      return server(message, statusCode);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return server(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return server?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (server != null) {
      return server(this);
    }
    return orElse();
  }
}

abstract class ServerFailure extends AppFailure {
  const factory ServerFailure({final String? message, final int? statusCode}) =
      _$ServerFailureImpl;
  const ServerFailure._() : super._();

  @override
  String? get message;
  int? get statusCode;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ServerFailureImplCopyWith<_$ServerFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$UnknownFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$UnknownFailureImplCopyWith(
    _$UnknownFailureImpl value,
    $Res Function(_$UnknownFailureImpl) then,
  ) = __$$UnknownFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, Object? cause});
}

/// @nodoc
class __$$UnknownFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$UnknownFailureImpl>
    implements _$$UnknownFailureImplCopyWith<$Res> {
  __$$UnknownFailureImplCopyWithImpl(
    _$UnknownFailureImpl _value,
    $Res Function(_$UnknownFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? cause = freezed}) {
    return _then(
      _$UnknownFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        cause: freezed == cause ? _value.cause : cause,
      ),
    );
  }
}

/// @nodoc

class _$UnknownFailureImpl extends UnknownFailure {
  const _$UnknownFailureImpl({this.message, this.cause}) : super._();

  @override
  final String? message;
  @override
  final Object? cause;

  @override
  String toString() {
    return 'AppFailure.unknown(message: $message, cause: $cause)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UnknownFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            const DeepCollectionEquality().equals(other.cause, cause));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    message,
    const DeepCollectionEquality().hash(cause),
  );

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UnknownFailureImplCopyWith<_$UnknownFailureImpl> get copyWith =>
      __$$UnknownFailureImplCopyWithImpl<_$UnknownFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return unknown(message, cause);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return unknown?.call(message, cause);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown(message, cause);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return unknown(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return unknown?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown(this);
    }
    return orElse();
  }
}

abstract class UnknownFailure extends AppFailure {
  const factory UnknownFailure({final String? message, final Object? cause}) =
      _$UnknownFailureImpl;
  const UnknownFailure._() : super._();

  @override
  String? get message;
  Object? get cause;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UnknownFailureImplCopyWith<_$UnknownFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$InvalidPhoneFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$InvalidPhoneFailureImplCopyWith(
    _$InvalidPhoneFailureImpl value,
    $Res Function(_$InvalidPhoneFailureImpl) then,
  ) = __$$InvalidPhoneFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$InvalidPhoneFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$InvalidPhoneFailureImpl>
    implements _$$InvalidPhoneFailureImplCopyWith<$Res> {
  __$$InvalidPhoneFailureImplCopyWithImpl(
    _$InvalidPhoneFailureImpl _value,
    $Res Function(_$InvalidPhoneFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$InvalidPhoneFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$InvalidPhoneFailureImpl extends InvalidPhoneFailure {
  const _$InvalidPhoneFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.invalidPhone(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvalidPhoneFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InvalidPhoneFailureImplCopyWith<_$InvalidPhoneFailureImpl> get copyWith =>
      __$$InvalidPhoneFailureImplCopyWithImpl<_$InvalidPhoneFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return invalidPhone(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return invalidPhone?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (invalidPhone != null) {
      return invalidPhone(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return invalidPhone(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return invalidPhone?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (invalidPhone != null) {
      return invalidPhone(this);
    }
    return orElse();
  }
}

abstract class InvalidPhoneFailure extends AppFailure {
  const factory InvalidPhoneFailure({final String? message}) =
      _$InvalidPhoneFailureImpl;
  const InvalidPhoneFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InvalidPhoneFailureImplCopyWith<_$InvalidPhoneFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$InvalidOtpFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$InvalidOtpFailureImplCopyWith(
    _$InvalidOtpFailureImpl value,
    $Res Function(_$InvalidOtpFailureImpl) then,
  ) = __$$InvalidOtpFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$InvalidOtpFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$InvalidOtpFailureImpl>
    implements _$$InvalidOtpFailureImplCopyWith<$Res> {
  __$$InvalidOtpFailureImplCopyWithImpl(
    _$InvalidOtpFailureImpl _value,
    $Res Function(_$InvalidOtpFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$InvalidOtpFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$InvalidOtpFailureImpl extends InvalidOtpFailure {
  const _$InvalidOtpFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.invalidOtp(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InvalidOtpFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$InvalidOtpFailureImplCopyWith<_$InvalidOtpFailureImpl> get copyWith =>
      __$$InvalidOtpFailureImplCopyWithImpl<_$InvalidOtpFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return invalidOtp(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return invalidOtp?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (invalidOtp != null) {
      return invalidOtp(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return invalidOtp(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return invalidOtp?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (invalidOtp != null) {
      return invalidOtp(this);
    }
    return orElse();
  }
}

abstract class InvalidOtpFailure extends AppFailure {
  const factory InvalidOtpFailure({final String? message}) =
      _$InvalidOtpFailureImpl;
  const InvalidOtpFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$InvalidOtpFailureImplCopyWith<_$InvalidOtpFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$OtpExpiredFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$OtpExpiredFailureImplCopyWith(
    _$OtpExpiredFailureImpl value,
    $Res Function(_$OtpExpiredFailureImpl) then,
  ) = __$$OtpExpiredFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$OtpExpiredFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$OtpExpiredFailureImpl>
    implements _$$OtpExpiredFailureImplCopyWith<$Res> {
  __$$OtpExpiredFailureImplCopyWithImpl(
    _$OtpExpiredFailureImpl _value,
    $Res Function(_$OtpExpiredFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$OtpExpiredFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$OtpExpiredFailureImpl extends OtpExpiredFailure {
  const _$OtpExpiredFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.otpExpired(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OtpExpiredFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OtpExpiredFailureImplCopyWith<_$OtpExpiredFailureImpl> get copyWith =>
      __$$OtpExpiredFailureImplCopyWithImpl<_$OtpExpiredFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return otpExpired(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return otpExpired?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (otpExpired != null) {
      return otpExpired(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return otpExpired(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return otpExpired?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (otpExpired != null) {
      return otpExpired(this);
    }
    return orElse();
  }
}

abstract class OtpExpiredFailure extends AppFailure {
  const factory OtpExpiredFailure({final String? message}) =
      _$OtpExpiredFailureImpl;
  const OtpExpiredFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OtpExpiredFailureImplCopyWith<_$OtpExpiredFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TooManyAttemptsFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$TooManyAttemptsFailureImplCopyWith(
    _$TooManyAttemptsFailureImpl value,
    $Res Function(_$TooManyAttemptsFailureImpl) then,
  ) = __$$TooManyAttemptsFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, Duration? lockDuration});
}

/// @nodoc
class __$$TooManyAttemptsFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$TooManyAttemptsFailureImpl>
    implements _$$TooManyAttemptsFailureImplCopyWith<$Res> {
  __$$TooManyAttemptsFailureImplCopyWithImpl(
    _$TooManyAttemptsFailureImpl _value,
    $Res Function(_$TooManyAttemptsFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? lockDuration = freezed}) {
    return _then(
      _$TooManyAttemptsFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        lockDuration: freezed == lockDuration
            ? _value.lockDuration
            : lockDuration // ignore: cast_nullable_to_non_nullable
                  as Duration?,
      ),
    );
  }
}

/// @nodoc

class _$TooManyAttemptsFailureImpl extends TooManyAttemptsFailure {
  const _$TooManyAttemptsFailureImpl({this.message, this.lockDuration})
    : super._();

  @override
  final String? message;
  @override
  final Duration? lockDuration;

  @override
  String toString() {
    return 'AppFailure.tooManyAttempts(message: $message, lockDuration: $lockDuration)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TooManyAttemptsFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.lockDuration, lockDuration) ||
                other.lockDuration == lockDuration));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, lockDuration);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TooManyAttemptsFailureImplCopyWith<_$TooManyAttemptsFailureImpl>
  get copyWith =>
      __$$TooManyAttemptsFailureImplCopyWithImpl<_$TooManyAttemptsFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return tooManyAttempts(message, lockDuration);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return tooManyAttempts?.call(message, lockDuration);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (tooManyAttempts != null) {
      return tooManyAttempts(message, lockDuration);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return tooManyAttempts(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return tooManyAttempts?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (tooManyAttempts != null) {
      return tooManyAttempts(this);
    }
    return orElse();
  }
}

abstract class TooManyAttemptsFailure extends AppFailure {
  const factory TooManyAttemptsFailure({
    final String? message,
    final Duration? lockDuration,
  }) = _$TooManyAttemptsFailureImpl;
  const TooManyAttemptsFailure._() : super._();

  @override
  String? get message;
  Duration? get lockDuration;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TooManyAttemptsFailureImplCopyWith<_$TooManyAttemptsFailureImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$OtpCooldownFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$OtpCooldownFailureImplCopyWith(
    _$OtpCooldownFailureImpl value,
    $Res Function(_$OtpCooldownFailureImpl) then,
  ) = __$$OtpCooldownFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message, Duration? remaining});
}

/// @nodoc
class __$$OtpCooldownFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$OtpCooldownFailureImpl>
    implements _$$OtpCooldownFailureImplCopyWith<$Res> {
  __$$OtpCooldownFailureImplCopyWithImpl(
    _$OtpCooldownFailureImpl _value,
    $Res Function(_$OtpCooldownFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed, Object? remaining = freezed}) {
    return _then(
      _$OtpCooldownFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
        remaining: freezed == remaining
            ? _value.remaining
            : remaining // ignore: cast_nullable_to_non_nullable
                  as Duration?,
      ),
    );
  }
}

/// @nodoc

class _$OtpCooldownFailureImpl extends OtpCooldownFailure {
  const _$OtpCooldownFailureImpl({this.message, this.remaining}) : super._();

  @override
  final String? message;
  @override
  final Duration? remaining;

  @override
  String toString() {
    return 'AppFailure.otpCooldown(message: $message, remaining: $remaining)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OtpCooldownFailureImpl &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.remaining, remaining) ||
                other.remaining == remaining));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, remaining);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OtpCooldownFailureImplCopyWith<_$OtpCooldownFailureImpl> get copyWith =>
      __$$OtpCooldownFailureImplCopyWithImpl<_$OtpCooldownFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return otpCooldown(message, remaining);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return otpCooldown?.call(message, remaining);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (otpCooldown != null) {
      return otpCooldown(message, remaining);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return otpCooldown(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return otpCooldown?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (otpCooldown != null) {
      return otpCooldown(this);
    }
    return orElse();
  }
}

abstract class OtpCooldownFailure extends AppFailure {
  const factory OtpCooldownFailure({
    final String? message,
    final Duration? remaining,
  }) = _$OtpCooldownFailureImpl;
  const OtpCooldownFailure._() : super._();

  @override
  String? get message;
  Duration? get remaining;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OtpCooldownFailureImplCopyWith<_$OtpCooldownFailureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$AccountDisabledFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$AccountDisabledFailureImplCopyWith(
    _$AccountDisabledFailureImpl value,
    $Res Function(_$AccountDisabledFailureImpl) then,
  ) = __$$AccountDisabledFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$AccountDisabledFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$AccountDisabledFailureImpl>
    implements _$$AccountDisabledFailureImplCopyWith<$Res> {
  __$$AccountDisabledFailureImplCopyWithImpl(
    _$AccountDisabledFailureImpl _value,
    $Res Function(_$AccountDisabledFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$AccountDisabledFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$AccountDisabledFailureImpl extends AccountDisabledFailure {
  const _$AccountDisabledFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.accountDisabled(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AccountDisabledFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AccountDisabledFailureImplCopyWith<_$AccountDisabledFailureImpl>
  get copyWith =>
      __$$AccountDisabledFailureImplCopyWithImpl<_$AccountDisabledFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return accountDisabled(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return accountDisabled?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (accountDisabled != null) {
      return accountDisabled(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return accountDisabled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return accountDisabled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (accountDisabled != null) {
      return accountDisabled(this);
    }
    return orElse();
  }
}

abstract class AccountDisabledFailure extends AppFailure {
  const factory AccountDisabledFailure({final String? message}) =
      _$AccountDisabledFailureImpl;
  const AccountDisabledFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AccountDisabledFailureImplCopyWith<_$AccountDisabledFailureImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$SessionExpiredFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$SessionExpiredFailureImplCopyWith(
    _$SessionExpiredFailureImpl value,
    $Res Function(_$SessionExpiredFailureImpl) then,
  ) = __$$SessionExpiredFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$SessionExpiredFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$SessionExpiredFailureImpl>
    implements _$$SessionExpiredFailureImplCopyWith<$Res> {
  __$$SessionExpiredFailureImplCopyWithImpl(
    _$SessionExpiredFailureImpl _value,
    $Res Function(_$SessionExpiredFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$SessionExpiredFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$SessionExpiredFailureImpl extends SessionExpiredFailure {
  const _$SessionExpiredFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.sessionExpired(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionExpiredFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionExpiredFailureImplCopyWith<_$SessionExpiredFailureImpl>
  get copyWith =>
      __$$SessionExpiredFailureImplCopyWithImpl<_$SessionExpiredFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return sessionExpired(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return sessionExpired?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (sessionExpired != null) {
      return sessionExpired(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return sessionExpired(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return sessionExpired?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (sessionExpired != null) {
      return sessionExpired(this);
    }
    return orElse();
  }
}

abstract class SessionExpiredFailure extends AppFailure {
  const factory SessionExpiredFailure({final String? message}) =
      _$SessionExpiredFailureImpl;
  const SessionExpiredFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionExpiredFailureImplCopyWith<_$SessionExpiredFailureImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$RefreshFailedFailureImplCopyWith<$Res>
    implements $AppFailureCopyWith<$Res> {
  factory _$$RefreshFailedFailureImplCopyWith(
    _$RefreshFailedFailureImpl value,
    $Res Function(_$RefreshFailedFailureImpl) then,
  ) = __$$RefreshFailedFailureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$RefreshFailedFailureImplCopyWithImpl<$Res>
    extends _$AppFailureCopyWithImpl<$Res, _$RefreshFailedFailureImpl>
    implements _$$RefreshFailedFailureImplCopyWith<$Res> {
  __$$RefreshFailedFailureImplCopyWithImpl(
    _$RefreshFailedFailureImpl _value,
    $Res Function(_$RefreshFailedFailureImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$RefreshFailedFailureImpl(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$RefreshFailedFailureImpl extends RefreshFailedFailure {
  const _$RefreshFailedFailureImpl({this.message}) : super._();

  @override
  final String? message;

  @override
  String toString() {
    return 'AppFailure.refreshFailed(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RefreshFailedFailureImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RefreshFailedFailureImplCopyWith<_$RefreshFailedFailureImpl>
  get copyWith =>
      __$$RefreshFailedFailureImplCopyWithImpl<_$RefreshFailedFailureImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String? message, int? statusCode, String? code)
    network,
    required TResult Function(String? message) timeout,
    required TResult Function(String? message) unauthorized,
    required TResult Function(String? message) forbidden,
    required TResult Function(String? message) notFound,
    required TResult Function(
      String? message,
      Map<String, List<String>>? fieldErrors,
    )
    validation,
    required TResult Function(String? message, String? code) conflict,
    required TResult Function(String? message, int? statusCode) server,
    required TResult Function(String? message, Object? cause) unknown,
    required TResult Function(String? message) invalidPhone,
    required TResult Function(String? message) invalidOtp,
    required TResult Function(String? message) otpExpired,
    required TResult Function(String? message, Duration? lockDuration)
    tooManyAttempts,
    required TResult Function(String? message, Duration? remaining) otpCooldown,
    required TResult Function(String? message) accountDisabled,
    required TResult Function(String? message) sessionExpired,
    required TResult Function(String? message) refreshFailed,
  }) {
    return refreshFailed(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String? message, int? statusCode, String? code)? network,
    TResult? Function(String? message)? timeout,
    TResult? Function(String? message)? unauthorized,
    TResult? Function(String? message)? forbidden,
    TResult? Function(String? message)? notFound,
    TResult? Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult? Function(String? message, String? code)? conflict,
    TResult? Function(String? message, int? statusCode)? server,
    TResult? Function(String? message, Object? cause)? unknown,
    TResult? Function(String? message)? invalidPhone,
    TResult? Function(String? message)? invalidOtp,
    TResult? Function(String? message)? otpExpired,
    TResult? Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult? Function(String? message, Duration? remaining)? otpCooldown,
    TResult? Function(String? message)? accountDisabled,
    TResult? Function(String? message)? sessionExpired,
    TResult? Function(String? message)? refreshFailed,
  }) {
    return refreshFailed?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String? message, int? statusCode, String? code)? network,
    TResult Function(String? message)? timeout,
    TResult Function(String? message)? unauthorized,
    TResult Function(String? message)? forbidden,
    TResult Function(String? message)? notFound,
    TResult Function(String? message, Map<String, List<String>>? fieldErrors)?
    validation,
    TResult Function(String? message, String? code)? conflict,
    TResult Function(String? message, int? statusCode)? server,
    TResult Function(String? message, Object? cause)? unknown,
    TResult Function(String? message)? invalidPhone,
    TResult Function(String? message)? invalidOtp,
    TResult Function(String? message)? otpExpired,
    TResult Function(String? message, Duration? lockDuration)? tooManyAttempts,
    TResult Function(String? message, Duration? remaining)? otpCooldown,
    TResult Function(String? message)? accountDisabled,
    TResult Function(String? message)? sessionExpired,
    TResult Function(String? message)? refreshFailed,
    required TResult orElse(),
  }) {
    if (refreshFailed != null) {
      return refreshFailed(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(NetworkFailure value) network,
    required TResult Function(TimeoutFailure value) timeout,
    required TResult Function(UnauthorizedFailure value) unauthorized,
    required TResult Function(ForbiddenFailure value) forbidden,
    required TResult Function(NotFoundFailure value) notFound,
    required TResult Function(ValidationFailure value) validation,
    required TResult Function(ConflictFailure value) conflict,
    required TResult Function(ServerFailure value) server,
    required TResult Function(UnknownFailure value) unknown,
    required TResult Function(InvalidPhoneFailure value) invalidPhone,
    required TResult Function(InvalidOtpFailure value) invalidOtp,
    required TResult Function(OtpExpiredFailure value) otpExpired,
    required TResult Function(TooManyAttemptsFailure value) tooManyAttempts,
    required TResult Function(OtpCooldownFailure value) otpCooldown,
    required TResult Function(AccountDisabledFailure value) accountDisabled,
    required TResult Function(SessionExpiredFailure value) sessionExpired,
    required TResult Function(RefreshFailedFailure value) refreshFailed,
  }) {
    return refreshFailed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(NetworkFailure value)? network,
    TResult? Function(TimeoutFailure value)? timeout,
    TResult? Function(UnauthorizedFailure value)? unauthorized,
    TResult? Function(ForbiddenFailure value)? forbidden,
    TResult? Function(NotFoundFailure value)? notFound,
    TResult? Function(ValidationFailure value)? validation,
    TResult? Function(ConflictFailure value)? conflict,
    TResult? Function(ServerFailure value)? server,
    TResult? Function(UnknownFailure value)? unknown,
    TResult? Function(InvalidPhoneFailure value)? invalidPhone,
    TResult? Function(InvalidOtpFailure value)? invalidOtp,
    TResult? Function(OtpExpiredFailure value)? otpExpired,
    TResult? Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult? Function(OtpCooldownFailure value)? otpCooldown,
    TResult? Function(AccountDisabledFailure value)? accountDisabled,
    TResult? Function(SessionExpiredFailure value)? sessionExpired,
    TResult? Function(RefreshFailedFailure value)? refreshFailed,
  }) {
    return refreshFailed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(NetworkFailure value)? network,
    TResult Function(TimeoutFailure value)? timeout,
    TResult Function(UnauthorizedFailure value)? unauthorized,
    TResult Function(ForbiddenFailure value)? forbidden,
    TResult Function(NotFoundFailure value)? notFound,
    TResult Function(ValidationFailure value)? validation,
    TResult Function(ConflictFailure value)? conflict,
    TResult Function(ServerFailure value)? server,
    TResult Function(UnknownFailure value)? unknown,
    TResult Function(InvalidPhoneFailure value)? invalidPhone,
    TResult Function(InvalidOtpFailure value)? invalidOtp,
    TResult Function(OtpExpiredFailure value)? otpExpired,
    TResult Function(TooManyAttemptsFailure value)? tooManyAttempts,
    TResult Function(OtpCooldownFailure value)? otpCooldown,
    TResult Function(AccountDisabledFailure value)? accountDisabled,
    TResult Function(SessionExpiredFailure value)? sessionExpired,
    TResult Function(RefreshFailedFailure value)? refreshFailed,
    required TResult orElse(),
  }) {
    if (refreshFailed != null) {
      return refreshFailed(this);
    }
    return orElse();
  }
}

abstract class RefreshFailedFailure extends AppFailure {
  const factory RefreshFailedFailure({final String? message}) =
      _$RefreshFailedFailureImpl;
  const RefreshFailedFailure._() : super._();

  @override
  String? get message;

  /// Create a copy of AppFailure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RefreshFailedFailureImplCopyWith<_$RefreshFailedFailureImpl>
  get copyWith => throw _privateConstructorUsedError;
}
