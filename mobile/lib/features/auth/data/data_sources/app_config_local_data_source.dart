import '../../../../app/config/app_config.dart';
import '../../domain/entities/app_bootstrap.dart';

class AppConfigLocalDataSource {
  const AppConfigLocalDataSource(this._config);

  final AppConfig _config;

  Future<AppBootstrap> loadBootstrap() async {
    // Phase 1: local config only. Remote config fetch in later phases.
    return AppBootstrap.fromConfig(_config);
  }
}
