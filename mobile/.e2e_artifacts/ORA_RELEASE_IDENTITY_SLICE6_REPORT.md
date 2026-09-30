# Ora production hardening — slice 6 (Android release identity + Play Integrity enablement)

**Date/time:** 2026-09-30 (PKT)  
**Slices 1–4:** Not reopened. **Slice 5:** Findings incorporated; not reopened for E2E.

---

## Phase 0 — Inventory (before changes)

| Item | State (pre-slice) |
|------|-------------------|
| **Debug signing** | Default Android debug keystore (`~/.android/debug.keystore`) |
| **Release signing** | `release` buildType used `signingConfigs.debug` in `build.gradle.kts` |
| **`android/key.properties`** | **Missing** |
| **Keystore files in repo** | **None** (`**/*.jks`, `**/*.keystore` gitignored) |
| **Firebase Android app** | `1:498169438285:android:3b100b1c7a7248f1ddbc04`, package `com.ora.ora` |
| **Firebase SHA registrations** | SHA-1 `9ae7ebcb…` (debug-era cert); SHA-256 `e1a97bdc…` (**debug** machine cert) |
| **Release SHA-256 on Firebase** | **Not registered** (no release keystore) |
| **Play Integrity (Firebase App Check)** | Provider configured; `tokenTtl=3600s`; `minDeviceRecognitionLevel=NO_INTEGRITY` |
| **Play Console** | **Not configured in repository**; no Play Developer API credentials in project |
| **Production build script** | `mobile/scripts/build_production_release.sh` |

---

## Phase 1 — Release keystore

| Check | Result |
|-------|--------|
| Authorized production keystore in repo or `android/` | **NOT FOUND** |
| `android/key.properties` | **NOT FOUND** |
| Auto-generate keystore | **NOT PERFORMED** (forbidden by slice rules) |

**STOP condition met:** production release keystore must be **provisioned and authorized by the project owner** before release identity can be completed.

---

## Phase 2 — Gradle signing (prep only — blocked on keystore)

Implemented **fail-closed** wiring (no debug-signed release artifacts):

| Change | Purpose |
|--------|---------|
| `mobile/android/app/build.gradle.kts` | Load `android/key.properties`; `signingConfigs.release`; **release build throws** if `key.properties` absent |
| `mobile/android/key.properties.example` | Non-secret template for local/CI setup |
| `mobile/scripts/build_production_release.sh` | Exits early if `key.properties` missing |
| `docs/operations/production-mobile-release.md` | Updated signing instructions |

**Debug builds:** unchanged (`debug` buildType → debug signing).

**Release builds without keystore:** expected **Gradle failure** with message requiring `android/key.properties` (fail-closed; not verified end-to-end in CI this session due to long Gradle bootstrap lock).

---

## 1. Date/time

2026-09-30 (PKT)

---

## 2. Android package

**`com.ora.ora`**

---

## 3. Firebase Android app ID

**`1:498169438285:android:3b100b1c7a7248f1ddbc04`**

Project: **`ora-app-d8112`**

---

## 4. Release signing status

| Status | Detail |
|--------|--------|
| Production keystore | **Not provisioned** |
| `key.properties` | **Not present** |
| Release artifact signing | **Cannot produce release-signed APK/AAB** until keystore + `key.properties` exist |
| Debug fallback for release | **Removed** (fail-closed) |

---

## 5. Release certificate SHA-256

**N/A** — no release keystore. Only **debug** SHA-256 is registered on Firebase today (`e1a97bdc…` prefix; full public fingerprint in Firebase Console).

---

## 6. Firebase SHA-256 registration status

| Certificate | Registered |
|-------------|------------|
| Debug / dev SHA-256 (`e1a97bdc…`) | **Yes** (preserved) |
| **Release upload / app signing SHA-256** | **No** — blocked until release cert exists |

---

## 7. Play Integrity configuration

| Field | Value |
|-------|--------|
| Provider | Play Integrity (`playIntegrityConfig` present) |
| Token TTL | `3600s` |
| `minDeviceRecognitionLevel` | `NO_INTEGRITY` (**unchanged** this slice) |
| Sufficient for sideload proof | **Uncertain** — Play-distributed builds often behave differently from sideloaded APKs |
| Debug App Check | Separate Firebase debug tokens (Slice 4); unchanged |

---

## 8. Play Console status

**Not available from repository / automation in this environment.**

No evidence of:

- Play Console app entry wired in repo
- Internal testing track
- Play App Signing enrollment

---

## 9. Play App Signing status

**Unknown / not configured** (requires Play Console access).

---

## 10. Internal testing readiness

| Path | Readiness |
|------|-----------|
| **A. Sideload release APK** | **NOT READY** — no release keystore |
| **B. Play internal testing** | **NOT READY** — no release AAB + Console setup |
| **C. Play App Signing** | **NOT READY** — requires Console + upload key |

When keystore exists: build **AAB** → upload to **internal testing** is the recommended path for reliable Play Integrity (Slice 7).

---

## 11. APK build result (release-signed)

**NOT BUILT** — blocked on `key.properties` / keystore.

Previous Slice 5 APK was **debug-signed**; new Gradle rules prevent repeating that without authorization.

---

## 12. AAB build result (release-signed)

**NOT BUILT** — same blocker.

---

## 13. Artifact static audit (release-signed)

**N/A** — no new release-signed artifacts.

Slice 5 structural checks (prod URL, no debug App Check secret) remain valid for **prior** debug-signed APK only; that artifact is **not** acceptable production identity.

---

## 14. Production API configuration (build defines)

Unchanged intended defines:

- `ORA_ENV=production`
- `ORA_APP_CHECK=true`
- `ORA_API_BASE_URL=https://ora-auth-service-2zmxvrrs7a-uc.a.run.app/v1`

---

## 15. App Check configuration

Release compile-time: **Play Integrity provider** when `kReleaseMode` (Flutter bootstrap unchanged).

Enforcement on backend: **`REQUIRE_APP_CHECK=true`** (unchanged; Slices 1–4 not reopened).

---

## 16. Places configuration status

`build_production_release.sh` requires **`ORA_GOOGLE_PLACES_API_KEY`** in environment (not embedded in report). Key was **missing** in Slice 5 build session; still required for Slice 7 production build.

---

## 17. Secret-leak audit

| Item | Result |
|------|--------|
| Keystore / `key.properties` committed | **No** (gitignored; not present) |
| Passwords in repo | **None added** |
| `key.properties.example` | Placeholders only |
| App Check debug secret in source | **No** |
| Backend/mobile credential logging | **No changes** |

---

## 18. Backend tests

**391/391 PASS** — `npm test -- --run`

---

## 19. Flutter tests

**453 passed, 2 failed** (pre-existing):

- `home_shell_driver_gate_test.dart`
- `mvvm_layer_test.dart`

No new failures from slice 6 Gradle/doc changes.

---

## 20. Build results

| Target | Result |
|--------|--------|
| Backend `npm run build` | **PASS** |
| Release-signed Flutter APK/AAB | **NOT RUN** (keystore blocker) |

---

## 21. Remaining blockers

1. **Authorized production upload keystore** must be created or supplied by project owner (outside automation).
2. **`android/key.properties`** pointing at keystore (local/CI only).
3. **Register release SHA-256** on Firebase Android app (keep debug SHA).
4. **Play Console** app + **internal testing** (recommended for Play Integrity proof in Slice 7).
5. **`ORA_GOOGLE_PLACES_API_KEY`** in build environment for production release build.

---

## 22. Exact next slice (Slice 7)

**Production Play Integrity + pricing E2E** (after Slice 6 unblocked):

1. Owner provisions keystore + `key.properties`.
2. `./scripts/build_production_release.sh both` with Places key exported.
3. Extract **release** cert SHA-256 (`keytool -list -v` on upload cert); register in Firebase.
4. Upload AAB to Play **internal testing** (or document sideload path if Console unavailable).
5. Install from Play/internal track on `RF8R40ZQ1JH`, **adb reverse OFF**.
6. Firebase Auth (test phone) → **Play Integrity** App Check → `POST /v1/pricing/estimate` **200** on production Cloud Run.
7. **No** debug App Check exchange for GREEN.

---

## Files changed (slice 6)

| File | Change |
|------|--------|
| `mobile/android/app/build.gradle.kts` | Fail-closed release signing |
| `mobile/android/key.properties.example` | Template |
| `mobile/scripts/build_production_release.sh` | Require `key.properties` |
| `docs/operations/production-mobile-release.md` | Signing docs |

No backend, App Check middleware, N3, D1, Cloud Run, or mobile UI changes.

---

**RELEASE IDENTITY SLICE = BLOCKED**

**Reason:** No authorized production release keystore exists. GREEN requires configured **release signing identity**, **release SHA-256 on Firebase**, and **release-signed APK/AAB** passing static audit — all blocked until the owner provisions signing credentials.
