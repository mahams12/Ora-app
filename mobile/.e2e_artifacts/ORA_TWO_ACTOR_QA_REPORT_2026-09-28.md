# ORA TWO-ACTOR QA REPORT

**Test start (UTC):** 2026-09-28T06:52:39+00:00 (log markers)  
**Report generated:** 2026-09-28 ~12:26 PKT  
**Correlation ride (partial run):** `de174953-b971-45b4-9f2e-eb10d1a89034` (created earlier same day; **expired** before this audit completed)

---

## Environment

| Item | Evidence |
|------|----------|
| **Samsung (DRIVER)** | `RF8R40ZQ1JH` · SM-A325F · Android 13 · USB |
| **Emulator (PASSENGER)** | `emulator-5554` · Pixel_9_Pro AVD · Android 36 · booted for this audit |
| **Backend** | LaunchAgent **UP** · `http://127.0.0.1:8080/healthz` OK · PID 86151 · log: `backend/auth-service/.local/dev-backend.log` |
| **ADB reverse** | Phone API `8081` → Mac `8080` on Samsung + emulator when connected |
| **APK** | `mobile/build/app/outputs/flutter-apk/app-debug.apk` (2026-09-23 17:01) · `ORA_API_BASE_URL=http://127.0.0.1:8081/v1` (logcat from prior gates) |
| **Emulator API** | Same APK + `adb reverse tcp:8081 tcp:8080` (not `10.0.2.2` unless rebuilt) |
| **Accounts (intended)** | Passenger `+923012345678` / OTP `123456` · Driver `+923012345677` / OTP `000000` (Firebase test numbers) |

**Monitoring:** Logcat snapshot files under `mobile/.e2e_artifacts/`; backend tail `qa_e2e_backend_tail.log`. Long-running logcat streams were **unreliable** (USB drop / zsh glob / exit 255).

---

## CORE E2E

| # | Gate | Status | Evidence |
|---|------|--------|----------|
| 1 | Auth | **YELLOW** | Samsung: prior session / driver shell reachable in earlier steps. Emulator: compose reached without full auth re-proof this run. |
| 2 | Passenger Home | **GREEN** | Emulator reached compose (“Where to?” / pickup flow). |
| 3 | GPS/Places | **YELLOW** | Emulator: `emu geo fix` OK; mock provider via shell **blocked** (MOCK_LOCATION). Places text entry + Liberty suggestion used. Samsung: mock GPS works (API 33). |
| 4 | Pricing | **GREEN** (ride `de174953…`) | Backend `pricing_estimate_ok` + snapshot on ride doc (see Pricing Integrity). Emulator automation did **not** complete a **new** pricing cycle this run. |
| 5 | Ride creation | **RED** (this audit) | **No new ride** created emulator→backend in this run (compose stuck before review). Earlier ride `de174953…` created on Samsung-as-passenger automation (~11:57 PKT). |
| 6 | Driver discovery | **RED** | After expiry, `listOpenRides` → **0** rides (~1.9s). Samsung UI: “No open ride requests” when refreshed earlier. **No rideId match** in this audit window. |
| 7 | Driver offer | **BLOCKED** | No live open ride on driver after expiry. |
| 8 | Passenger offer inbox | **BLOCKED** | No offer submitted. |
| 9 | Assignment | **BLOCKED** | — |
| 10–14 | Progression / CLOSED | **BLOCKED** | — |
| 15 | Ratings | **N/A** | Driver home shows **Ratings** as unavailable placeholder; no end-to-end rating UI exercised. |

---

## PRICING INTEGRITY (ride `de174953-b971-45b4-9f2e-eb10d1a89034`)

| Field | Value | Source |
|-------|-------|--------|
| Pickup | 31.4127633, 74.1725305 · “Current location” | Firestore ride doc |
| Destination | Liberty Market Gulberg III, Lahore | Firestore ride doc |
| Distance | **23.973 km** | Stored on ride (Google Routes via pricing pipeline) |
| Duration | **38.616… min** (API rounds to **39** in open-ride DTO) | Stored on ride |
| pricingSnapshotId | `ps_00e9fa9e-a592-4260-9fc2-89f81eb23db4` | Firestore |
| recommendedFareMinor | **114000** | Firestore |
| passengerOfferMinor | **114000** | Firestore (= requested fare) |
| Display (UI) | **Rs 1140** via `formatOfferAmountMinor(minor/100)` | Code + prior device observation |

**Verdict:** Fare is **server-derived**, not hardcoded in Flutter. **114000 minor = Rs 1,140** — users do **not** see `114000` on open-ride **cards** (only on offer sheet — see UX).

**Inconsistencies / risks**

- **P2 DEFECT (fixed in repo, APK old):** Open-ride JSON returned fractional `estimatedDurationMin`; older client cast → “unexpected error” when list non-empty. Backend now rounds; mobile parser hardened — **rebuild APK** to pick up mobile half.
- **P3 RECOMMENDATION:** Distance label suffix **`(server)`** and **`min (server)`** in `open_ride_display.dart` exposes engineering tone (see Driver UX).

---

## DRIVER UX (findings)

### DEFECTS (P2)

1. **Offer sheet shows minor units** — `driver_open_rides_view.dart`: label **“Amount (minor units)”**, hint **“Server minor units”**, default text **`114000`**, helper mentions **POST /v1/rides/:rideId/offers** and **requestVersion**. Normal drivers cannot negotiate in Rs without mental math.
2. **Engineering copy on open rides header** — “Available ride requests from Ora's servers… Not a GPS or map-radius feed.” — accurate but not driver-facing (RECOMMENDATION if product accepts shorter copy).

### RECOMMENDATIONS (P3)

- Replace header with **“Available rides”** + optional one-line refresh hint.
- Offer sheet: **Accept Rs X** / **Counter Rs ___** using major units; hide requestVersion/API paths.
- Trip line: shorten **“Current location → Liberty Market…”** to destination-first once pickup is implied.
- Remove **`(server)`** from km/min lines; keep numbers only.
- **“Respond”** → **“Accept or counter”** (or split primary actions).

---

## PASSENGER UX

| Area | Status | Notes |
|------|--------|-------|
| Compose / confirm | **YELLOW** | Two-step **Confirm pickup** / **Confirm destination** easy to miss in automation; likely human confusion too. |
| Review / pricing | **GREEN** (prior) | “Retry pricing” + **Request Easy** when pricing OK. |
| Offers waiting | **GREEN** (prior) | “Waiting for offers” copy reasonable. |
| Engineering leakage | **Not fully audited** on emulator this run | Offer inbox not reached. |

---

## PERFORMANCE (measured this session)

| Metric | Value |
|--------|-------|
| Open discovery (driver, empty) | **~1.9–4.2 s** (backend logs) |
| Open discovery (1 ride, earlier) | **~1.1 s** (backend log) |
| Pricing retry window (automation) | **~18 s** (script wait; includes network) |
| Emulator cold boot | **~17.6 s** (emulator log) |
| Full passenger create (this audit) | **Not measured** (did not complete) |
| Assignment / progression | **Not measured** |

---

## ERRORS / CRASHES

- **Connection errors** when backend down or **adb reverse** missing (prior session; mitigated by LaunchAgent + `dev_adb_reverse.sh`).
- **Parse error** when open rides list non-empty on **old APK** (fractional duration) — see pricing integrity.
- **Emulator logcat stream:** exit 255 on USB/agent shell teardown.
- **`dev_adb_reverse.sh`:** failed on macOS default bash (`mapfile`) — **fixed** in repo.

---

## FIRESTORE / BACKEND INTEGRITY

- Ride `de174953…`: **SEARCHING**, unassigned, **expired** `2026-09-28T07:01:47.750Z` — correctly excluded from open discovery after expiry.
- Open discovery uses **unordered scan + in-memory sort** (no composite index required for M0 path).
- **`RIDE_LIST`** on driver assigned/history path: **INTERNAL** (missing index) observed earlier — separate from open discovery.

---

## BACKEND CORRELATION (intended chain)

Only partially satisfied for **`de174953…`**:

| Step | rideId | Status |
|------|--------|--------|
| Passenger created | `de174953…` | **GREEN** (earlier automation + Firestore) |
| Driver discovered same id | `de174953…` | **GREEN** (backend log `resultCount:1` earlier) · **not re-shown** after expiry |
| Driver offer | — | **NOT DONE** |
| Passenger accept | — | **NOT DONE** |
| Progression → CLOSED | — | **NOT DONE** |

---

## FIX PRIORITY

**P0:** None observed in this audit window.

**P1:**

- Complete **one correlated ride** emulator (passenger) + Samsung (driver) with fresh APK after duration parse fix.
- Deploy or verify Firestore **index** for driver **assigned/history** `RIDE_LIST` if that tab is in scope.

**P2:**

- Driver offer UX: **major-unit fare entry**; remove API/requestVersion/minor-units copy from primary UI.
- Emulator E2E: document **Places + confirm destination** dependency; consider UI affordance when `proposedDestination` pending.

**P3:**

- Shorten driver open-rides header and km/min labels.
- Rebuild debug APK with latest mobile parse fix + UX changes when implemented.
- Use **`./scripts/dev_adb_reverse.sh`** after every USB reconnect.

---

## FINAL VERDICT

**RED** — Production readiness **not** demonstrated for full two-actor marketplace closure.

**BLOCKED** items: no live ride at audit end; no offer/assign/progression; emulator passenger automation did not finish a new create in this run.

**Evidence that works:** persistent backend, pricing snapshot → **Rs 1140** mapping, driver open discovery **did** return the live ride before expiry, prior passenger **Waiting for offers** state.

**Not claimed:** end-to-end assignment, progression, ratings, or production-ready UX on driver offer sheet.
