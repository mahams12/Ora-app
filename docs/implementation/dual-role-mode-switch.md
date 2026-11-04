# Dual-Role Mode Switch (Passenger ⇄ Driver)

Status: implemented, verified on local emulators + one physical device (Samsung
SM-A325F). NOT verified on staging/production.

## Model

One Firebase Auth account and one canonical `users/{uid}` profile per user.
Both roles hang off the same document:

- `role`: `passenger` | `driver` — the account's broadest entitlement.
  Onboarding+approval flips `passenger → driver`. Never flipped back.
- `driverStatus`: `none` | `pending` | `approved` | `rejected` | `suspended`.
- `activeMode`: `passenger` | `driver` — which UI surface the session opens.
  Persisted server-side; restored on app restart and re-login.

No second `users` doc, no second Auth account, no data migration. Ride
history, courier history, ratings, and earnings are UID-keyed and untouched by
mode switches.

## API

### `POST /v1/auth/mode` — `users.switchMode` (`src/services/users.ts`, route in `src/routes/auth.ts`)

Body: `{ "mode": "passenger" | "driver" }`.

- `driver` target requires `driverStatus === 'approved'`; otherwise 403
  (`DRIVER_NOT_APPROVED` / `DRIVER_PENDING` / `DRIVER_REJECTED` /
  `DRIVER_SUSPENDED`).
- Both transitions are idempotent — switching to the current mode is a no-op
  returning the same profile.
- **Active-job guard**: any non-terminal ride/courier where the caller is
  passenger OR assigned driver blocks the switch with `409 ACTIVE_JOB`
  (queried inside the Firestore transaction; `(assignedDriverId, state)`
  composite index already exists).
- `driver → passenger` runs through the shared driver-availability service in
  the same request: durable `offline` write + GEO presence removal, so a
  passenger-mode user can never remain discoverable as a driver.

### `POST /v1/drivers/onboarding` — `src/drivers/driver_onboarding_service.ts`

Body: `{ vehicleType, vehicleModel?, plateNumber?, homeCity? }`.

- Validates vehicle data, creates/updates `drivers/{uid}`, sets canonical
  `driverStatus: 'pending'`, leaves `activeMode: 'passenger'`.
- Idempotent: repeat submits update the same `drivers` doc while pending; no
  duplicate records. All transaction reads precede writes (real Firestore
  constraint — the memory test double does not enforce this, only the
  emulator/production path does).

### `GET /v1/rides?as=passenger|driver` — `src/rides/list_query.ts`

Ride listing takes an explicit mode. Previously a driver-role user's
passenger bookings were invisible because the role was derived from the
profile; now `as` selects the viewer perspective.

## Mobile

- `UserProfile.activeMode` persisted via the profile model.
- `AuthRepository.switchMode(mode)` / `submitDriverOnboarding(...)`; use cases
  `SwitchModeUseCase`, `SubmitDriverOnboardingUseCase`.
- Passenger home "Earn on ORA" (`home_shell_view.dart`): refreshes the
  canonical profile, then routes — pending → "application under review"
  sheet; suspended/rejected → block sheet; none →
  `driver_onboarding_sheet.dart` (scrollable, vehicle type + optional model /
  plate / city); approved → `POST /auth/mode` → driver shell.
- Driver shell drawer → "Switch to passenger mode" calls the same endpoint;
  presence publisher stops because the availability service put the driver
  durably offline server-side.
- Route guards: `activeMode === 'driver'` boots into the driver shell on
  restart/re-login; approved drivers in passenger mode are no longer rejected
  by the legacy passenger gate.
- `ACTIVE_JOB` (409 `ConflictFailure.code`) surfaces a readable "finish your
  active trip first" message.

## Local device setup (physical phones, zero cloud cost)

- `scripts/dev_adb_reverse.sh` — `adb reverse` map for API (8081→8080), Auth
  emulator (9099), RTDB (9000), Firestore (8181), OTP lookup (8899).
- `scripts/ora_auth_emulator_proxy.js` — Android `firebase-auth` calls
  Identity Toolkit paths the emulator doesn't serve
  (`signInWithPhoneNumber` → rewritten to `verifyPhoneNumber`, plus
  `sendVerificationCode` passthrough). Device → emulator only.
- **Loopback caveat**: on at least one Samsung (Android 11–12) the SDK's
  phone-auth traffic never reached `127.0.0.1` despite the reverse working in
  Chrome — `network-request-failed` (17020) with zero packets arriving.
  Workaround: bind the proxy/emulator ports on the Mac's LAN IP and build the
  debug APK with `ORA_FIREBASE_EMULATOR_HOST=<lan-ip>`; same-subnet Wi-Fi
  reaches it directly.
- `backend/auth-service/scripts/seed_device_test_accounts.ts` — seeds
  phone-number-keyed test users/drivers on the emulators (emulator only,
  refuses to run without `FIRESTORE_EMULATOR_HOST`).

## Verification

| Layer | Result |
|---|---|
| Backend unit/serial suite | 638/638 (mode-switch suite 25/25) |
| Flutter analyze | clean |
| Flutter test | 779/779 |
| Local emulator E2E (`run_local_emulator_e2e.ts`) | 52/52 incl. onboard → pending → blocked → approve → switch → online → back → durable offline |
| Physical Samsung SM-A325F (`RF8R40ZQ1JH`) | full loop below |

Physical run (dev APK, LAN emulator path, `+923004445555` /
uid `sYLTRjEtZZTl95gtElzlwoZM5OoM`):

1. Phone OTP sign-in via auth proxy — PASS.
2. Single `users/{uid}`; `role:passenger, driverStatus:none, activeMode:passenger` — PASS.
3. "Earn on ORA" → onboarding sheet → submit → `driverStatus:pending`,
   `drivers/{uid}` created offline — PASS.
4. Pending state blocks driver mode ("application submitted") — PASS.
5. Server-side approval → switch → `POST /auth/mode` → driver shell — PASS.
6. Go online → presence stream `seq:1 accepted`, location updates logged — PASS.
7. Switch to passenger → `GEO_OFFLINE_REMOVED`, durable `offline`,
   `activeMode:passenger` — PASS.
8. Force-stop → restart → passenger home restored — PASS.
9. Switch to driver → force-stop → restart → driver shell restored — PASS.
10. Drawer → Log out → session cleared → login screen — PASS.
11. Re-login same number → same UID (`isNewUser:false`) → driver shell
    restored — PASS.

Bug found and fixed during the physical run: `showOraBottomSheet` capped the
sheet at full-screen height while also applying the keyboard inset →
"BOTTOM OVERFLOWED BY 82 PIXELS" on the onboarding form. Fixed by subtracting
`viewInsets.bottom` before applying the height factor
(`ora_bottom_sheet.dart`).

## Remaining gaps / not verified

- **Staging/production untouched and unverified.** No deploy, no shared-APK
  rebuild, no production data changes.
- Concurrent rapid-fire switching across two physical devices under one
  account — the `ACTIVE_JOB` tx guard + idempotency cover the server side;
  two-device UI racing is untested.
- `driverStatus` transitions (approve/reject/suspend) remain admin/seed
  operations — there is no ops endpoint or console flow for them.
- Switching while driver-mode presence is mid-`goOnline` relies on the
  existing availability-service semantics; no dedicated chaos test.
