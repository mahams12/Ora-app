import '../../../../app/config/app_config.dart';
import '../../../../core/constants/app_constants.dart';

class AppBootstrap {
  const AppBootstrap({
    required this.appName,
    required this.environmentName,
    required this.apiBaseUrl,
    required this.clientVersion,
  });

  final String appName;
  final String environmentName;
  final String apiBaseUrl;
  final String clientVersion;

  factory AppBootstrap.fromConfig(AppConfig config) => AppBootstrap(
        appName: AppConstants.appName,
        environmentName: config.environment.displayName,
        apiBaseUrl: config.apiBaseUrl,
        clientVersion: config.clientVersion,
      );
}
