import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/config/app_config.dart';
import 'package:ora/app/config/environment.dart';
import 'package:ora/app/di/providers.dart';

void main() {
  group('Provider wiring', () {
    test('appConfigProvider reflects environment override', () {
      final container = ProviderContainer(
        overrides: [
          environmentProvider.overrideWithValue(AppEnvironment.staging),
        ],
      );
      addTearDown(container.dispose);

      final config = container.read(appConfigProvider);
      expect(config.environment, AppEnvironment.staging);
      expect(config.apiBaseUrl, contains('staging'));
    });

    test('getAppBootstrapUseCase resolves from repository chain', () async {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(AppConfig.development()),
        ],
      );
      addTearDown(container.dispose);

      final bootstrap = await container.read(getAppBootstrapUseCaseProvider)();
      expect(bootstrap.appName, 'Ora');
      expect(bootstrap.environmentName, 'Development');
    });
  });
}
