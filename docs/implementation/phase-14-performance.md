# Phase 14 — Performance

**Status:** NOT STARTED  
**Dependencies:** Phase 13

## Objectives

Profile, measure, and optimize until all SLOs in `ORA_LATENCY_SLO.md` are met.

## Key Activities

- Flutter DevTools profiling: CPU, memory, network, widget rebuild trace
- Firestore read audit: count reads per session; reduce to < 20
- Map render profiling: measure startup, polyline, marker performance
- GPS battery test on real device (mid-range Android)
- Load test: assignment throughput; fare estimation throughput
- Implement deferred imports for heavy screens
- Implement `compute()` for GPS Kalman filter
- Implement `select()` for all rebuild-sensitive providers
- Remove any remaining `setState()` anti-patterns
- Measure T0–T11 with observability tooling; verify against SLOs

## Acceptance Criteria

- [ ] Cold start < 3.5s P95 (measured via Firebase Performance)
- [ ] T0→T6 < 900ms P95 (measured via structured logs)
- [ ] T6→T11 < 500ms P95
- [ ] GPS battery drain < 5%/hr idle, < 8%/hr active trip (real device)
- [ ] Frame jank rate < 1% (Flutter DevTools)
- [ ] Firestore reads < 20 per cold session
- [ ] All API endpoints at SLO targets
- [ ] No regressions from Phase 13 test suite
