# MVP vs Post-MVP (Contract)

Definition for this architecture pass:
- **MVP** = features required for coherent end-to-end ride lifecycle (create → dispatch → offer → passenger select → assignment → arrival → start → complete → payment/ledger settlement → ratings/safety basics) with correctness, idempotency, outbox, and recovery.
- **POST-MVP** = enhancements that require additional operational UX/polish or expanded algorithms, but where the core contract already exists and correctness does not depend on the enhancement.
- **NOT PLANNED** = features not present in the current locked docs/product model.

Why this matters:
- Phase 2+ implementation must not expand beyond MVP correctness contracts without a new architecture approval.

