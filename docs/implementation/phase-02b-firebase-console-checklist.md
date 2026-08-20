# Phase 2B — Firebase Console checklist (manual)

**Do not apply destructive Console changes without explicit approval.**

## Required before production App Check enforcement

| # | Action | Notes |
|---|---|---|
| 1 | Firebase Console → **App Check** → register Android app `com.ora.ora` | Play Integrity provider |
| 2 | App Check → register iOS app `com.ora.ora` | App Attest (DeviceCheck fallback if needed) |
| 3 | Create **debug tokens** for emulator/CI only | Never embed in release binaries |
| 4 | Deploy rules: `firebase deploy --only firestore:rules` | After reviewing `firestore.rules` |
| 5 | Deploy indexes if any added later | `firestore.indexes.json` currently empty |
| 6 | Set Cloud Run / backend `REQUIRE_APP_CHECK=true` | Only after client sends valid tokens in staging |
| 7 | **Do not** turn on App Check **Enforce** globally until staging E2E passes | Monitor metrics first |

## Authentication provider drift (approval required to change)

| Provider | Console | Product | Recommendation |
|---|---|---|---|
| Phone | Enabled | Used | Keep |
| Google | Enabled | **Not in Flutter app** | **Disable after explicit approval** (reduces attack surface) |
| Email/Password | Enabled | **Not in Flutter app** | **Disable after explicit approval** |

## SMS / OTP (Path A)

| Item | Status |
|---|---|
| Phone numbers for testing | Dev-only free OTP |
| SMS region allowlist | Include **PK** for Pakistan |
| Real SMS | Requires Blaze near deploy |

## Secrets

| Item | Action |
|---|---|
| Service account JSON | Never in git / APK; use Secret Manager / Workload Identity in prod |
| API keys | Prefer Firebase App Check + backend auth over relying on key secrecy |
