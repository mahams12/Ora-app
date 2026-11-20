// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ViewState<T> {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ViewStateCopyWith<T, $Res> {
  factory $ViewStateCopyWith(
    ViewState<T> value,
    $Res Function(ViewState<T>) then,
  ) = _$ViewStateCopyWithImpl<T, $Res, ViewState<T>>;
}

/// @nodoc
class _$ViewStateCopyWithImpl<T, $Res, $Val extends ViewState<T>>
    implements $ViewStateCopyWith<T, $Res> {
  _$ViewStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$InitialViewStateImplCopyWith<T, $Res> {
  factory _$$InitialViewStateImplCopyWith(
    _$InitialViewStateImpl<T> value,
    $Res Function(_$InitialViewStateImpl<T>) then,
  ) = __$$InitialViewStateImplCopyWithImpl<T, $Res>;
}

/// @nodoc
class __$$InitialViewStateImplCopyWithImpl<T, $Res>
    extends _$ViewStateCopyWithImpl<T, $Res, _$InitialViewStateImpl<T>>
    implements _$$InitialViewStateImplCopyWith<T, $Res> {
  __$$InitialViewStateImplCopyWithImpl(
    _$InitialViewStateImpl<T> _value,
    $Res Function(_$InitialViewStateImpl<T>) _then,
  ) : super(_value, _then);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InitialViewStateImpl<T> implements InitialViewState<T> {
  const _$InitialViewStateImpl();

  @override
  String toString() {
    return 'ViewState<$T>.initial()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InitialViewStateImpl<T>);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) {
    return initial();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) {
    return initial?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) {
    return initial(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) {
    return initial?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) {
    if (initial != null) {
      return initial(this);
    }
    return orElse();
  }
}

abstract class InitialViewState<T> implements ViewState<T> {
  const factory InitialViewState() = _$InitialViewStateImpl<T>;
}

/// @nodoc
abstract class _$$LoadingViewStateImplCopyWith<T, $Res> {
  factory _$$LoadingViewStateImplCopyWith(
    _$LoadingViewStateImpl<T> value,
    $Res Function(_$LoadingViewStateImpl<T>) then,
  ) = __$$LoadingViewStateImplCopyWithImpl<T, $Res>;
}

/// @nodoc
class __$$LoadingViewStateImplCopyWithImpl<T, $Res>
    extends _$ViewStateCopyWithImpl<T, $Res, _$LoadingViewStateImpl<T>>
    implements _$$LoadingViewStateImplCopyWith<T, $Res> {
  __$$LoadingViewStateImplCopyWithImpl(
    _$LoadingViewStateImpl<T> _value,
    $Res Function(_$LoadingViewStateImpl<T>) _then,
  ) : super(_value, _then);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$LoadingViewStateImpl<T> implements LoadingViewState<T> {
  const _$LoadingViewStateImpl();

  @override
  String toString() {
    return 'ViewState<$T>.loading()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LoadingViewStateImpl<T>);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) {
    return loading();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) {
    return loading?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) {
    return loading(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) {
    return loading?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) {
    if (loading != null) {
      return loading(this);
    }
    return orElse();
  }
}

abstract class LoadingViewState<T> implements ViewState<T> {
  const factory LoadingViewState() = _$LoadingViewStateImpl<T>;
}

/// @nodoc
abstract class _$$LoadedViewStateImplCopyWith<T, $Res> {
  factory _$$LoadedViewStateImplCopyWith(
    _$LoadedViewStateImpl<T> value,
    $Res Function(_$LoadedViewStateImpl<T>) then,
  ) = __$$LoadedViewStateImplCopyWithImpl<T, $Res>;
  @useResult
  $Res call({T data});
}

/// @nodoc
class __$$LoadedViewStateImplCopyWithImpl<T, $Res>
    extends _$ViewStateCopyWithImpl<T, $Res, _$LoadedViewStateImpl<T>>
    implements _$$LoadedViewStateImplCopyWith<T, $Res> {
  __$$LoadedViewStateImplCopyWithImpl(
    _$LoadedViewStateImpl<T> _value,
    $Res Function(_$LoadedViewStateImpl<T>) _then,
  ) : super(_value, _then);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? data = freezed}) {
    return _then(
      _$LoadedViewStateImpl<T>(
        freezed == data
            ? _value.data
            : data // ignore: cast_nullable_to_non_nullable
                  as T,
      ),
    );
  }
}

/// @nodoc

class _$LoadedViewStateImpl<T> implements LoadedViewState<T> {
  const _$LoadedViewStateImpl(this.data);

  @override
  final T data;

  @override
  String toString() {
    return 'ViewState<$T>.loaded(data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$LoadedViewStateImpl<T> &&
            const DeepCollectionEquality().equals(other.data, data));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(data));

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$LoadedViewStateImplCopyWith<T, _$LoadedViewStateImpl<T>> get copyWith =>
      __$$LoadedViewStateImplCopyWithImpl<T, _$LoadedViewStateImpl<T>>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) {
    return loaded(data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) {
    return loaded?.call(data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) {
    return loaded(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) {
    return loaded?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) {
    if (loaded != null) {
      return loaded(this);
    }
    return orElse();
  }
}

abstract class LoadedViewState<T> implements ViewState<T> {
  const factory LoadedViewState(final T data) = _$LoadedViewStateImpl<T>;

  T get data;

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$LoadedViewStateImplCopyWith<T, _$LoadedViewStateImpl<T>> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$EmptyViewStateImplCopyWith<T, $Res> {
  factory _$$EmptyViewStateImplCopyWith(
    _$EmptyViewStateImpl<T> value,
    $Res Function(_$EmptyViewStateImpl<T>) then,
  ) = __$$EmptyViewStateImplCopyWithImpl<T, $Res>;
  @useResult
  $Res call({String? message});
}

/// @nodoc
class __$$EmptyViewStateImplCopyWithImpl<T, $Res>
    extends _$ViewStateCopyWithImpl<T, $Res, _$EmptyViewStateImpl<T>>
    implements _$$EmptyViewStateImplCopyWith<T, $Res> {
  __$$EmptyViewStateImplCopyWithImpl(
    _$EmptyViewStateImpl<T> _value,
    $Res Function(_$EmptyViewStateImpl<T>) _then,
  ) : super(_value, _then);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = freezed}) {
    return _then(
      _$EmptyViewStateImpl<T>(
        message: freezed == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$EmptyViewStateImpl<T> implements EmptyViewState<T> {
  const _$EmptyViewStateImpl({this.message});

  @override
  final String? message;

  @override
  String toString() {
    return 'ViewState<$T>.empty(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EmptyViewStateImpl<T> &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EmptyViewStateImplCopyWith<T, _$EmptyViewStateImpl<T>> get copyWith =>
      __$$EmptyViewStateImplCopyWithImpl<T, _$EmptyViewStateImpl<T>>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) {
    return empty(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) {
    return empty?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) {
    return empty(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) {
    return empty?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) {
    if (empty != null) {
      return empty(this);
    }
    return orElse();
  }
}

abstract class EmptyViewState<T> implements ViewState<T> {
  const factory EmptyViewState({final String? message}) =
      _$EmptyViewStateImpl<T>;

  String? get message;

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EmptyViewStateImplCopyWith<T, _$EmptyViewStateImpl<T>> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ErrorViewStateImplCopyWith<T, $Res> {
  factory _$$ErrorViewStateImplCopyWith(
    _$ErrorViewStateImpl<T> value,
    $Res Function(_$ErrorViewStateImpl<T>) then,
  ) = __$$ErrorViewStateImplCopyWithImpl<T, $Res>;
  @useResult
  $Res call({AppFailure failure});

  $AppFailureCopyWith<$Res> get failure;
}

/// @nodoc
class __$$ErrorViewStateImplCopyWithImpl<T, $Res>
    extends _$ViewStateCopyWithImpl<T, $Res, _$ErrorViewStateImpl<T>>
    implements _$$ErrorViewStateImplCopyWith<T, $Res> {
  __$$ErrorViewStateImplCopyWithImpl(
    _$ErrorViewStateImpl<T> _value,
    $Res Function(_$ErrorViewStateImpl<T>) _then,
  ) : super(_value, _then);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? failure = null}) {
    return _then(
      _$ErrorViewStateImpl<T>(
        null == failure
            ? _value.failure
            : failure // ignore: cast_nullable_to_non_nullable
                  as AppFailure,
      ),
    );
  }

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $AppFailureCopyWith<$Res> get failure {
    return $AppFailureCopyWith<$Res>(_value.failure, (value) {
      return _then(_value.copyWith(failure: value));
    });
  }
}

/// @nodoc

class _$ErrorViewStateImpl<T> implements ErrorViewState<T> {
  const _$ErrorViewStateImpl(this.failure);

  @override
  final AppFailure failure;

  @override
  String toString() {
    return 'ViewState<$T>.error(failure: $failure)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ErrorViewStateImpl<T> &&
            (identical(other.failure, failure) || other.failure == failure));
  }

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ErrorViewStateImplCopyWith<T, _$ErrorViewStateImpl<T>> get copyWith =>
      __$$ErrorViewStateImplCopyWithImpl<T, _$ErrorViewStateImpl<T>>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(T data) loaded,
    required TResult Function(String? message) empty,
    required TResult Function(AppFailure failure) error,
  }) {
    return error(failure);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(T data)? loaded,
    TResult? Function(String? message)? empty,
    TResult? Function(AppFailure failure)? error,
  }) {
    return error?.call(failure);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(T data)? loaded,
    TResult Function(String? message)? empty,
    TResult Function(AppFailure failure)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(failure);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(InitialViewState<T> value) initial,
    required TResult Function(LoadingViewState<T> value) loading,
    required TResult Function(LoadedViewState<T> value) loaded,
    required TResult Function(EmptyViewState<T> value) empty,
    required TResult Function(ErrorViewState<T> value) error,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(InitialViewState<T> value)? initial,
    TResult? Function(LoadingViewState<T> value)? loading,
    TResult? Function(LoadedViewState<T> value)? loaded,
    TResult? Function(EmptyViewState<T> value)? empty,
    TResult? Function(ErrorViewState<T> value)? error,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(InitialViewState<T> value)? initial,
    TResult Function(LoadingViewState<T> value)? loading,
    TResult Function(LoadedViewState<T> value)? loaded,
    TResult Function(EmptyViewState<T> value)? empty,
    TResult Function(ErrorViewState<T> value)? error,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class ErrorViewState<T> implements ViewState<T> {
  const factory ErrorViewState(final AppFailure failure) =
      _$ErrorViewStateImpl<T>;

  AppFailure get failure;

  /// Create a copy of ViewState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ErrorViewStateImplCopyWith<T, _$ErrorViewStateImpl<T>> get copyWith =>
      throw _privateConstructorUsedError;
}
