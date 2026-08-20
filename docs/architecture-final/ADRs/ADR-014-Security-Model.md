# ADR-014: Security Model (App Check + JWT + Least Privilege)

## Status
Accepted / Locked.

## Decision
All API calls must pass:
1) App Check
2) Firebase Auth JWT
3) Server-side authorization checks
4) Firestore/RTDB least-privilege security rules

Client must treat location as untrusted input; server validates proximity and plausibility for state transitions.

