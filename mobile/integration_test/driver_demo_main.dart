// Driver demo app for video capture — real widgets + fixed view-model
// states, full animations running (OraFloaty, tap-scale, nav badge slide).
// Auto-cycles shell pages on a timer so `adb screenrecord` captures every
// screen without scripted taps. Dev-only harness; nothing ships.
//
// Run: flutter run -t integration_test/driver_demo_main.dart -d <device>
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ora/app/theme/ora_colors.dart';
import 'package:ora/app/theme/ora_theme.dart';
import 'package:ora/features/auth/presentation/view_models/session_user_profile.dart';
import 'package:ora/features/driver/presentation/views/driver_shell_view.dart';

import 'package:ora/demo/driver_seed.dart';

void main() {
  final container = ProviderContainer(overrides: driverDemoOverrides());
  container.read(sessionUserProfileProvider.notifier).setProfile(demoProfile);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const _DriverDemoApp(),
    ),
  );
}

class _DriverDemoApp extends StatefulWidget {
  const _DriverDemoApp();

  @override
  State<_DriverDemoApp> createState() => _DriverDemoAppState();
}

class _DriverDemoAppState extends State<_DriverDemoApp> {
  static const _pages = [
    DriverShellPage.home,
    DriverShellPage.open,
    DriverShellPage.assigned,
    DriverShellPage.earnings,
    DriverShellPage.profile,
  ];

  var _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() => _index = (_index + 1) % _pages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ORA Driver',
      debugShowCheckedModeBanner: false,
      theme: OraTheme.light(),
      themeMode: ThemeMode.light,
      builder: (context, child) => DecoratedBox(
        decoration: const BoxDecoration(gradient: OraColors.backgroundGradient),
        child: child ?? const SizedBox.shrink(),
      ),
      home: DriverShellView(initialTab: _pages[_index]),
    );
  }
}
