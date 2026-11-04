export const RIDE_STATES = [
  'SEARCHING',
  'OFFERS_AVAILABLE',
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
  'RIDE_COMPLETED',
  'DELIVERY_FAILED',
  'RETURNING',
  'RETURNED',
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

/**
 * Ora Courier v2 — multi-stop, code-free delivery protocol.
 * Version 1 = OTP-era courier (parcelOtp present). Version 2 docs are
 * stamped at create; stops drive progression and evidence replaces codes.
 */
export const COURIER_PROTOCOL_OTP = 1;
export const COURIER_PROTOCOL_EVIDENCE = 2;

export const STOP_TYPES = ['PICKUP', 'SHOP', 'DROPOFF'] as const;
export type StopType = (typeof STOP_TYPES)[number];

export const STOP_STATUSES = [
  'PENDING',
  'ARRIVED',
  'WAITING_APPROVAL',
  'DONE',
  'FAILED',
  'SKIPPED',
] as const;
export type StopStatus = (typeof STOP_STATUSES)[number];

/** Ora Courier v2 — driver-reported per-stop failure reasons. */
export const STOP_FAILURE_REASONS = [
  'SENDER_UNAVAILABLE',
  'SHOP_CLOSED',
  'ITEM_UNAVAILABLE',
  'PRICE_REJECTED',
  'BUDGET_EXCEEDED',
  'RECEIVER_UNREACHABLE',
  'ADDRESS_INCORRECT',
  'RECEIVER_REJECTED',
  'PAYMENT_REFUSED',
  'PARCEL_DAMAGED',
  'OTHER',
] as const;
export type StopFailureReason = (typeof STOP_FAILURE_REASONS)[number];

/** Driver-reported cash settlement outcome (never platform-verified). */
export const SETTLEMENT_REPORTS = ['PAID', 'UNPAID', 'PARTIAL'] as const;
export type SettlementReport = (typeof SETTLEMENT_REPORTS)[number];

export const DISPUTE_STATUSES = ['OPEN', 'RESOLVED', 'DISMISSED'] as const;
export type DisputeStatus = (typeof DISPUTE_STATUSES)[number];

export const DISPUTE_CATEGORIES = [
  'NOT_DELIVERED',
  'PAYMENT_REFUSED',
  'ITEM_MISMATCH',
  'DAMAGED',
  'OVERCHARGE',
  'DRIVER_BEHAVIOR',
  'CUSTOMER_BEHAVIOR',
  'OTHER',
] as const;
export type DisputeCategory = (typeof DISPUTE_CATEGORIES)[number];

export interface StopItem {
  name: string;
  qty: number;
  note: string | null;
}

export interface StopQuoteItem extends StopItem {
  priceMinor: number;
}

export interface StopQuote {
  items: StopQuoteItem[];
  totalMinor: number;
  quotedAt: string;
  approvedAt: string | null;
  rejectedAt: string | null;
}

export interface StopPurchase {
  totalMinor: number;
  confirmedAt: string;
}

/** Ora Courier v2 — one ordered waypoint on a delivery itinerary. */
export interface RideStopDoc {
  seq: number;
  type: StopType;
  location: LatLng;
  label: string | null;
  instructions: string | null;
  /** buy_deliver — customer shopping list for SHOP stops. */
  items?: StopItem[];
  /** buy_deliver — per-shop spend cap (minor units). */
  shopBudgetMinor?: number | null;
  status: StopStatus;
  arrivedAt: string | null;
  doneAt: string | null;
  failedAt: string | null;
  failureReason: StopFailureReason | null;
  /** Server-measured driver-fix distance to stop at confirm time. */
  confirmedNearMeters: number | null;
  quote?: StopQuote | null;
  purchase?: StopPurchase | null;
}

/** buy_deliver — aggregate shopping bookkeeping (reimbursement, NOT fare). */
export interface ShoppingDoc {
  totalBudgetMinor: number;
  approvedTotalMinor: number;
  spentMinor: number;
  serviceFeeMinor: number;
  paymentArrangement: 'RIDER_CASH';
  attestationAcceptedAt: string | null;
}

/** Ora Courier v2 — server-computed cash breakdown; driver-reported status. */
export interface SettlementDoc {
  currency: string;
  deliveryFareMinor: number | null;
  shoppingTotalMinor: number;
  serviceFeeMinor: number;
  stopFeesMinor: number;
  totalDueMinor: number;
  driverReportedStatus: SettlementReport | null;
  driverReportedAt: string | null;
  customerAckAt: string | null;
  status: 'PENDING' | 'SETTLED' | 'DISPUTED';
}

/** Per-stop confirmation evidence recorded server-side (never blocks). */
export interface StopConfirmEvidence {
  seq: number;
  at: string;
  nearMeters: number | null;
  gpsFlag: boolean;
}

export interface DeliveryEvidence {
  confirms: StopConfirmEvidence[];
  customerAckAt: string | null;
}

export interface DisputeDoc {
  disputeId: string;
  rideId: string;
  reporterUid: string;
  reporterRole: 'passenger' | 'driver';
  category: DisputeCategory;
  message: string;
  status: DisputeStatus;
  createdAt: string;
  resolvedAt: string | null;
  resolution: string | null;
}

export const DISPUTES_COLLECTION = 'disputes';
export const DELIVERY_CONFIG_COLLECTION = 'deliveryConfig';
export const DELIVERY_CONFIG_DOC_ID = 'global';

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

/** Ora Courier — parcel size classes surfaced in the booking UI. */
export const PARCEL_SIZES = ['SMALL', 'MEDIUM', 'LARGE'] as const;
export type ParcelSize = (typeof PARCEL_SIZES)[number];

/** Ora Courier — parcel content categories (drives limits/prohibited list). */
export const PARCEL_CATEGORIES = [
  'documents',
  'food',
  'fragile',
  'electronics',
  'clothing',
  'gifts',
  'other',
] as const;
export type ParcelCategory = (typeof PARCEL_CATEGORIES)[number];

/** Ora Courier — driver-reported delivery failure reasons. */
export const DELIVERY_FAILURE_REASONS = [
  'RECEIVER_UNREACHABLE',
  'ADDRESS_INCORRECT',
  'RECEIVER_REJECTED',
  'PARCEL_DAMAGED',
  'OTHER',
] as const;
export type DeliveryFailureReason = (typeof DELIVERY_FAILURE_REASONS)[number];

/**
 * Ora Courier — immutable parcel manifest captured at booking.
 * Contact fields are visible to the passenger and the assigned driver only
 * (publicRide viewer projection); never exposed through open discovery or
 * invite listings beyond the driver-visible summary.
 */
export interface ParcelDetails {
  senderName: string;
  senderPhone: string;
  receiverName: string;
  receiverPhone: string;
  parcelCategory: ParcelCategory;
  size: ParcelSize;
  weightKg: number;
  quantity: number;
  description: string;
  handlingInstructions: string | null;
  /** Optional parcel photo — app-uploaded media URL (nullable, length-capped). */
  photoUrl: string | null;
}

/**
 * Ora Courier — server-issued single-use confirmation codes.
 * Generated inside the offer-select transaction; each code is consumed by its
 * transition (pickup→RIDE_STARTED, delivery→RIDE_COMPLETED, return→RETURNED).
 * Stored server-side only; exposed to the passenger via publicRide, never to
 * any driver or third party. `attempts` caps brute-force tries across codes.
 */
export interface ParcelOtp {
  pickupCode: string;
  deliveryCode: string;
  returnCode: string;
  expiresAt: string;
  attempts: number;
  pickupUsedAt: string | null;
  deliveryUsedAt: string | null;
  returnUsedAt: string | null;
}

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
  /**
   * Optional city metadata (UX/ops). NOT a spatial matching gate for N3/N4.
   * May be absent on historical rides (no backfill).
   */
  city?: string;
  /**
   * N4 — last completed dispatch wave (0 = none). Optional until first wave.
   */
  dispatchWave?: number;
  /**
   * N4 — ISO timestamp when the next wave is eligible; null when none / exhausted / stopped.
   */
  dispatchNextAt?: string | null;
  /**
   * N4 — dispatch cursor status.
   */
  dispatchStatus?: 'none' | 'active' | 'exhausted' | 'stopped';
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
  /**
   * Payout snapshot — derived once inside the offer-select transaction;
   * immutable thereafter (same immutability class as the assignment snapshot).
   * Null on rides selected before the payout model (no backfill) and whenever
   * the policy resolution was UNAVAILABLE.
   */
  driverPayoutMinor: number | null;
  platformFeeMinor: number | null;
  payoutCurrency: string | null;
  paymentMethod: PaymentMethod;
  paymentIntentId: string | null;
  passengerCount: number;
  /**
   * Ora Courier — present only when serviceType === 'courier'.
   * Validated at create; immutable thereafter (parcel contents can't change
   * once drivers have quoted on it).
   */
  parcel?: ParcelDetails;
  /**
   * Ora Courier — server-issued confirmation codes (pickup/delivery/return).
   * Present only on assigned courier rides; NEVER serialized to drivers.
   */
  parcelOtp?: ParcelOtp;
  /** Ora Courier — optional parcel-condition photo taken at pickup. */
  pickupPhotoUrl?: string | null;
  /** Ora Courier — delivery failure bookkeeping. */
  deliveryFailedAt?: string | null;
  deliveryFailedReason?: DeliveryFailureReason | null;
  /** Ora Courier — return-to-sender bookkeeping. */
  returnStartedAt?: string | null;
  returnedAt?: string | null;
  /**
   * Ora Courier v2 — delivery protocol stamp written at create.
   * Absent/1 = OTP-era (parcelOtp issued at select). 2 = code-free,
   * stops-driven. Never mutated after create.
   */
  courierProtocolVersion?: 1 | 2;
  /** Ora Courier v2 — ordered itinerary (2–maxStops). pickup=first, destination=last. */
  stops?: RideStopDoc[];
  /** Ora Courier v2 — index of the next actionable stop. */
  currentStopIndex?: number;
  /** buy_deliver — shopping budget/spend bookkeeping (reimbursement, not fare). */
  shopping?: ShoppingDoc;
  /** Ora Courier v2 — cash breakdown + driver-reported settlement status. */
  settlement?: SettlementDoc;
  /** Ora Courier v2 — per-stop confirmation evidence. */
  evidence?: DeliveryEvidence;
  /** Ora Courier v2 — at least one stop FAILED/SKIPPED before completion. */
  partialFulfillment?: boolean;
  /** Ora Courier v2 — dispute pointer (disputes collection holds the doc). */
  disputeStatus?: 'none' | 'OPEN' | 'RESOLVED' | 'DISMISSED';
  disputeId?: string | null;
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

export type OutboxPublishState =
  | 'PENDING'
  | 'CLAIMED'
  | 'DELIVERED'
  | 'DEAD_LETTER';

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
  /** Writers create PENDING; D1 projector may advance CLAIMED/DELIVERED/DEAD_LETTER. */
  publishState: OutboxPublishState;
  attemptCount: number;
  nextAttemptAt: string;
  leaseOwner?: string | null;
  leaseExpiresAt?: string | null;
  updatedAt?: string;
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
