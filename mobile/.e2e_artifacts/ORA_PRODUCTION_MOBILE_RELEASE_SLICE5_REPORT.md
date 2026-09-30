# Ora production hardening — slice 5 (Production Flutter release + Play Integrity)

**Date/time:** 2026-09-30 (PKT)  
**Slices 1–4:** Not reopened.  
**Production backend revision (unchanged):** `ora-auth-service-00001-mwc`

---

## Phase 0 — Mobile configuration inventory

| Area | Finding |
|------|---------|
| Environment | `ORA_ENV` dart-define → `AppEnvironment` (`main.dart`, `providers.dart`) |
| API URL | `ORA_API_BASE_URL` override; else `environment.apiBaseUrl` (`api.ora.app` for production enum — **overridden at build** for Cloud Run) |
| App Check | `ORA_APP_CHECK` dart-define; production release defaults App Check **on** when `ORA_ENV=production` |
| Firebase | `google-services.json` → project `ora-app-d8112`, package `com.ora.ora` |
| App Check bootstrap | `activateOraAppCheck(useDebugProvider: kDebugMode)` → release uses **Play Integrity** |
| API client | `X-Firebase-AppCheck` via `api_client.dart` (never logged) |
| Staging script | `scripts/build_staging_apk.sh` — **debug** APK, `ORA_APP_CHECK=false` |
| Production script | **Added** `scripts/build_production_release.sh` |
| Android signing | `android/app/build.gradle.kts` — release `signingConfig = debug` (no `key.properties` in repo) |
| Flavors | None — dart-define configuration only |

Default production enum URL `https://api.ora.app/v1` is **not** used when `ORA_API_BASE_URL` is set at build (required for current Cloud Run).

---

## 1. Production project

**`ora-app-d8112`**

---

## 2. Android package

**`com.ora.ora`**

---

## 3. Firebase Android app ID

**`1:498169438285:android:3b100b1c7a7248f1ddbc04`**

(`google-services.json` matches package + project.)

---

## 4. Release version / build number

**`1.0.0` / `versionCode=1`** (`pubspec.yaml` / `aapt dump badging`)

---

## 5. Release artifact type

| Artifact | Path | Size (approx.) |
|----------|------|----------------|
| **APK** (release) | `mobile/build/app/outputs/flutter-apk/app-release.apk` | ~55.6 MB |
| **AAB** (release) | `mobile/build/app/outputs/bundle/release/app-release.aab` | ~47.4 MB |

Build command (dart-defines):

`ORA_ENV=production`, `ORA_APP_CHECK=true`, `ORA_API_BASE_URL=https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/v1`

---

## 6. Signing status

| Item | Status |
|------|--------|
| `android/key.properties` | **Not present** (gitignored pattern only) |
| Release keystore | **Not configured** |
| Effective signing | **Debug keystore** via `signingConfig = signingConfigs.getByName("debug")` on `release` buildType |
| Firebase SHA-256 (this machine debug cert) | Registered: `e1a97bdc…` (full hash in Firebase console, not repeated here) |

**Blocker for Play Store / true production identity:** dedicated release keystore + `key.properties` wiring (not created in this slice per stop rules).

---

## 7. Production API URL (embedded at build)

**`https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/v1`**

Verified via `strings` on release APK (prod host present). No `127.0.0.1`, `localhost`, or `ora-auth-service-staging` strings found in APK scan.

---

## 8. App Check release provider

**`AndroidPlayIntegrityProvider()`** when `kReleaseMode == true` (`firebase_app_check_bootstrap.dart`).  
Build uses `--release` + `ORA_APP_CHECK=true` → `AppConfig.appCheckEnabled == true`; fail-closed if disabled on production release.

No `PRODUCTION_APP_CHECK_DEBUG_SECRET` or debug UUID embedded in APK.

---

## 9. Play Integrity configuration (Firebase)

| Item | Value |
|------|--------|
| Provider | Play Integrity registered (`playIntegrityConfig`, token TTL 3600s) |
| Device recognition | `minDeviceRecognitionLevel: NO_INTEGRITY` (Firebase console API) |
| Package | `com.ora.ora` |

Play Console internal testing / app signing linkage **not verified** in this slice.

---

## 10. Static artifact audit

| Check | Result |
|-------|--------|
| `applicationId` | `com.ora.ora` |
| Release build | Yes (`flutter build apk/appbundle --release`) |
| Production API host in APK | **Present** |
| Staging / localhost | **Not found** (strings scan) |
| Debug App Check secret | **Not found** |
| Valid APK structure | **Yes** (after clean rebuild: `AndroidManifest.xml`, `resources.arsc` present) |

**Note:** An earlier build while disk was full produced an **invalid** APK (missing manifest); discarded after clean rebuild.

**Places key:** Build completed with empty `ORA_GOOGLE_PLACES_API_KEY` dart-define when ops env var unavailable — Places autocomplete may be limited on device until key is supplied at rebuild.

---

## 11. Device used

**Samsung `SM-A325F` — serial `RF8R40ZQ1JH` (Android 13)**

---

## 12. adb reverse status

**OFF** — `adb reverse --remove-all`; `adb reverse --list` empty before install/launch tests.

---

## 13. Firebase Auth result (release app)

| Result | Detail |
|--------|--------|
| App launch | **PASS** — release APK installs and shows auth welcome UI |
| Automated OTP | **NOT COMPLETED** — release build does **not** set `appVerificationDisabledForTesting` (debug-only in `main.dart`); UI automation did not reach post-auth home reliably |
| Manual evidence | Welcome / phone entry screen observed (`Welcome to ORA`, Send verification code) |

---

## 14. Real Play Integrity result

| Class | Result |
|-------|--------|
| **Play Integrity App Check token obtained (release)** | **NOT PROVEN** |
| **Production backend accepted Play Integrity token from release app** | **NOT PROVEN** |

No log evidence of successful Play Integrity token exchange tied to an authenticated release-app API call. Slice 4 **debug-token** path remains the only proven automated pricing path.

---

## 15. Production API connectivity (from release app)

**NOT PROVEN end-to-end** — auth + pricing flow not completed on device against production HTTPS API in this session.

(Release app is configured for direct HTTPS prod URL; no adb reverse.)

---

## 16. Production pricing from real app

**NOT PROVEN** — no `POST /v1/pricing/estimate` **HTTP 200** attributed to the release app on device.

---

## 17–19. Pricing snapshot / fare / distance (device)

**N/A** — pricing not reached on device.

---

## 20. Negative App Check proof (backend)

**PASS** (Slice 4 smoke script, unchanged backend):

| Case | Result |
|------|--------|
| No App Check | 401 `APP_CHECK_REQUIRED` |
| Invalid App Check | 401 `APP_CHECK_INVALID` |
| Debug exchange + Auth (automation only) | 200 pricing |

---

## 21. Staging regression

**PASS** — staging `GET /healthz/` → **200**; revision **`ora-auth-service-staging-00024-4wv`** not modified.

---

## 22. Flutter tests

**453 passed, 2 failed** (unchanged pre-existing):

- `home_shell_driver_gate_test.dart`
- `mvvm_layer_test.dart`

**No new failures** introduced by slice 5 mobile source changes (scripts/docs only).

---

## 23. Backend tests

**391/391 PASS** — `npm test -- --run`

---

## 24. Build result

| Target | Result |
|--------|--------|
| Backend `npm run build` | **PASS** |
| Flutter release APK | **PASS** (valid manifest after clean rebuild) |
| Flutter release AAB | **PASS** |

---

## 25. Artifact paths

- `mobile/build/app/outputs/flutter-apk/app-release.apk`
- `mobile/build/app/outputs/bundle/release/app-release.aab`
- `mobile/scripts/build_production_release.sh`
- `docs/operations/production-mobile-release.md`

---

## 26. Remaining blockers

1. **Dedicated Android release signing** — no production keystore / `key.properties`; Gradle uses debug cert for release artifacts.
2. **Real Play Integrity E2E** — release app did not complete auth + pricing with provable Play Integrity App Check on production backend (no debug token substitute).
3. **`ORA_GOOGLE_PLACES_API_KEY`** — required for full Places-enabled production build script gate; last build used empty define when key not in shell env.
4. **Play Console** — internal testing track / Play App Signing may be required for reliable Play Integrity on distributed builds (not configured here).
5. **Disk space** — initial release build corrupted APK when disk was full; resolved after cleanup (ops note for CI).

---

## 27. Recommended next slice (Slice 6)

1. Provision **release keystore** + Gradle `key.properties` (local/CI secrets only); register **release SHA-256** in Firebase.
2. Rebuild production APK/AAB with **`ORA_GOOGLE_PLACES_API_KEY`**.
3. Distribute via **Play internal testing** (or proven sideload path) and complete **manual or instrumented** auth + pricing on `RF8R40ZQ1JH`.
4. Capture proof: production Cloud Run log `pricing_estimate_ok` + requestId **without** debug App Check exchange; optional App Check metrics in Firebase console.
5. Custom domain `api.ora.app` → prod Cloud Run (optional, separate slice).

---

## Artifacts added (this slice)

| File | Purpose |
|------|---------|
| `mobile/scripts/build_production_release.sh` | Production release APK/AAB |
| `docs/operations/production-mobile-release.md` | Ops notes |
| `mobile/.e2e_artifacts/production_release_device_smoke.sh` | Device helper (ops) |
| `mobile/.e2e_artifacts/production_release_pricing_device_proof.py` | Device helper (ops) |

No backend business-logic changes. No App Check weakening.

---

**PRODUCTION MOBILE RELEASE SLICE = BLOCKED**

**Reason:** GREEN requires **real Play Integrity** proof from the **signed release artifact** through to production **pricing 200**. This slice delivered production-configured release **APK/AAB**, static prod URL verification, and device install/launch, but **did not** prove Play Integrity App Check + Auth + production pricing on the physical device. Release signing remains **debug keystore**, which is also a production-release blocker for store/attestation hardening.
