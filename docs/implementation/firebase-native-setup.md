# Firebase Native Setup

**Status:** Native integration prepared — awaiting real config files from the Firebase Console
**Applies to:** `mobile/` (Flutter app)
**Related:** `docs/implementation/phase-02-authentication.md`

## Why this document exists

`mobile/lib/main.dart` calls `Firebase.initializeApp()` with **no** `FirebaseOptions`, and the
repository contains no `firebase_options.dart` / `DefaultFirebaseOptions`. Initialization therefore
resolves the project entirely from the **native** config files. There is no Dart-side fallback: if a
platform's config file is absent, `Firebase.initializeApp()` throws at launch.

This means the Firebase project is chosen purely by which config files are dropped in. No Dart or
Gradle change is needed to point the app at a different project.

## Identifiers

Both platforms already use the same identifier, so both Firebase apps register under one value.

| Platform | Key | Value | Source of truth |
|---|---|---|---|
| Android | `applicationId` | `com.ora.ora` | `mobile/android/app/build.gradle.kts` |
| Android | `namespace` | `com.ora.ora` | `mobile/android/app/build.gradle.kts` |
| iOS | `PRODUCT_BUNDLE_IDENTIFIER` | `com.ora.ora` | `mobile/ios/Runner.xcodeproj/project.pbxproj` |
| Flutter | package name | `ora` | `mobile/pubspec.yaml` |

The iOS test target is `com.ora.ora.RunnerTests`. It does not need a Firebase app registration.

## Required config file locations

These paths are exact. The Gradle plugin and the iOS `firebase_core` plugin look nowhere else.

```
mobile/android/app/google-services.json
mobile/ios/Runner/GoogleService-Info.plist
```

The Android file belongs in the `app` **module** directory, not `mobile/android/`.

Both paths are gitignored via `**/google-services.json` and `**/GoogleService-Info.plist` in the root
`.gitignore`. No placeholder or example versions of either file exist in the repository, and none
should be created — a syntactically valid file containing wrong identifiers fails at runtime with a
far less obvious error than a missing file does.

## Android

The Google Services Gradle plugin is wired following the repository's existing Kotlin DSL
convention: the version is pinned once in `settings.gradle.kts` with `apply false`, and the plugin is
applied by ID in the app module.

| Item | Value |
|---|---|
| Plugin ID | `com.google.gms.google-services` |
| Version | `4.5.0` |
| Declared in | `mobile/android/settings.gradle.kts` (`plugins` block, `apply false`) |
| Applied in | `mobile/android/app/build.gradle.kts` (`plugins` block) |

Version `4.5.0` is the latest release and targets JVM 11, which is compatible with the toolchain
already in the repository: AGP 8.9.1, Kotlin 2.1.0, Gradle 8.12, Java 17, `compileSdk` 36,
`minSdk` 24. The plugin must be applied *after* `com.android.application`, because it attaches to the
Android build variants in order to parse the JSON.

`minSdk` is inherited from the Flutter SDK default rather than pinned in the repo. Firebase Auth
requires API 23 or higher, and the current default is 24, so no override is needed. Pinning
`minSdk` explicitly would become necessary only if a future Flutter downgrade lowered that default.

### Expected build behaviour before the JSON is supplied

Applying this plugin makes the Android build **fail by design** until the config file exists:

```
File google-services.json is missing. The Google Services Plugin cannot function without it.
```

This is the intended outcome. The alternative — applying the plugin conditionally on file existence —
would let a misconfigured build succeed and then crash at runtime instead.

Running `./gradlew :app:processDebugGoogleServices` reproduces this failure and prints the locations
the plugin searches. The last entry is `mobile/android/app/google-services.json`, which confirms the
destination path above directly from the plugin rather than from documentation.

Dart-only work is unaffected: `flutter analyze` and `flutter test` do not invoke Gradle.

## iOS

**No iOS source or project files were changed, deliberately.** Every remaining iOS step depends on
values that only exist inside the real `GoogleService-Info.plist`, and fabricating them would produce
a project that compiles but cannot authenticate.

Current state, verified:

- `ios/Runner/GeneratedPluginRegistrant.m` already registers `FLTFirebaseCorePlugin` and
  `FLTFirebaseAuthPlugin`. Native plugin registration is in place.
- `ios/Runner/AppDelegate.swift` calls `GeneratedPluginRegistrant.register(with: self)` and needs
  **no** `FirebaseApp.configure()` call. The `firebase_core` plugin performs configuration itself when
  `Firebase.initializeApp()` runs. Adding a manual call would double-configure the app.
- No `ios/Podfile` or `ios/Podfile.lock` exists. Flutter generates the Podfile on the first iOS
  build; it must not be hand-written, or it will drift from the Flutter-managed pod setup.
- `ios/Runner/Info.plist` contains no `CFBundleURLTypes` entry. This is correct for now, because the
  required value is the reversed client ID from the plist that does not exist yet.

### Steps required after the real plist is supplied

1. Place the file at `mobile/ios/Runner/GoogleService-Info.plist`.
2. Add it to the **Runner target** in Xcode (drag into the Runner group, tick "Copy items if needed"
   and the Runner target). Copying it to disk alone is not enough — if it is not a bundle resource,
   the app ships without it and `Firebase.initializeApp()` throws even though the file is present.
   Confirm afterwards that `project.pbxproj` references `GoogleService-Info.plist`; it currently has
   zero references.
3. Run `cd mobile && flutter build ios --no-codesign` (or `flutter run`) once to let Flutter generate
   the Podfile and resolve the Firebase pods.
4. For phone authentication only: read `REVERSED_CLIENT_ID` from the supplied plist and add it as a
   `CFBundleURLTypes` URL scheme in `ios/Runner/Info.plist`. Take the value from the file; never
   reconstruct it by hand.
5. For phone authentication only: upload an APNs authentication key in the Firebase Console under
   Cloud Messaging. iOS phone auth uses silent push for app verification and falls back to a
   reCAPTCHA web flow without it.

## Manual Firebase Console steps

None of these can be performed from the repository.

1. Register an **Android** app with package name `com.ora.ora`; download `google-services.json`.
2. Register an **iOS** app with bundle ID `com.ora.ora`; download `GoogleService-Info.plist`.
3. Enable **Phone** under Authentication → Sign-in method.
4. Add the debug **SHA-1** (and release SHA-1 when signing is set up) under Project settings → the
   Android app. Android phone auth fails the Play Integrity / reCAPTCHA check without it. Read the
   debug fingerprint with:

   ```bash
   keytool -list -v -alias androiddebugkey \
     -keystore ~/.android/debug.keystore -storepass android -keypass android
   ```

   Note that `mobile/android/app/build.gradle.kts` still signs release builds with the debug key
   (a `flutter create` default), so release signing is a separate, later task.
5. Upload an **APNs key** under Cloud Messaging for iOS phone auth.

## Security notes

- The two config files are **not secrets**. They contain client identifiers that ship inside every
  copy of the app binary and are extractable from any release build. They are gitignored because
  they are per-environment, not because they are confidential. The root `.gitignore` labels them
  accordingly, separately from the real `secrets/` and `.env` entries.
- Service-account JSON keys, APNs `.p8` keys, and keystores must never enter `mobile/`. They belong
  to backend and release-signing infrastructure. A repository scan confirms none are present: no
  `service_account` payloads, no `BEGIN PRIVATE KEY` blocks, no `.p8` / `.p12` / `.jks` /
  `.keystore` files, and no hardcoded `AIza…` API keys or Firebase tokens in tracked source.
- Server-side authority is unchanged by this work. Firebase remains the identity provider only; the
  Ora backend remains the business-state authority, per
  `docs/implementation/phase-02-authentication.md`.
