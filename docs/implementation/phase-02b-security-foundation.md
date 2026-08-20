# Phase 2B — Security Foundation

**Date:** 2026-08-20  
**Status:** see final report in this chat / gate below

## Locked OTP architecture (ADR-016 Path A)

| Layer | Owns |
|---|---|
| **Firebase** | OTP generation, delivery, verification, Firebase phone-auth throttling |
| **Ora backend** | ID token verify (`checkRevoked=true`), register, profile, bans, App Check, API rate limits, future ride/payment authz |
| **Ora client** | UX (30s resend cooldown), never authoritative for uid/role/status |

The historical Phase 1.6 `otpSessions` numeric freeze is **Path B / not implemented** and **must not be claimed** as Ora-enforced.

## Implemented in Phase 2B

1. Secret hygiene report + `.gitignore` hardening + safe git init (no SA / `.env`)
2. Versioned `firestore.rules` / `firebase.json` / `firestore.indexes.json` (fail-closed)
3. Flutter App Check wiring (`firebase_app_check`) + `X-Firebase-AppCheck` on API
4. Backend App Check verify path (`REQUIRE_APP_CHECK`)
5. Auth API rate limiting (`RATE_LIMITED`, uid+ip from verified token)
6. Production / release HTTPS guard for `ORA_API_BASE_URL`
7. Error sanitization (no Firebase/internal leakage to UI; no `detail` on 401)
8. Security tests (backend + Flutter + rules contract)
9. Provider drift documented (Google / Email unused — do not auto-disable)

## Env matrix

| Env | `REQUIRE_APP_CHECK` | Client `appCheckEnabled` | HTTP API |
|---|---|---|---|
| development | `false` | `false` (default) | `http://` allowed |
| staging | `true` when client ready | `true` (or `ORA_APP_CHECK=true`) | HTTPS (unless `ORA_ALLOW_HTTP_API=true`) |
| production | `true` | `true` | HTTPS only |

## Firebase Console actions (manual — see checklist doc)

Do **not** auto-disable Google / Email. Do **not** Enforce App Check until staging is green.

## Extension point — future rate limits

Mount additional `createRateLimiter` instances on ride/payment routers later. Do not invent ride limits in Phase 2B.
