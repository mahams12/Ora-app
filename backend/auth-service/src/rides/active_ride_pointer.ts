import type {
  DocumentSnapshot,
  Firestore,
  Transaction,
} from 'firebase-admin/firestore';
import { PASSENGER_BLOCK_STATES } from '../services/users';
import { RideDomainError } from './types';

/**
 * DR-008 / A7 — one active ride per passenger.
 *
 * `passengerActiveRides/{passengerId}` is a deterministic pointer doc
 * read+written inside the same Firestore transaction as ride creation
 * and every terminal transition. It exists to close the concurrent-
 * create race that a query-only check cannot (phantom read on an
 * empty result set).
 *
 * Server-only collection — Firestore rules deny all client access via
 * the catch-all; only the Admin SDK touches it.
 *
 * Firestore transaction rule: ALL reads must precede ALL writes.
 * Pointer reads therefore happen in the read phase of each tx (via
 * readActiveRidePointerTx); deletes happen in the write phase (via
 * clearActiveRidePointerIfMatchTx) once the resulting state is known.
 */

export const PASSENGER_ACTIVE_RIDES_COLLECTION = 'passengerActiveRides';
export const RIDES_COLLECTION = 'rides';

/**
 * States that count as "active" for the one-ride rule — the same set
 * the passenger mode-switch guard uses (`services/users.ts`). Single
 * source of truth; do not fork this list.
 */
export const ACTIVE_RIDE_STATES: readonly string[] = PASSENGER_BLOCK_STATES;

export function isActiveRideState(state: unknown): boolean {
  return (
    typeof state === 'string' &&
    (ACTIVE_RIDE_STATES as readonly string[]).includes(state)
  );
}

/**
 * Explicit terminal states — used to decide pointer release on dynamic
 * transitions (e.g. courier mutateDelivery patch.state). Deliberately
 * NOT "anything not in ACTIVE_RIDE_STATES" so unknown/empty states can
 * never trigger a release.
 */
export const TERMINAL_RIDE_STATES: readonly string[] = [
  'RIDE_COMPLETED',
  'RETURNED',
  'RIDE_CLOSED',
  'CANCELLED',
  'EXPIRED',
  'NO_SHOW',
];

export function isTerminalRideState(state: unknown): boolean {
  return (
    typeof state === 'string' &&
    (TERMINAL_RIDE_STATES as readonly string[]).includes(state)
  );
}

export function passengerActiveRideRef(db: Firestore, passengerId: string) {
  return db
    .collection(PASSENGER_ACTIVE_RIDES_COLLECTION)
    .doc(passengerId);
}

function activeRideExistsError(rideId: string | null): RideDomainError {
  return new RideDomainError(
    'ACTIVE_RIDE_EXISTS',
    409,
    'You already have an active ride. Finish or cancel it before booking again.',
    rideId ? { activeRideId: rideId } : {},
  );
}

/**
 * Acquire check — MUST be called inside the create transaction, AFTER
 * the idempotency-record check (replays return before this runs) and
 * BEFORE any tx writes.
 *
 * Order inside the tx:
 *  1. tx.get(pointer) — if it references a ride whose state is active
 *     → 409 ACTIVE_RIDE_EXISTS.
 *  2. Legacy fallback: query rides for this passenger in an active
 *     state — catches rides created before pointer enforcement.
 *     (The query's phantom-read hole is covered by the pointer for
 *     all new creates.)
 *  3. Caller then tx.set(ride) + tx.set(pointer, {activeRideId,...}).
 *
 * Stale pointers (pointed ride missing or terminal) self-heal: the
 * acquire proceeds and overwrites the pointer.
 */
export async function assertNoActiveRideTx(
  tx: Transaction,
  db: Firestore,
  passengerId: string,
): Promise<void> {
  const pointerSnap = await tx.get(passengerActiveRideRef(db, passengerId));
  if (pointerSnap.exists) {
    const pointer = pointerSnap.data() as
      | { activeRideId?: unknown }
      | undefined;
    const pointedId =
      typeof pointer?.activeRideId === 'string' && pointer.activeRideId
        ? pointer.activeRideId
        : null;
    if (pointedId) {
      const pointedSnap = await tx.get(
        db.collection(RIDES_COLLECTION).doc(pointedId),
      );
      const pointedState = pointedSnap.exists
        ? (pointedSnap.data() as { state?: unknown } | undefined)?.state
        : null;
      if (isActiveRideState(pointedState)) {
        throw activeRideExistsError(pointedId);
      }
      // Stale pointer (terminal/missing ride) — fall through; the
      // create tx overwrites it.
    }
  }

  // Legacy rides have no pointer — detect them via the rides query.
  // Equality + IN only; no composite index required (no range/orderBy).
  const legacy = await tx.get(
    db
      .collection(RIDES_COLLECTION)
      .where('passengerId', '==', passengerId)
      .where('state', 'in', [...ACTIVE_RIDE_STATES])
      .limit(1),
  );
  if (!legacy.empty) {
    const doc = legacy.docs[0];
    const data = doc?.data() as { rideId?: unknown } | undefined;
    const rideId =
      typeof data?.rideId === 'string' ? data.rideId : (doc?.id ?? null);
    throw activeRideExistsError(rideId);
  }
}

/**
 * Acquire write — call in the SAME tx after the ride doc is written.
 */
export function writeActiveRidePointerTx(
  tx: Transaction,
  db: Firestore,
  passengerId: string,
  rideId: string,
  nowIso: string,
): void {
  tx.set(passengerActiveRideRef(db, passengerId), {
    passengerId,
    activeRideId: rideId,
    updatedAt: nowIso,
  });
}

/**
 * Read phase of a terminal transition — call alongside the other
 * tx.get reads, BEFORE any writes. Returns the pointer snapshot (or
 * null when absent) for clearActiveRidePointerIfMatchTx.
 */
export async function readActiveRidePointerTx(
  tx: Transaction,
  db: Firestore,
  passengerId: string,
) {
  return tx.get(passengerActiveRideRef(db, passengerId));
}

/**
 * Write phase of a terminal transition — call only when the resulting
 * ride state is terminal. Conditional on the pointer referencing THIS
 * ride so a stale/foreign pointer is never cleared. Missing pointer
 * docs are a safe no-op. Idempotent: safe on tx retry.
 */
export function clearActiveRidePointerIfMatchTx(
  tx: Transaction,
  db: Firestore,
  passengerId: string,
  rideId: string,
  pointerSnap: DocumentSnapshot | null,
): void {
  if (!pointerSnap?.exists) return;
  const data = pointerSnap.data() as { activeRideId?: unknown } | undefined;
  if (data?.activeRideId !== rideId) return;
  tx.delete(passengerActiveRideRef(db, passengerId));
}
