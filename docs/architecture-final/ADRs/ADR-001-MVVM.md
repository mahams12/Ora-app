# ADR-001: MVVM in Flutter

## Status
Accepted / Locked for Phase 1+.

## Decision
Use Flutter MVVM with feature-based Clean Architecture.
Views render UI and send user intents only.
ViewModels orchestrate presentation state and call use cases.
go_router is navigation only.

## Context
Phase 0.7 locked Flutter presentation architecture (`docs/architecture/flutter-mvvm-architecture.md`).

## Consequences
- Strong separation prevents Views from directly calling infrastructure (Firebase/Dio/data sources).
- Testability: MVVM boundary is enforced via `mobile/test/features/mvvm_layer_test.dart`.

