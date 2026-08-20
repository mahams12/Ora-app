# ADR-002: Clean Architecture Boundaries

## Status
Accepted / Locked.

## Decision
Adopt feature-first Clean Architecture:
`presentation` → `view_models` → `domain/use_cases` → `domain/repositories` → `data/repositories` → `data_sources`.

## Consequences
- UI cannot directly depend on infrastructure.
- Correctness-sensitive workflows are centralized in use cases.
- Enables consistent mapping of backend contracts to presentation state.

