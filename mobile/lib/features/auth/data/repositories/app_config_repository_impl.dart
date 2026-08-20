import '../../domain/entities/app_bootstrap.dart';
import '../../domain/repositories/app_config_repository.dart';
import '../data_sources/app_config_local_data_source.dart';

class AppConfigRepositoryImpl implements AppConfigRepository {
  const AppConfigRepositoryImpl(this._localDataSource);

  final AppConfigLocalDataSource _localDataSource;

  @override
  Future<AppBootstrap> loadBootstrap() => _localDataSource.loadBootstrap();
}
