# Feature Inventory (MVP vs Post-MVP vs Not Planned)

This inventory lists **all major product/system features** enumerated by Phase 1.5.

Legend:
- **MVP** = required for end-to-end coherent ride platform per `docs/ORA_MASTER_PLAN.md` through Phase 15.
- **POST-MVP** = architecture exists, but product UX / deeper implementation is explicitly later than MVP.
- **NOT PLANNED** = not present in the current locked product model/docs.

For each feature, the “detailed contract” (state machine, errors, API, realtime, persistence) is expected to be sourced from the authoritative docs referenced in the `Docs` column.

## Inventory

1. App bootstrap — **MVP** — `docs/product/ux-product-contract.md`, `docs/architecture/flutter-mvvm-architecture.md`
2. Configuration/environment — **MVP** — `docs/ORA_TECH_STACK.md`, `docs/architecture/flutter-mvvm-architecture.md` (Flutter), `mobile/.env.example`
3. Authentication — **MVP** — `docs/product/ux-product-contract.md` (OTP in flow), `docs/ORA_SECURITY_MODEL.md`
4. Phone OTP — **MVP** — `docs/product/ux-product-contract.md`, `docs/ORA_SECURITY_MODEL.md`
5. Account creation — **MVP** — `docs/security/abuse-prevention.md`
6. Profile — **MVP** — Firestore `users` schema
7. Passenger mode — **MVP** — `docs/product/passenger-flow.md`
8. Driver mode — **MVP** — `docs/product/driver-flow.md`
9. Driver onboarding — **MVP** — `docs/product/driver-flow.md`
10. Driver verification/KYC — **MVP** — Firestore driverDocuments + admin review (Firestore schema)
11. Vehicle registration — **MVP** — `docs/database/firestore-schema.md` (vehicles)
12. Vehicle categories — **MVP** — `docs/database/firestore-schema.md` + fare/matching category fields
13. Driver availability/online-offline — **MVP** — RTDB presence + Firestore `drivers.availabilityState`
14. Driver location — **MVP** — RTDB `tripLocations` + Redis GEO
15. Passenger location — **MVP** — pickup/destination fields in ride requests; server validates usage
16. Maps — **MVP** (integration later) — `docs/ORA_TECH_STACK.md`, `docs/architecture/maps-architecture.md`
17. Geocoding — **MVP** (integration later) — `docs/ORA_TECH_STACK.md`
18. Route calculation — **MVP** (integration later) — `docs/algorithms/matching-engine.md`, `docs/algorithms/fare-engine.md`
19. ETA — **MVP** — `docs/algorithms/matching-engine.md`, realtime freshness SLOs
20. Fare recommendation — **MVP** — `docs/algorithms/fare-engine.md`
21. Passenger offered fare — **MVP** — `docs/algorithms/offer-model.md`, `docs/api/ride-api.md`
22. Ride request — **MVP** — `docs/api/ride-api.md`, `docs/ORA_STATE_MACHINE.md`
23. Driver discovery — **MVP** — `docs/algorithms/matching-engine.md`
24. Driver eligibility — **MVP** — `docs/algorithms/matching-engine.md`
25. Driver request delivery — **MVP** — `docs/architecture/realtime-architecture.md`
26. Driver accept — **MVP** — `docs/api/ride-api.md`, `docs/algorithms/offer-model.md`
27. Driver counter-offer — **MVP** — `docs/api/ride-api.md`, `docs/algorithms/offer-model.md`
28. Passenger offer comparison — **MVP** — `docs/product/passenger-flow.md`
29. Passenger selects driver offer — **MVP** — `docs/api/ride-api.md`, `docs/algorithms/ride-assignment.md`
30. Atomic assignment — **MVP** — `docs/algorithms/ride-assignment.md`, `docs/architecture-review/system-invariants.md`
31. Offer expiration — **MVP** — `docs/ORA_STATE_MACHINE.md`, realtime & Firestore offer fields
32. Ride expiration — **MVP** — `docs/ORA_STATE_MACHINE.md`, Firestore TTL `rides.expiresAt`
33. Ride cancellation — **MVP** — `docs/ORA_STATE_MACHINE.md`, `docs/api/ride-api.md`
34. Driver arrival — **MVP** — `docs/ORA_STATE_MACHINE.md`, security + proximity checks
35. Ride start — **MVP** — `docs/ORA_STATE_MACHINE.md`
36. Active trip — **MVP** — RTDB live projection `tripLocations`
37. Live location — **MVP** — `docs/architecture/location-architecture.md`, `docs/database/realtime-schema.md`
38. Route deviation — **POST-MVP** (architecture defined) — `docs/product/safety-flow.md`
39. Ride completion — **MVP** — `docs/api/ride-api.md`, state machine
40. Payment authorization — **MVP** — `docs/product/payment-flow.md`, payment state machine
41. Payment capture — **MVP** — `docs/product/payment-flow.md`, `docs/architecture-review/payment-ledger-design.md`
42. Cash payment if supported — **MVP** — `docs/product/payment-flow.md`
43. Wallet if supported — **MVP** — `docs/product/payment-flow.md`
44. Platform fee — **MVP** — `docs/product/payment-flow.md`, Firestore `feePolicies`
45. Driver earnings — **MVP** — derived from ledger; `docs/product/payment-flow.md`
46. Immutable ledger — **MVP** — `docs/architecture-review/payment-ledger-design.md`, Firestore schema
47. Refunds — **MVP** — `docs/product/payment-flow.md`
48. Payment failure/recovery — **MVP** — `docs/product/payment-flow.md`, disaster recovery doc
49. Ratings — **MVP** — Firestore `ratings` collection
50. Reviews — **POST-MVP** (if “reviews” is more than ratings/comments) — current schema supports tags/comments in `ratings`
51. Notifications — **MVP** — FCM + in-app realtime via RTDB
52. Push notifications — **MVP** — `docs/architecture/realtime-architecture.md`
53. In-app realtime events — **MVP** — RTDB `rideSignals`, `tripLocations`
54. Safety — **MVP** — `docs/product/safety-flow.md`
55. Emergency/SOS — **MVP** (later UX) — Firestore `safetyEvents`, safety flow doc
56. Trip sharing — **POST-MVP** — `docs/product/safety-flow.md`
57. Blocking/reporting — **POST-MVP** — only partially represented via safety/driver-block checks in matching
58. Fraud/risk controls — **MVP** — `docs/security/abuse-prevention.md`, threat model
59. Driver/passenger cancellation abuse — **POST-MVP** — cancellation policy exists but abuse strategy is not exhaustively formalized
60. Search/history — **POST-MVP** — persistence primitives exist (`ride history`, `savedPlaces`) but query/state contract not fully specified
61. Ride history — **MVP** — `docs/api/ride-api.md`, Firestore ride indexes
62. Driver earnings/history — **MVP** — ledger + payout collections
63. Profile/settings — **MVP** — Firestore `users`, `savedPlaces`, authorization matrix
64. Privacy — **MVP** — `docs/ORA_SECURITY_MODEL.md`, `docs/architecture/location-trust-model.md`
65. Terms/consent — **NOT PLANNED** — no locked term/consent contract found in docs list
66. Support — **POST-MVP** — supportTickets exist in master plan; support UI flows not fully documented
67. Admin/moderation — **MVP** — authorization model + server-only capabilities
68. Observability — **MVP** — `docs/operations/observability.md`
69. Analytics — **MVP** — master plan + observability sinks
70. Feature flags — **MVP** (platform) — disaster recovery + remote config fields in runbook
71. Rate limiting — **MVP** — `docs/ORA_SECURITY_MODEL.md`, abuse prevention
72. Abuse prevention — **MVP** — `docs/security/abuse-prevention.md`
73. Backend jobs — **MVP** — expiry sweeper, bonus calculator (master plan)
74. Scheduled cleanup — **MVP** — RTDB cleanup and TTL sweeps
75. Dead-letter handling — **MVP** — outbox design + dead-letter requirement in event contracts
76. Disaster recovery — **MVP** — operations/disaster-recovery.md
77. Reconnect/recovery — **MVP** — consistency model + stale event handling + reconnect rules
78. Offline behavior — **MVP** — consistency model + read-repair requirements
79. App termination/restart recovery — **MVP** — consistency model + disaster recovery + stale event handling
80. Version compatibility — **MVP** — API versioning + event schema versioning expectations

