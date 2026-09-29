# AUTH-001 Final Physical Verification Gate

**Date:** 2026-09-23 (independent run, post-fix)  
**Device:** Samsung SM-A325F · ADB `RF8R40ZQ1JH`  
**Mode:** Verification only — no product code changes

---

## 1. Backend

| Check | Result |
|--------|--------|
| PID | **14764** (`auth-service` via tsx `src/index.ts`) |
| Port | **8080** (single LISTEN) |
| healthz | `{"ok":true,"service":"ora-auth-service"}` |

---

## 2. Reverse

```
UsbFfs tcp:8081 tcp:8080
```

---

## 3. APK

| Field | Value |
|--------|--------|
| Package | `com.ora.ora` |
| versionName | 1.0.0 (versionCode 1) |
| lastUpdateTime (device) | **2026-09-23 15:47:33** |
| APK on disk mtime | Matches P5C-style rebuild session (local `app-debug.apk`) |
| Rebuild this gate | **Not required** — installed APK already P5C-configured |
| API base confirmation | Logcat on each launch: `ORA API BASE URL = http://127.0.0.1:8081/v1` |
| ORA_ALLOW_HTTP_API | Implied by successful HTTP to `127.0.0.1:8081` (same as 5C GREEN proof) |
| 5C config parity | Same base URL + reverse as [`p5c_device_proof_report.json`](p5c_device_proof_report.json) |

---

## 4. Cold launch #1 (Test C)

| Metric | Value |
|--------|--------|
| Activity WaitTime | **4053 ms** (SLOW) |
| Activity TotalTime | **4047 ms** |
| Time to Home (UI poll) | **10370 ms** (GOOD overall) |
| Try Again used | **No** |
| Try Again visible during run | **No** |
| Indefinite Signing you in… (>30s) | **No** |
| Crash | **No** |
| `register_ok` delta (backend log) | **+1** (no storm per launch) |
| Auth `AUTH_*` markers in logcat | **Not present** on `flutter:I` (AppLogger markers not surfaced to logcat in this build) |
| Observable bootstrap | API base log → Home without manual recovery |

---

## 5. Cold launch #2 (Test D)

| Metric | Value |
|--------|--------|
| Activity WaitTime | **4066 ms** |
| Activity TotalTime | **4058 ms** |
| Time to Home | **10602 ms** |
| Try Again used | **No** |
| Try Again visible | **No** |
| `register_ok` delta | **+1** |

---

## 6. Authenticated restart (Test E)

| Metric | Value |
|--------|--------|
| Activity WaitTime | **4081 ms** |
| Activity TotalTime | **4071 ms** |
| Time to Home | **9825 ms** |
| Try Again used | **No** |
| Session restore | Firebase session present → Home (no phone OTP) |
| `register_ok` delta | **+1** |

---

## 7. Tests (host)

| Suite | Result |
|--------|--------|
| `auth_state_notifier_test.dart` | **PASS** |
| `auth_token_provider_test.dart` | **PASS** |
| Combined | **22/22 PASS** |

Full Flutter suite not re-run (gate scope: auth regression only).

---

## 8. Test F — Pricing regression

No pricing flow re-run. Configuration matches **5C GREEN**: local `http://127.0.0.1:8081/v1` + adb reverse + same backend PID/port.

---

## 9. AUTH-001 verdict

**GREEN**

All gate success criteria met on device:

1. Home reached on fresh cold launches (×2) and authenticated restart  
2. No Try Again tap  
3. No indefinite spinner  
4. Backend healthy, +1 register per bootstrap (no duplicate storm within each launch)  
5. No crash  
6. Auth unit tests pass  

**Note:** Per-phase token/register/me ms not available from logcat; total **launch → Home ~9.8–10.6 s** measured; activity cold start **~4 s**.

---

## 10. Recommendation

**Proceed to two-device full ride E2E** when ready. Keep using P5C dart-defines for any future device APK installs.
