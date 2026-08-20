import 'package:freezed_annotation/freezed_annotation.dart';

import '../errors/app_failure.dart';

part 'view_state.freezed.dart';

/// Generic presentation state union for ViewModels.
@Freezed(genericArgumentFactories: true)
sealed class ViewState<T> with _$ViewState<T> {
  const factory ViewState.initial() = InitialViewState<T>;
  const factory ViewState.loading() = LoadingViewState<T>;
  const factory ViewState.loaded(T data) = LoadedViewState<T>;
  const factory ViewState.empty({String? message}) = EmptyViewState<T>;
  const factory ViewState.error(AppFailure failure) = ErrorViewState<T>;
}
