import {
  RideDomainError,
  type RideState,
} from './types';

/** Pre-assignment marketplace states eligible for server TTL expiry (Phase 2J). */
const EXPIRABLE: ReadonlySet<RideState> = new Set([
  'SEARCHING',
  'OFFERS_AVAILABLE',
]);

const OFFERABLE: ReadonlySet<RideState> = EXPIRABLE;

const ASSIGNABLE: ReadonlySet<RideState> = new Set([
  'SEARCHING',
  'OFFERS_AVAILABLE',
]);

/** States where passenger or assigned driver may cancel (Phase 2G). */
const CANCELLABLE_POST_ASSIGN: ReadonlySet<RideState> = new Set([
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
]);

/** Offer marketplace is closed once a driver is assigned or the ride is terminal. */
const TERMINAL_FOR_OFFERS: ReadonlySet<RideState> = new Set([
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
  'RIDE_COMPLETED',
  'RIDE_CLOSED',
  'CANCELLED',
  'EXPIRED',
  'NO_SHOW',
]);

/** Aggregate-terminal states (no further ride mutations). */
const TERMINAL: ReadonlySet<RideState> = new Set([
  'CANCELLED',
  'EXPIRED',
  'RIDE_CLOSED',
  'NO_SHOW',
]);

export function assertOfferable(state: RideState): void {
  if (!OFFERABLE.has(state)) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} does not accept offers.`,
    );
  }
}

export function assertAssignable(state: RideState): void {
  if (!ASSIGNABLE.has(state)) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} is not assignable.`,
    );
  }
}

export function assertCancellablePreAssign(state: RideState): void {
  if (!OFFERABLE.has(state)) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot be cancelled in this phase.`,
    );
  }
}

export function assertCancellablePostAssign(state: RideState): void {
  if (!CANCELLABLE_POST_ASSIGN.has(state)) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot be cancelled after assignment.`,
    );
  }
}

export function assertProgression(
  state: RideState,
  from: RideState,
  to: RideState,
): void {
  if (state !== from) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot transition to ${to} (expected ${from}).`,
    );
  }
}

export function assertCloseable(state: RideState): void {
  if (state !== 'RIDE_COMPLETED') {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot be closed (expected RIDE_COMPLETED).`,
    );
  }
}

export function isExpirable(state: RideState): boolean {
  return EXPIRABLE.has(state);
}

export function assertExpirable(state: RideState): void {
  if (!EXPIRABLE.has(state)) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot expire (expected SEARCHING or OFFERS_AVAILABLE).`,
    );
  }
}

export function isTerminalForOffers(state: RideState): boolean {
  return TERMINAL_FOR_OFFERS.has(state);
}

export function isAggregateTerminal(state: RideState): boolean {
  return TERMINAL.has(state);
}

export { TERMINAL, CANCELLABLE_POST_ASSIGN, EXPIRABLE };
