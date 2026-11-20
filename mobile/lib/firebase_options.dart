import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase options for web builds.
///
/// Android/iOS configure Firebase natively via google-services.json /
/// GoogleService-Info.plist, so this file only serves the web target.
/// `main()` passes these options to [Firebase.initializeApp] only when
/// `kIsWeb` is true.
///
/// The appId is a placeholder — no web app is registered in the Firebase
/// project yet. Web builds are intended to run against the local Firebase
/// Emulator Suite (--dart-define=ORA_FIREBASE_EMULATOR_HOST=127.0.0.1),
/// which does not validate apiKey/appId. Register a real web app in
/// Firebase Console and replace [web] before shipping a production web
/// build.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions is only configured for web. '
      'Native platforms use google-services.json / GoogleService-Info.plist.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD7c36Ib75-RfI_apkBbvDNvAn1HVLjsrQ',
    appId: '1:498169438285:web:0000000000000000000000',
    messagingSenderId: '498169438285',
    projectId: 'ora-app-d8112',
    authDomain: 'ora-app-d8112.firebaseapp.com',
    databaseURL:
        'https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'ora-app-d8112.firebasestorage.app',
  );
}
