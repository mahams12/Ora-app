# Phase 2B — Security test matrix

| # | Attack | Protection | Test | Result |
|---|---|---|---|---|
| 1 | Missing token | Auth middleware 401 | backend unit | PASS |
| 2 | Malformed token | verifyIdToken fails | backend unit | PASS |
| 3 | Expired token | SDK reject | design + SDK | PASS (SDK) |
| 4 | Revoked token | `checkRevoked=true` | design + SDK | PASS (SDK) |
| 5 | Wrong Firebase project | Admin project binding | design | PASS (SDK) |
| 6 | Forged UID | Ignored | backend unit | PASS |
| 7 | Forged role | Server sets passenger | backend unit | PASS |
| 8 | Cross-user `/me` | Token uid only | backend unit | PASS |
| 9 | Duplicate registration | Transaction | backend unit | PASS |
| 10 | Concurrent registration | Transaction | backend unit | PASS / partial |
| 11 | OTP architecture | ADR-016 Path A | docs + contract | PASS |
| 12 | OTP replay | Firebase session | Firebase | N/A Ora |
| 13 | OTP resend | Firebase + 30s UX | client | PASS (UX) |
| 14 | User enumeration | Generic errors | review | PARTIAL |
| 15 | SA exposure | gitignore + hygiene | git ls-files | PASS after init |
| 16 | Firestore unauthorized read | rules deny | rules contract | PASS (static); emulator N/A locally |
| 17 | Firestore unauthorized write | rules deny | rules contract | PASS (static) |
| 18 | Auth IDOR | Token-bound | backend unit | PASS |
| 19 | Replayed register | Idempotency | backend unit | PASS |
| 20 | Token refresh race | Single-flight | Flutter tests | PASS |
| 21 | Logout | signOut + clear | Flutter tests | PASS |
| 22 | Disabled account | 403 + logout | code | PASS |
| 23 | Deleted account | Token verify fail | design | PASS (SDK) |
| 24 | Debug API in release | HTTPS + release guard | Flutter unit | PASS |
| 25 | HTTP in production | `resolveApiBaseUrl` | Flutter unit | PASS |
| 26 | Sensitive logging | No tokens in logs | tests + review | PASS |
| 27 | App Check missing | `APP_CHECK_REQUIRED` | backend unit | PASS |
| 28 | App Check invalid | `APP_CHECK_INVALID` | backend unit | PASS |
| 29 | Admin escalation | No client path | backend unit | PASS |
| 30 | Fail-closed authz | Splash hold / 401 | code + tests | PASS |

**Legend:** PASS · FAIL · N/A · REQUIRES LIVE ENVIRONMENT
