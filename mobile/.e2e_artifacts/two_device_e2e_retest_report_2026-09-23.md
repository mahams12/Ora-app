# Two-Device Physical E2E Retest Report

**Correlation ID:** `ORA-E2E-20260923-1608`  
**Date:** 2026-09-23 ~16:06–16:12 PKT  
**Mode:** Audit only — **no product code changes**

---

## Final verdict

**FULL TWO-DEVICE E2E: RED — NOT GREEN**

The run **cannot** complete the required passenger→driver→closure journey on hardware in this session because:

1. **Device B (Android 16)** rejects **ADB input injection** (`INJECT_EVENTS` / `MOCK_LOCATION` / `pm grant`) — driver login and all driver-side steps are **UNTESTED** via automation; device remains on **phone entry** unless operated manually on-device.
2. **Passenger compose automation** did not reliably reach **Review + live pricing** in scripted runs, though **Places succeeded** after APK rebuild with Places dart-define.
3. **Ride create → offer → assign → progression → ratings → history** were **never started** on either device.

---

## 1–2. Devices

| | **Device A (Passenger target)** | **Device B (Driver target)** |
|--|--------------------------------|------------------------------|
| Serial | `RF8R40ZQ1JH` | `H6YLNBV8MF45Z94L` |
| Model | Samsung **SM-A325F** | **23090RA98G** |
| Android | **13** (API 33) | **16** (API 36) |
| Physical | Yes | Yes |
| `adb devices` | `device` | `device` |

---

## 3. Test accounts (intended)

| Role | Test phone (Firebase testing) | UID evidence this run |
|------|------------------------------|------------------------|
| Passenger | `+923001234567` | **`AQLQjCfBw3W17kfgzziM6po1Nh33`** (backend `pricing_estimate_begin` / `register_ok` history) |
| Driver | `+923012345678` | **Not verified** — Device B never completed OTP login in automation |

**Passenger UID ≠ Driver UID:** **Not proven** (driver UID not observed).

If your configured numbers differ from the two above, re-run login manually on each device before the next gate.

---

## 4–5. Backend / reverse / APK

| Check | Result |
|-------|--------|
| Backend PID | **14764** (single listener on **8080**) |
| healthz | `{"ok":true,"service":"ora-auth-service"}` |
| Reverse A | `tcp:8081 tcp:8080` |
| Reverse B | `tcp:8081 tcp:8080` |
| Firebase project | **ora-app-d8112** |
| APK build | **2026-09-23 16:06:57** — debug with `ORA_API_BASE_URL=http://127.0.0.1:8081/v1`, `ORA_ALLOW_HTTP_API=true`, **Google Places dart-define present** (key not logged) |
| Installed on both | Yes (`adb install -r` success both) |
| API base logcat | Both devices: `ORA API BASE URL = http://127.0.0.1:8081/v1` |

---

## 6. Auth (Phase 1)

| | Device A | Device B |
|--|----------|----------|
| Cold activity start | WaitTime **4107 ms**, TotalTime **4100 ms** | **NOT MEASURED** (blocked before home) |
| Cold → Home | **9568 ms**, no Try Again | **UNTESTED** — UI at **Welcome / Phone number** |
| Try Again required | No | N/A |
| Crash | No | No |

**AUTH-001 on Device A:** **GREEN** (consistent with prior gate).

---

## 7–8. GPS / Places / Pricing (Device A)

| Stage | Result | Evidence |
|-------|--------|----------|
| GPS pickup | **YELLOW** | Compose shows **31.41272, 74.17249** (mock/test provider on A32; not 31.5204 Lahore mock) |
| Places | **GREEN (this session)** | Destination resolved: **Liberty Market Gulberg III, Lahore** — no “Location lookup isn't available” in latest `p5c_clean_ui.xml` |
| Review (automation) | **RED/YELLOW** | `p5c_clean_run.py` exited `FAIL: review not reached` (waits for “Select a ride” string) |
| Category UI | **YELLOW** | After manual Continue: **Trio** visible, **“Fare on request”** |
| Pricing API (this session) | **UNTESTED / no new ok** | No new `pricing_estimate_ok` after 16:08 marker; last log entries remain earlier **trio** success for passenger UID |
| Pricing UI Rs 270 | **NOT observed** this session | Prior **5C GREEN** report (15:20) **not re-validated** end-to-end today |

---

## 9–24. Ride marketplace stages (Device A + B)

| # | Stage | Status |
|---|--------|--------|
| 9 | Create ride | **UNTESTED** |
| 10 | Driver discovery | **UNTESTED** |
| 11 | Driver offer | **UNTESTED** |
| 12 | Passenger offer inbox | **UNTESTED** |
| 13 | Assignment | **UNTESTED** |
| 14–20 | Progression → closed | **UNTESTED** |
| 21–22 | Ratings | **UNTESTED** |
| 23–24 | History | **UNTESTED** |

**Harness reference (not physical):** backend **341/341** Vitest PASS @ 15:54 PKT (ride lifecycle in-process).

---

## 25. FCM

**UNTESTED physical.** No offer flow reached.

---

## 26. Network recovery (Phase 19)

**UNTESTED** — happy path not completed.

---

## 27. Performance table (measured only)

| Metric | Device | Time (ms) | Class |
|--------|--------|-----------|-------|
| Activity cold start | A | 4100–4107 | SLOW |
| Cold → Passenger Home | A | 9568 | GOOD |
| Activity cold start | B | — | NOT MEASURED |
| Driver Home | B | — | NOT MEASURED |
| Places → destination shown | A | ~160s script wall (includes auth/compose) | NOT isolated |
| Pricing UI ready | A | — | NOT MEASURED |
| All other journey metrics | — | — | NOT MEASURED |

---

## 28. Responsiveness / jank

**NOT MEASURED** (no profiling). Device A compose UI responded to automation taps; Device B blocked at shell input layer.

---

## 29. Duplicate requests / races

**NOT MEASURED** — no ride created.

---

## 30. Firestore integrity

**NOT MEASURED** — no ride ID captured.

---

## 31. Bugs / blockers

| ID | Sev | Status | Summary |
|----|-----|--------|---------|
| **E2E-005** | **P0** | **Confirmed** | Device B **Android 16** denies ADB `input tap`, `keyevent`, `pm grant`, mock location — **blocks automated two-device E2E** |
| **E2E-006** | **P1** | **Confirmed** | Passenger automation **fragile** — script fails “Select a ride” while UI is on category/pricing step; manual Continue reaches Trio but **no fresh pricing_estimate** observed |
| **E2E-002** | P0 | **Mitigated** | Two physical devices **now connected** — but B not exercisable via ADB |
| TEST-001 | P3 | Known | Flutter **445 PASS / 1 FAIL** (`mvvm_layer_test`) |

**Ops note (Device B):** On Xiaomi / Android 16, enable **USB debugging (Security settings)** (or equivalent) to allow shell input injection, **or** run driver steps **manually on-device** while correlating backend logs.

**Ops note (Driver role):** If driver test user is still `role=passenger` in Firestore, approve via Console or ops script `seed_e2e_driver_profile.ts` **after** driver completes `POST /register` once.

---

## 32. GREEN / YELLOW / RED matrix

| Area | Physical | Notes |
|------|----------|-------|
| Two devices connected | **GREEN** | ADB sees both |
| APK local API + Places define | **GREEN** | Rebuilt 16:06, installed both |
| Auth Device A | **GREEN** | |
| Auth Device B | **RED** | Not logged in (automation blocked) |
| Places Device A | **GREEN** | Gulberg destination resolved |
| Pricing Device A (this run) | **YELLOW** | No new backend pricing ok; UI “Fare on request” |
| Full two-device E2E | **RED** | |
| Backend harness | **GREEN** | 341/341 |

---

## 33. Recommendation

1. **Device B:** Enable ADB input injection **or** perform driver path **manually** with a written checklist and shared `rideId` in backend log.  
2. **Device A:** Re-run **5C-equivalent** compose to **Review + Rs fare** (fix automation selectors or manual confirm pricing_estimate_ok **after** 16:08 marker).  
3. **Driver Firestore:** Confirm driver test UID has `role=driver`, `driverStatus=approved`, `profileComplete=true`.  
4. Only after **both** sides reach Home and **one ride** completes on hardware, claim **FULL E2E GREEN**.

**Do not** claim full E2E GREEN from this retest.
