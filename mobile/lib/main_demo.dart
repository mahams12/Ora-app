import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'demo/demo_overrides.dart';

/// ORA — DEMO / DESIGN REVIEW BUILD.
///
/// A fully self-contained entrypoint for frontend review: sign in with ANY
/// phone number and OTP `000000`, every partner registration auto-approves,
/// and all backend data is served from labelled in-memory demo stores.
///
/// Isolation guarantees:
///  - No `Firebase.initializeApp` — the demo never touches Firebase, FCM,
///    App Check, RTDB or the live API.
///  - Every backend seam is replaced via [oraDemoOverrides]; the production
///    `lib/main.dart` entrypoint and provider graph are unchanged.
///  - The persistent DEMO ribbon marks every screen as simulated.
///
/// Build:
///   ORA_DEMO_BUILD=true flutter build apk --release -t lib/main_demo.dart
/// (`ORA_DEMO_BUILD` gives the APK a distinct applicationId + "ORA Demo"
/// launcher name so it can sit next to the real app.)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: oraDemoOverrides(),
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: Banner(
          message: 'DEMO',
          location: BannerLocation.topEnd,
          child: OraApp(),
        ),
      ),
    ),
  );
}
