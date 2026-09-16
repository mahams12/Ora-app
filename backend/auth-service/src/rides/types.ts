export const RIDE_STATES = [
  'SEARCHING',
  'OFFERS_AVAILABLE',
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
  'RIDE_COMPLETED',
  'RIDE_CLOSED',
  'CANCELLED',
  'EXPIRED',
  'NO_SHOW',
] as const;

export type RideState = (typeof RIDE_STATES)[number];

export const OFFER_STATUSES = [
  'PENDING',
  'SELECTED',
  'SUPERSEDED',
  'WITHDRAWN',
  'EXPIRED',
] as const;

export type OfferStatus = (typeof OFFER_STATUSES)[number];

export const OFFER_TYPES = [
  'PASSENGER_PRICE_ACCEPTED',
  'DRIVER_COUNTEROFFER',
] as const;

export type OfferType = (typeof OFFER_TYPES)[number];

export const PAYMENT_METHODS = ['CASH', 'WALLET', 'ONLINE_PAYMENT'] as const;
export type PaymentMethod = (typeof PAYMENT_METHODS)[number];

/** Phase 2N — server-derived rating directions (client cannot supply). */
export const RATING_TYPES = [
  'passenger_rates_driver',
  'driver_rates_passenger',
] as const;
export type RatingType = (typeof RATING_TYPES)[number];

export interface RatingDoc {
  rideId: string;
  raterId: string;
  ratedId: string;
  ratingType: RatingType;
  stars: number;
  createdAt: string;
}

/** MVP: max pending offers superseded inside the assignment transaction. */
export const MAX_OFFERS_SUPERSEDE_IN_TXN = 50;

export const RIDE_OFFER_TTL_MS = 3 * 60 * 1000;
export const RIDE_SEARCH_TTL_MS = 5 * 60 * 1000;
/** Phase 2M — passenger wait after DRIVER_ARRIVED before server NO_SHOW. */
export const RIDE_NO_SHOW_WAIT_MS = 5 * 60 * 1000;
export const IDEMPOTENCY_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export type LatLng = { lat: number; lng: number; address?: string };

export interface PricingSnapshotDoc {
  snapshotId: string;
  recommendedFareMinor: number;
  offerBoundMinMinor: number;
  offerBoundMaxMinor: number;
  currency: string;
  pricingRulesVersion: string;
  computedAt: string;
  expiresAt: string;
  inputs?: Record<string, unknown>;
}

export interface RideDoc {
  rideId: string;
  passengerId: string;
  assignedDriverId: string | null;
  state: RideState;
  version: number;
  requestVersion: number;
  category: string;
  serviceType: string;
  pickup: LatLng;
  destination: LatLng;
  routePolyline: string | null;
  distanceKm: number | null;
  estimatedDurationMin: number | null;
  pricingSnapshotId: string;
  recommendedFareMinor: number;
  passengerOfferMinor: number;
  agreedFareMinor: number | null;
  agreedOfferId: string | null;
  agreedFareCurrency: string | null;
  feePolicySnapshot: Record<string, unknown> | null;
  paymentMethod: PaymentMethod;
  paymentIntentId: string | null;
  passengerCount: number;
  expiresAt: string;
  assignedAt: string | null;
  /** Phase 2L — wait-clock start; set once on DRIVER_ARRIVED; immutable thereafter. */
  arrivedAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  closedAt: string | null;
  cancelledBy: string | null;
  cancellationReason: string | null;
  cancellationFeeMinor: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface RideOfferDoc {
  offerId: string;
  rideId: string;
  driverId: string;
  amountMinor: number;
  currency: string;
  type: OfferType;
  status: OfferStatus;
  requestVersion: number;
  expiresAt: string;
  driverSnapshot: Record<string, unknown> | null;
  createdAt: string;
  selectedAt: string | null;
  withdrawnAt: string | null;
}

export interface IdempotencyRecordDoc {
  idempotencyKey: string;
  requestHash: string;
  actorId: string;
  operation: string;
  resourceId: string | null;
  status: 'PENDING' | 'SUCCEEDED' | 'FAILED';
  responseSnapshot: {
    httpStatus: number;
    body: unknown;
  } | null;
  createdAt: string;
  expiresAt: string;
}

export interface OutboxEventDoc {
  eventId: string;
  eventType: string;
  aggregateType: string;
  aggregateId: string;
  aggregateVersion: number;
  schemaVersion: number;
  occurredAt: string;
  correlationId: string;
  causationId: string | null;
  payload: Record<string, unknown>;
  publishState: 'PENDING';
  attemptCount: number;
  nextAttemptAt: string;
}

export class RideDomainError extends Error {
  constructor(
    readonly code: string,
    readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'RideDomainError';
  }
}

export class IdempotencyReplay {
  constructor(
    readonly httpStatus: number,
    readonly body: unknown,
  ) {}
}
