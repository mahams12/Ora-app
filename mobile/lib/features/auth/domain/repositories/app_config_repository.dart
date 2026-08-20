import '../entities/app_bootstrap.dart';

abstract interface class AppConfigRepository {
  Future<AppBootstrap> loadBootstrap();
}
