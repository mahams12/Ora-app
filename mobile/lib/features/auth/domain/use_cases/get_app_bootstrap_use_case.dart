import '../entities/app_bootstrap.dart';
import '../repositories/app_config_repository.dart';

class GetAppBootstrapUseCase {
  const GetAppBootstrapUseCase(this._repository);

  final AppConfigRepository _repository;

  Future<AppBootstrap> call() => _repository.loadBootstrap();
}
