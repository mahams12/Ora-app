import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'di/providers.dart';
import 'router/app_router.dart';
import 'theme/ora_theme.dart';

class OraApp extends ConsumerStatefulWidget {
  const OraApp({super.key});

  @override
  ConsumerState<OraApp> createState() => _OraAppState();
}

class _OraAppState extends ConsumerState<OraApp> {
  var _dispatchFcmStarted = false;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final router = ref.watch(appRouterProvider);

    if (!_dispatchFcmStarted) {
      _dispatchFcmStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref.read(dispatchFcmServiceProvider).init(router: router, ref: ref),
        );
      });
    }

    return MaterialApp.router(
      title: 'ORA',
      debugShowCheckedModeBanner: !config.environment.isProduction,
      theme: OraTheme.light(),
      darkTheme: OraTheme.dark(),
      // Prototype is dark-first; product surfaces default to Ora dark.
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}

/// Notifies go_router when [AuthStatus] changes without recreating the router.
class AuthRouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final authRouterRefreshProvider = Provider<AuthRouterRefresh>((ref) {
  final refresh = AuthRouterRefresh();
  ref.listen(authStateNotifierProvider, (previous, next) {
    if (previous != next) {
      refresh.ping();
    }
  });
  ref.onDispose(refresh.dispose);
  return refresh;
});

/// Built once. Redirects re-run when [authRouterRefreshProvider] pings.
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(authRouterRefreshProvider);
  return createAppRouter(ref: ref, refreshListenable: refresh);
});
