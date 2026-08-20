# Security Threat Model (Architecture-Level)

Authoritative sources:
- `docs/security/threat-model.md`
- `docs/security/security-model.md` (where applicable)
- `docs/security/authorization-matrix.md`
- `docs/architecture-review/authorization-audit.md`
- `docs/ORA_SECURITY_MODEL.md`

## Threats (Selected, Not Exhaustive)

1. **Client fakes assignment**
   - Attack: writes ride state directly
   - Prevention: Firestore rides collection write denied to clients; Cloud Run Admin SDK only
   - Detection: audit log on rideEvents; alert on forbidden attempts
   - Logging: include `requestId, rideId, actorId`

2. **GPS spoofing to appear at pickup**
   - Attack: mock GPS / teleport
   - Prevention: App Check + speed plausibility + geofence proximity gates for arrival/completion
   - Detection: server rejects stale/implausible; repeated violations → safetyEvent

3. **Duplicate ride acceptance race**
   - Attack: two drivers attempt assignment
   - Prevention: Firestore transaction predicates for selection/assignment; Accept only creates offer

4. **Fare manipulation**
   - Attack: submit passenger offer far outside bounds
   - Prevention: server clamps against OfferBoundPolicy; snapshot linkage; no agreedFare client write

5. **Wallet balance inflation**
   - Attack: write walletAccounts.balanceMinor
   - Prevention: walletAccounts server-only writes; ledger authoritative

6. **Token theft / JWT replay**
   - Attack: reuse token on other device
   - Prevention: short TTL + App Check on every request + rate limiting

7. **Fake completed trip for payout**
   - Attack: collusion + GPS trajectory spoof
   - Prevention: route validation, distance vs elapsed plausibility, proximity/geofence for arrival/completion
   - Gap: collusion detection relies on Phase 14 anomaly detection; present docs still label risk MEDIUM

8. **API key leakage and scraping**
   - Attack: extract Maps key
   - Prevention: key restricted by package/SHA; sensitive geocoding/routes performed server-side where possible

9. **Referral abuse**
   - Attack: self-referral with multiple accounts
   - Prevention: phone OTP + App Check device fingerprint + server referrerId check

10. **Offer flooding / duplicate offer spam**
   - Prevention: `offer:dedup:{rideId}:{driverId}` and one live non-terminal offer constraint

11. **Request/response replay attacks**
   - Prevention: durable idempotency records + requestHash + request signing for payments webhooks

12. **Webhook forgery**
   - Prevention: HMAC-SHA256 signature verification (docs/security model)
   - Detection: mismatch signature → reject + alert

13. **Notification abuse/privacy leakage**
   - Prevention: payloads must not include sensitive identifiers beyond what is necessary
   - Logging: track delivery failures and dedupe keys

## Authorization Gaps (Architecture Review Findings)

14. **RTDB authorization must be participant-scoped**
   - Risk: docs show historical/over-broad reads; final matrix requires rideAccess gating for tripLocations/rideSignals.
   - Status: closed/frozen in Phase 1.6 via `docs/architecture-final/24-phase-1.6-condition-closure.md` section 1; remaining work is implementation validation (rule tests + rollout review).

15. **Firestore rule completeness for sensitive collections**
   - Status: **closed in Phase 1.6** by `docs/architecture-final/24-phase-1.6-condition-closure.md` section 1.
   - All sensitive collections now have explicit read/write/create/update/delete ownership classification and audit requirements.

