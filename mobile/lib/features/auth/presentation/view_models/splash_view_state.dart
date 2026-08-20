import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../domain/entities/app_bootstrap.dart';

part 'splash_view_state.freezed.dart';

@freezed
sealed class SplashViewState with _$SplashViewState {
  const factory SplashViewState.initial() = SplashInitial;
  const factory SplashViewState.loading() = SplashLoading;
  const factory SplashViewState.loaded(AppBootstrap bootstrap) = SplashLoaded;
  const factory SplashViewState.error(AppFailure failure) = SplashError;
}
