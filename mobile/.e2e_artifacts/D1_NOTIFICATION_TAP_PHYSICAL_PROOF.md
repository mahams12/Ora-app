# D1 notification tap — physical proof (FINAL)

**Device:** `RF8R40ZQ1JH` (Samsung)  
**Driver:** `+923012345677` / OTP `000000`  
**Fresh ride (GREEN run):** `212d0068-9ad2-4658-bc68-da13b0784515`  
**Run:** 2026-09-30T06:58:35Z → 07:00:02Z (UTC)

## Final gate table

| Gate | Result |
|------|--------|
| ADB | **PASS** |
| Driver auth | **PASS** |
| FCM token | **PASS** |
| Fresh ride | **PASS** |
| Ride unexpired | **PASS** |
| N4 dispatch | **PASS** |
| FCM delivery | **PASS** |
| Notification exists | **PASS** |
| Physical notification tap | **PASS** |
| Open Rides navigation | **PASS** |
| Target ride API visible | **PASS** |
| Target ride UI visible | **PASS** |
| Duplicate/safety | **PASS** |

**D1 FINAL PHYSICAL VERDICT = GREEN**

## Ride snapshot (API create, no Firestore mutation)

| Field | Value |
|-------|--------|
| rideId | `212d0068-9ad2-4658-bc68-da13b0784515` |
| state | `SEARCHING` |
| createdAt | `2026-09-30T06:59:12.337Z` |
| expiresAt | `2026-09-30T07:04:12.337Z` |
| requestVersion | `1` |
| passengerOfferMinor | `114000` |
| pricingSnapshotId | `ps_1ec8136a-61c8-4371-87f7-8f36bb96121f` |

Verified unexpired before dispatch and at `GET /v1/rides/open` after tap (`targetPresent: true`, `rideCount: 2`).

## Dispatch / FCM

- `dispatch-tick`: `wave_completed`, `invitedCount: 1`, driver `SRjL7BJgCKTduhtpjtYMRZMq5fD2`
- `dispatch-fcm-sweep`: `delivered: 2`, `failed: 0`
- Tray: `com.ora.ora`, title **New ride request** (dumpsys before tap)

## Physical tap

- Notification shade expanded; **tap on real `expandableNotificationRow`** (not `ora://` deep link only)
- Foreground: `com.ora.ora`; UI **Open rides**
- UiAutomator: `Ride id 212d0068-9ad2-4658-bc68-da13b0784515` + **Respond**
- After tap: dispatch notification count **1 → 0**; **0** offer sheets

## Defect fix (minimal, a11y only)

First GREEN attempt **BLOCKED** on UI rideId: open-ride cards did not expose `rideId` to the accessibility tree. Added `Semantics(label: 'Ride id ${ride.rideId}')` on the open-ride card (no visual change). Rebuilt debug staging APK and re-ran end-to-end.

## Artifacts

- `d1_fresh_physical_final_report.json`
- `d1_notification_tap_physical_verify_report.json`
- `d1_tap_before_dumpsys_snippet.txt` / `d1_tap_after_dumpsys_snippet.txt`
- `d1_tap_before_shade.xml` / `d1_tap_after_tap_app.xml` / `d1_tap_before_dup_tap.xml`
- Runners: `d1_fresh_physical_final_verify.py`, `staging_d1_dispatch_prep.ts`, `d1_notification_tap_physical_verify.py`

## Prior runs (not final)

- Expired ride `762867a3-…`: tap/navigation PASS, visibility **BLOCKED** (expired).
- Fresh ride `9381083c-…`: all gates PASS except UI rideId **BLOCKED** (pre-a11y fix).
