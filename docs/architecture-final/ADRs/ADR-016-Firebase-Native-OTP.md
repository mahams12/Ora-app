# ADR-016: Firebase-Native OTP (Path A)

## Status
Accepted / Locked (2026-08-20).

## Context
Phase 1.6 §4 froze a custom Ora `otpSessions` aggregate as sole OTP authority.
Phase 2 / 2A implemented **Firebase Phone Auth** instead. Rebuilding custom SMS
OTP would delay product progress and duplicate Firebase capabilities.

Phase 2A-S security audit classified this as architecture drift and required an
explicit reconciliation before claiming Phase 1.6 OTP compliance.

## Decision
**Ora uses Firebase Phone Authentication as the OTP provider for MVP and
current production intent (Path A).**

| Concern | Authority |
|---|---|
| OTP send / verify / expiry / session invalidation | **Firebase Auth** |
| Brute-force / SMS flood / quota throttling | **Firebase Auth quotas + policies** |
| Client resend UX cooldown (30s) | **Ora Flutter client** (UX only) |
| Post-login identity (`uid`) | **Firebase ID token** verified by Ora backend |
| User profile / role / ban / register | **Ora backend + Firestore (Admin SDK)** |
| App Check + API rate limits | **Ora** (required before public production) |

Ora does **not** implement `otpSessions/{sessionId}` for phone OTP in the
current product path.

## Consequences
- Phase 1.6 §4 numeric limits for a custom Ora OTP aggregate are **not claimed
  as Ora-enforced**.
- Client comments / docs must not say “Ora server enforces maxResends = 3”.
- SIM-swap residual risk remains (inherent to phone auth).
- Stolen Firebase ID tokens remain valid until expiry/revoke; mitigate with
  App Check + API rate limits (ADR-014) before public launch.
- A future Path B (custom `otpSessions`) would require a new ADR and would
  supersede this decision.

## Phase 2B additions
- Flutter App Check client wiring + backend `REQUIRE_APP_CHECK`
- Auth API rate limiting (`RATE_LIMITED`)
- Versioned fail-closed `firestore.rules`
- Production HTTPS guard for `ORA_API_BASE_URL`


## Supersedes
- Custom-server OTP authority in
  `docs/architecture-final/24-phase-1.6-condition-closure.md` section 4
  **for phone OTP delivery/verification only**.
- UX guidance retained: prefer ~30s resend cooldown in the client UI.
