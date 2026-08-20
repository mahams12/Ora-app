# Phase 2A-S — Security Gate + OTP Path Lock

**Date:** 2026-08-20  
**Security gate:** `PASS WITH REQUIRED HARDENING`  
**OTP decision:** **Path A — Firebase-native** ([ADR-016](../architecture-final/ADRs/ADR-016-Firebase-Native-OTP.md))

## OTP reconciliation

| Item | Decision |
|---|---|
| Provider | Firebase Phone Auth |
| Ora `otpSessions` | Not implemented (Path B deferred) |
| Client cooldown | 30s UX |
| Quotas / brute-force | Firebase |
| Post-auth hardening | App Check + API rate limits (required before public prod) |

## Gate summary

- Identity path (JWT verify, no client uid/role trust): sound  
- App Check: NOT IMPLEMENTED (`appCheck=false` OK for local only)  
- API rate limits: MISSING  
- Firestore rules in repo: NOT YET CREATED (Console deny-all assumed)  
- Unused Console providers: Google + Email enabled, not in app  

Full matrix: see Phase 2A-S chat audit (2026-08-20). Do not claim production-ready until hardening list is addressed.

## Next

1. Live Phase 2A E2E (device OTP → register → `/me`)  
2. Hardening: App Check, rate limits, versioned Firestore rules, provider cleanup, release HTTP guard, git/secrets  
