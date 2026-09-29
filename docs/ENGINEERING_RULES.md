# Ora Engineering Rules

**Status:** CURRENT  
**Authority:** Process rules for humans and Cursor agents. Implementation truth remains **code + proofs**. Current snapshot: [`ORA_CURRENT_STATE.md`](ORA_CURRENT_STATE.md).

---

1. **Code + executable proof outrank stale markdown.** Prefer `backend/auth-service/src/**`, registered routes, Vitest, and proof scripts over narrative docs.

2. **Historical docs are not current-state truth.** Files marked `HISTORICAL` / `SUPERSEDED` (especially old audits) describe a past repo. Always start from [`ORA_CURRENT_STATE.md`](ORA_CURRENT_STATE.md).

3. **Never implement the next phase without a decision freeze.** Required: objective, frozen API/data contracts, non-goals, exit criteria (see [`implementation/PHASE_TEMPLATE.md`](implementation/PHASE_TEMPLATE.md)).

4. **Never silently expand scope.** If work requires touching ride SM, Redis write semantics, RTDB, or Flutter GPS, stop and get an explicit freeze.

5. **Never invent missing API contracts.** If a route is not registered in `src/app.ts`, it does not exist. Documented contracts without routes are **targets**, not implementations.

6. **Never invent state transitions.** Only states/transitions in `rides/types.ts` + `rides/state_machine.ts` + `ride_service.ts` are legal.

7. **Never make Redis authoritative when Firestore is SoT.** Redis GEO / `driver:online` are ephemeral projections. Assignment, availability business state, and ride state live in Firestore.

8. **Never persist GPS history into Firestore unless explicitly frozen.** N2A `locationStreams` store **cursor metadata**, not lat/lng trails.

9. **Never claim live proof from mocked/in-memory tests.** MemoryDb / MemoryRedis / Vitest ≠ Firestore emulator ≠ real Redis. Label results honestly: PASS / NOT RUN / BLOCKED / N/A.

10. **Every completed phase must identify:** implementation files, tests, proof commands, security notes, failure behavior, non-goals, and next dependency.

11. **When debugging, start from the failing observable and trace backwards** using [`diagnostics/BACKEND_TROUBLESHOOTING.md`](diagnostics/BACKEND_TROUBLESHOOTING.md) and [`architecture/N_REQUEST_FLOWS.md`](architecture/N_REQUEST_FLOWS.md).

12. **If documentation conflicts with code, report the conflict before changing either.** Prefer fixing docs to match code unless the task is an intentional behavior change.

13. **Do not use previous chat context as an undocumented architectural authority.** If a decision matters, record it in the repo (ADR / decision freeze / CURRENT_STATE).

14. **Every future architectural decision must be recorded in the repository** (ADR update, decision freeze, or CURRENT_STATE frontier note).

15. **Nearby ≠ open rides.** Nearby (N3) = drivers near passenger pickup via Redis GEO. Open marketplace (M0) = chronological `GET /v1/rides/open`.

16. **N2B is deferred until explicitly started.** Do not imply RTDB `tripLocations` exists.

17. **Do not delete historical documentation.** Mark headers; point to CURRENT_STATE.
