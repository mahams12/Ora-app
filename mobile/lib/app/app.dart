import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'di/providers.dart';
import 'router/app_router.dart';
import 'theme/ora_theme.dart';

class OraApp extends ConsumerWidget {
  const OraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Ora',
      debugShowCheckedModeBanner: !config.environment.isProduction,
      theme: OraTheme.light(),
      darkTheme: OraTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

/// The router is a ChangeNotifier that refreshes when auth state changes,
/// so go_router re-evaluates guards on every auth transition.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Watch auth state so the router is refreshed on status changes.
  ref.watch(authStateNotifierProvider);

  return createAppRouter(ref: ref);
});
