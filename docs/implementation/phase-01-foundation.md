# Phase 1 — Flutter Foundation + MVVM

**Status:** COMPLETE (implementation) — local Android/iOS builds may still need free disk space  
**Dependencies:** Phase 0, 0.5, 0.6, 0.7 (locked)  
**Architecture reference:** `docs/architecture/flutter-mvvm-architecture.md`

## What Was Implemented

Phase 1 delivers the production Flutter foundation for Ora: MVVM folder structure, Riverpod dependency injection, Freezed immutable state, go_router navigation, typed error handling, structured logging, networking abstraction, environment/config separation, design-system primitives, responsive utilities, CI workflow, and a minimal end-to-end MVVM bootstrap flow (Splash → Home shell).

No ride dispatch, assignment, payment, live-trip, Firebase auth, or maps SDK integration was implemented.

## Repository Before Implementation

- Workspace contained documentation only under `docs/`.
- No Flutter project, no git repository, no Firebase config.

## Commands Used

```bash
flutter create --org com.ora --project-name ora --platforms android,ios mobile/
cd mobile && flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --no-codesign
```

## Packages Added

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | DI, ViewModel lifecycle |
| `riverpod_annotation` | Future codegen support |
| `freezed_annotation` / `freezed` | Immutable states |
| `json_annotation` / `json_serializable` | Future API models |
| `go_router` | Navigation |
| `dio` | HTTP foundation |
| `uuid` | Request/correlation IDs |
| `mocktail` | Test doubles |
| `build_runner` | Codegen |
| `flutter_lints` | Strict analyzer |

Deferred: Firebase, Maps/Location SDKs, Retrofit, Hive, flutter_secure_storage.

## Architecture Decisions

1. MVVM + Clean Architecture — View → ViewModel → UseCase → Repository → DataSource.
2. Riverpod `NotifierProvider` for ViewModels; graph in `app/di/providers.dart`.
3. Freezed sealed states — `AppFailure`, `SplashViewState`, `ViewState<T>`.
4. go_router with placeholder auth guard (no enforcement yet).
5. Dio `ApiClient` with request/correlation IDs, idempotency headers, token injection, retry only for safe/idempotent ops.
6. Environment via `AppEnvironment` + `--dart-define=ORA_ENV=...` + `.env.example`.
7. Design-system foundation (theme tokens + core widgets).
8. Responsive utilities; in-memory storage placeholders until Phase 2+.

## Key Paths

- App: `mobile/lib/main.dart`, `mobile/lib/app/`
- Core: `mobile/lib/core/`
- Auth bootstrap MVVM: `mobile/lib/features/auth/`
- Passenger shell: `mobile/lib/features/passenger/`
- Tests: `mobile/test/`
- CI: `.github/workflows/ci.yml`

## Tests

| File | Coverage |
|------|----------|
| `failure_mapper_test.dart` | Dio/HTTP → `AppFailure` |
| `retry_policy_test.dart` | Idempotent retry rules |
| `providers_test.dart` | Provider wiring |
| `router_test.dart` | go_router paths |
| `splash_view_model_test.dart` | ViewModel transitions |
| `mvvm_layer_test.dart` | Views must not import Dio/Firebase/data sources |

**Result:** 14/14 passed.

## Verification Results

| Check | Result |
|-------|--------|
| `flutter analyze` | No issues found |
| `flutter test` | 14/14 passed |
| `flutter build apk --debug` | Previously blocked by disk space; re-verify when ≥5 GB free |
| `flutter build ios --no-codesign` | Not confirmed locally |
| MVVM / Riverpod / Freezed / go_router | Present |
| No ride/payment/dispatch logic | Confirmed |

## Known Limitations

1. Fonts: Material defaults (Sora/Inter deferred).
2. Storage: in-memory placeholders.
3. Firebase / Maps not initialized.
4. Auth guards are no-ops.
5. Host disk was critically low during final build attempts.

## Next Phase

**Phase 2 — Authentication & Onboarding** (per `docs/ORA_MASTER_PLAN.md`).

Do not begin Phase 2 until Android/iOS build verification succeeds on a machine with sufficient free disk.
