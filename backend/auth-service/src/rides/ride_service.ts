import { randomInt, randomUUID } from 'node:crypto';
import type {
  DocumentReference,
  Firestore,
  Transaction,
} from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { hashRequest } from './hash';
import {
  assertDriverEligible,
  assertPassenger,
  loadActor,
} from './eligibility';
import {
  assertOfferWithinBounds,
  loadPricingSnapshot,
} from './pricing_snapshot';
import {
  assertPositiveIntegerMinor,
} from './money';
import {
  assertAssignable,
  assertCancellablePostAssign,
  assertCancellablePreAssign,
  assertCloseable,
  assertExpirable,
  assertOfferable,
  assertProgression,
  COURIER_PARCEL_IN_TRANSIT,
  isExpirable,
} from './state_machine';
import type { TripLocationRtdb } from '../rtdb/types';
import type { LocationStreamStore } from '../location/stream_store';
import { NullTripLocationRtdb } from '../rtdb/admin_trip_location_rtdb';
import {
  cleanupTripLocationOnTerminal,
  grantRideLocationAccess,
} from '../rtdb/ride_location_lifecycle';
import {
  assertOfferSelectableForAssignment,
  assertOfferWithdrawable,
  effectiveOfferStatus,
} from './offer_lifecycle';
import {
  FEE_POLICIES_COLLECTION,
  GLOBAL_FEE_POLICY_ID,
  derivePayoutSnapshot,
  parseFeePolicyDoc,
  type FeePolicyDoc,
} from '../pricing/fee_policy';
import {
  COURIER_PROTOCOL_EVIDENCE,
  DELIVERY_FAILURE_REASONS,
  DISPUTE_CATEGORIES,
  DISPUTES_COLLECTION,
  IDEMPOTENCY_TTL_MS,
  IdempotencyReplay,
  MAX_OFFERS_SUPERSEDE_IN_TXN,
  PARCEL_CATEGORIES,
  PARCEL_SIZES,
  RIDE_NO_SHOW_WAIT_MS,
  RIDE_OFFER_TTL_MS,
  RIDE_SEARCH_TTL_MS,
  RideDomainError,
  SETTLEMENT_REPORTS,
  STOP_FAILURE_REASONS,
  type DeliveryFailureReason,
  type DisputeCategory,
  type DisputeDoc,
  type LatLng,
  type OfferType,
  type ParcelCategory,
  type ParcelDetails,
  type ParcelOtp,
  type ParcelSize,
  type PaymentMethod,
  type RatingDoc,
  type RatingType,
  type RideDoc,
  type RideOfferDoc,
  type RideState,
  type RideStopDoc,
  type SettlementDoc,
  type SettlementReport,
  type ShoppingDoc,
  type StopFailureReason,
  type StopItem,
  type StopStatus,
  type StopType,
} from './types';
import {
  isProhibitedItem,
  loadDeliveryConfig,
} from '../delivery/delivery_config';
import {
  completedStates,
  decodeListCursor,
  encodeListCursor,
  ownerBinding,
  parseRideListQuery,
  RIDE_LIST_SERVICE_TYPES,
  type RideListQueryRole,
} from './list_query';
import {
  OPEN_DISCOVERY_SCAN_CAP,
  RIDE_LIST_CURSOR_VERSION,
  discoveryBinding,
  parseOpenDiscoveryQuery,
} from './open_discovery_query';
import { normalizeCitySlug } from '../redis/types';

const RIDES = 'rides';
const OFFERS = 'rideOffers';
const RATINGS = 'ratings';
const IDEM = 'idempotencyRecords';
const OUTBOX = 'outboxEvents';

const EXPIRABLE_STATES = ['SEARCHING', 'OFFERS_AVAILABLE'] as const;
const DEFAULT_SWEEP_BATCH = 100;
const MAX_SWEEP_BATCH = 200;
/** Bounded multi-pass within one NO_SHOW sweep HTTP call (2K-style). */
const MAX_NO_SHOW_SWEEP_PASSES = 20;

export type ExpireRideResult =
  | {
      outcome: 'expired';
      rideId: string;
      fromState: RideState;
      version: number;
      offersExpired: number;
    }
  | { outcome: 'already_expired'; rideId: string; offersExpired: number }
  | { outcome: 'skipped'; rideId: string; reason: string };

export type SweepExpiredRidesResult = {
  scanned: number;
  expired: number;
  alreadyExpired: number;
  skipped: number;
  failed: number;
};

/** Phase 2M — single-ride NO_SHOW outcome. */
export type MarkNoShowResult =
  | {
      outcome: 'no_show';
      rideId: string;
      fromState: RideState;
      version: number;
      assignedDriverId?: string | null;
    }
  | {
      outcome: 'already_no_show';
      rideId: string;
      assignedDriverId?: string | null;
    }
  | { outcome: 'skipped'; rideId: string; reason: string };

export type SweepNoShowRidesResult = {
  scanned: number;
  noShowed: number;
  alreadyNoShow: number;
  skipped: number;
  failed: number;
  passes: number;
};

/** Phase 2K — why a PENDING offer is durably expired. */
export type OfferExpireReason =
  | 'offer_ttl_elapsed'
  | 'parent_ride_expired'
  | 'parent_ride_cancelled';

export type ExpireOfferResult =
  | {
      outcome: 'expired';
      offerId: string;
      rideId: string;
      reason: OfferExpireReason;
    }
  | { outcome: 'already_expired'; offerId: string; rideId: string }
  | { outcome: 'skipped'; offerId: string; reason: string };

export type SweepExpiredOffersResult = {
  scanned: number;
  expired: number;
  alreadyExpired: number;
  skipped: number;
  failed: number;
};

const MAX_PARENT_OFFER_CLEANUP_PASSES = 20;

const PAYMENT_METHODS = new Set(['CASH', 'WALLET', 'ONLINE_PAYMENT']);

/** Ora Courier — which confirmation code a transition consumes. */
export type ParcelOtpPurpose = 'pickup' | 'delivery' | 'return';

function requireIdempotencyKey(raw: string | undefined): string {
  const key = raw?.trim() ?? '';
  if (key.length < 8 || key.length > 200) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Idempotency-Key header is required (8–200 characters).',
    );
  }
  return key;
}

function parseLatLng(raw: unknown, field: string): LatLng {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} must be an object with lat/lng.`,
    );
  }
  const obj = raw as Record<string, unknown>;
  const lat = obj.lat;
  const lng = obj.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field}.lat and ${field}.lng must be numbers.`,
    );
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `${field} coordinates are out of range.`,
    );
  }
  // Omit optional address entirely when absent — Firestore rejects undefined.
  const point: LatLng = { lat, lng };
  if (typeof obj.address === 'string') {
    point.address = obj.address;
  }
  return point;
}

function publicLatLng(point: LatLng) {
  const out: LatLng = { lat: point.lat, lng: point.lng };
  if (typeof point.address === 'string') {
    out.address = point.address;
  }
  return out;
}

// ── Ora Courier ─────────────────────────────────────────────────────────────

const PARCEL_OTP_TTL_MS = 24 * 60 * 60 * 1000;
const PARCEL_OTP_MAX_ATTEMPTS = 10;

function parcelString(
  raw: unknown,
  field: string,
  opts: { min: number; max: number; required: boolean },
): string | null {
  if (raw == null || raw === '') {
    if (opts.required) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `parcel.${field} is required.`,
      );
    }
    return null;
  }
  if (typeof raw !== 'string') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `parcel.${field} must be a string.`,
    );
  }
  const v = raw.trim();
  if (v.length < opts.min || v.length > opts.max) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `parcel.${field} must be ${opts.min}–${opts.max} characters.`,
    );
  }
  return v;
}

/** Loose international phone check — digits, optional +, spaces/dashes. */
function parcelPhone(raw: unknown, field: string): string {
  const v = parcelString(raw, field, { min: 7, max: 20, required: true })!;
  if (!/^\+?[0-9][0-9\s-]{5,18}$/.test(v)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `parcel.${field} must be a valid phone number.`,
    );
  }
  return v;
}

/**
 * Validate the courier parcel manifest at booking time. Strict caps keep
 * payloads bounded; unknown keys are already rejected by createRide.
 */
function parseParcelDetails(raw: unknown): ParcelDetails {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'parcel is required for courier bookings.',
    );
  }
  const obj = raw as Record<string, unknown>;
  const allowed = new Set([
    'senderName',
    'senderPhone',
    'receiverName',
    'receiverPhone',
    'parcelCategory',
    'size',
    'weightKg',
    'quantity',
    'description',
    'handlingInstructions',
    'photoUrl',
  ]);
  const extra = Object.keys(obj).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `parcel has unknown fields: ${extra.join(', ')}.`,
    );
  }

  const parcelCategory = parcelString(obj.parcelCategory, 'parcelCategory', {
    min: 1,
    max: 30,
    required: true,
  })!;
  if (!(PARCEL_CATEGORIES as readonly string[]).includes(parcelCategory)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `parcel.parcelCategory must be one of: ${PARCEL_CATEGORIES.join(', ')}.`,
    );
  }
  const size = parcelString(obj.size, 'size', {
    min: 1,
    max: 10,
    required: true,
  })!.toUpperCase();
  if (!(PARCEL_SIZES as readonly string[]).includes(size)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'parcel.size must be SMALL, MEDIUM, or LARGE.',
    );
  }
  const weightKg = Number(obj.weightKg);
  if (!Number.isFinite(weightKg) || weightKg <= 0 || weightKg > 30) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'parcel.weightKg must be a number greater than 0 and at most 30 kg.',
    );
  }
  const quantity = Number(obj.quantity);
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'parcel.quantity must be an integer from 1 to 50.',
    );
  }
  const photoUrl = parcelString(obj.photoUrl, 'photoUrl', {
    min: 0,
    max: 500,
    required: false,
  });
  if (photoUrl != null && !/^https:\/\//i.test(photoUrl)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'parcel.photoUrl must be an https URL.',
    );
  }

  return {
    senderName: parcelString(obj.senderName, 'senderName', {
      min: 1,
      max: 80,
      required: true,
    })!,
    senderPhone: parcelPhone(obj.senderPhone, 'senderPhone'),
    receiverName: parcelString(obj.receiverName, 'receiverName', {
      min: 1,
      max: 80,
      required: true,
    })!,
    receiverPhone: parcelPhone(obj.receiverPhone, 'receiverPhone'),
    parcelCategory: parcelCategory as ParcelCategory,
    size: size as ParcelSize,
    weightKg,
    quantity,
    description: parcelString(obj.description, 'description', {
      min: 1,
      max: 500,
      required: true,
    })!,
    handlingInstructions: parcelString(
      obj.handlingInstructions,
      'handlingInstructions',
      { min: 0, max: 300, required: false },
    ),
    photoUrl,
  };
}

function parseStopItems(raw: unknown, seq: number): StopItem[] | undefined {
  if (raw === undefined) return undefined;
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > 50) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `stops[${seq}].items must contain 1–50 items.`,
    );
  }
  return raw.map((it, i) => {
    const o = (it ?? {}) as Record<string, unknown>;
    const name = parcelString(o.name, `stops[${seq}].items[${i}].name`, {
      min: 1,
      max: 100,
      required: true,
    })!;
    const qty = Number(o.qty ?? 1);
    if (!Number.isInteger(qty) || qty < 1 || qty > 99) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `stops[${seq}].items[${i}].qty must be an integer from 1 to 99.`,
      );
    }
    const note = parcelString(o.note, `stops[${seq}].items[${i}].note`, {
      min: 0,
      max: 200,
      required: false,
    });
    return { name, qty, note };
  });
}

/**
 * Ora Courier v2 — validate + normalize the ordered itinerary.
 * pickup/destination are derived from first/last stop; stops are immutable
 * after create (post-acceptance amendments are a future phase).
 */
function parseStops(
  raw: unknown,
  serviceType: string,
  maxStops: number,
): RideStopDoc[] {
  if (!Array.isArray(raw)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'stops must be an array of waypoints.',
    );
  }
  if (raw.length < 2 || raw.length > maxStops) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `stops must contain between 2 and ${maxStops} waypoints.`,
    );
  }
  const allowedTypes =
    serviceType === 'buy_deliver'
      ? new Set<StopType>(['PICKUP', 'SHOP', 'DROPOFF'])
      : new Set<StopType>(['PICKUP', 'DROPOFF']);

  const stops: RideStopDoc[] = raw.map((s, i) => {
    const o = (s ?? {}) as Record<string, unknown>;
    const extra = Object.keys(o).filter(
      (k) =>
        !new Set([
          'type',
          'location',
          'label',
          'instructions',
          'items',
          'shopBudgetMinor',
        ]).has(k),
    );
    if (extra.length > 0) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `stops[${i}] has unknown fields: ${extra.join(', ')}.`,
      );
    }
    const type = parcelString(o.type, `stops[${i}].type`, {
      min: 1,
      max: 10,
      required: true,
    })!.toUpperCase() as StopType;
    if (!allowedTypes.has(type)) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `stops[${i}].type is not valid for ${serviceType}.`,
      );
    }
    const location = parseLatLng(o.location, `stops[${i}].location`);
    const label = parcelString(o.label, `stops[${i}].label`, {
      min: 0,
      max: 80,
      required: false,
    });
    const instructions = parcelString(
      o.instructions,
      `stops[${i}].instructions`,
      { min: 0, max: 500, required: false },
    );
    const items = parseStopItems(o.items, i);
    if (type === 'SHOP' && (!items || items.length === 0)) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `stops[${i}] (SHOP) requires a non-empty items list.`,
      );
    }
    if (type !== 'SHOP' && items !== undefined) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        `stops[${i}].items is only valid on SHOP stops.`,
      );
    }
    let shopBudgetMinor: number | null = null;
    if (o.shopBudgetMinor !== undefined && o.shopBudgetMinor !== null) {
      const b = Number(o.shopBudgetMinor);
      if (!Number.isInteger(b) || b <= 0) {
        throw new RideDomainError(
          'VALIDATION_ERROR',
          400,
          `stops[${i}].shopBudgetMinor must be a positive integer.`,
        );
      }
      shopBudgetMinor = b;
    }
    return {
      seq: i,
      type,
      location,
      label,
      instructions,
      ...(items !== undefined ? { items } : {}),
      shopBudgetMinor,
      status: 'PENDING' as StopStatus,
      arrivedAt: null,
      doneAt: null,
      failedAt: null,
      failureReason: null,
      confirmedNearMeters: null,
      quote: null,
      purchase: null,
    };
  });

  if (stops[0].type === 'DROPOFF') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'The first stop cannot be a DROPOFF.',
    );
  }
  if (stops[stops.length - 1].type !== 'DROPOFF') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'The last stop must be a DROPOFF.',
    );
  }
  if (serviceType === 'buy_deliver' && !stops.some((s) => s.type === 'SHOP')) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Buy & Deliver requires at least one SHOP stop.',
    );
  }
  return stops;
}

/** Ora Courier v2 — validate the buy_deliver shopping block. */
function parseShopping(
  raw: unknown,
  maxBudgetMinor: number,
): ShoppingDoc {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'shopping is required for buy_deliver bookings.',
    );
  }
  const o = raw as Record<string, unknown>;
  const extra = Object.keys(o).filter(
    (k) =>
      !new Set([
        'totalBudgetMinor',
        'attestationAccepted',
        'paymentArrangement',
      ]).has(k),
  );
  if (extra.length > 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `shopping has unknown fields: ${extra.join(', ')}.`,
    );
  }
  const budget = Number(o.totalBudgetMinor);
  if (!Number.isInteger(budget) || budget <= 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'shopping.totalBudgetMinor must be a positive integer.',
    );
  }
  if (budget > maxBudgetMinor) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `shopping.totalBudgetMinor exceeds the booking cap of ${maxBudgetMinor}.`,
    );
  }
  if (o.attestationAccepted !== true) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'The restricted-items attestation must be accepted.',
    );
  }
  if (
    o.paymentArrangement !== undefined &&
    o.paymentArrangement !== 'RIDER_CASH'
  ) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Only RIDER_CASH payment arrangement is supported.',
    );
  }
  return {
    totalBudgetMinor: budget,
    approvedTotalMinor: 0,
    spentMinor: 0,
    serviceFeeMinor: 0,
    paymentArrangement: 'RIDER_CASH',
    attestationAcceptedAt: new Date().toISOString(),
  };
}

/**
 * Ora Courier v2 — the driver holds goods (parcel collected or shopping
 * purchased). While true, instant cancellation is unsafe and blocked.
 */
function v2HasCustody(ride: RideDoc): boolean {
  if (ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE) return false;
  return (ride.stops ?? []).some(
    (s) =>
      s.status === 'DONE' && (s.type === 'PICKUP' || s.type === 'SHOP'),
  );
}

function haversineMeters(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number },
): number {
  const R = 6371000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/** Evidence flag thresholds — recorded, never blocking (GPS can be stale). */
const STOP_CONFIRM_NEAR_METERS = 300;
const STOP_CONFIRM_FIX_MAX_AGE_MS = 10 * 60 * 1000;

function generateParcelOtp(now: Date): ParcelOtp {
  const code = () => randomInt(0, 1_000_000).toString().padStart(6, '0');
  return {
    pickupCode: code(),
    deliveryCode: code(),
    returnCode: code(),
    expiresAt: new Date(now.getTime() + PARCEL_OTP_TTL_MS).toISOString(),
    attempts: 0,
    pickupUsedAt: null,
    deliveryUsedAt: null,
    returnUsedAt: null,
  };
}

function otpFieldForPurpose(purpose: ParcelOtpPurpose): keyof ParcelOtp {
  switch (purpose) {
    case 'pickup':
      return 'pickupCode';
    case 'delivery':
      return 'deliveryCode';
    case 'return':
      return 'returnCode';
  }
}

function otpUsedFieldForPurpose(
  purpose: ParcelOtpPurpose,
): 'pickupUsedAt' | 'deliveryUsedAt' | 'returnUsedAt' {
  switch (purpose) {
    case 'pickup':
      return 'pickupUsedAt';
    case 'delivery':
      return 'deliveryUsedAt';
    case 'return':
      return 'returnUsedAt';
  }
}

/**
 * Slice M0 — privacy-minimized open-ride discovery projection.
 * Excludes passenger identity, assignment internals, pricing snapshots, and
 * route/fee backend fields. Pickup/destination coordinates remain because they
 * are part of the ride request contract and are required for driver offer
 * evaluation (including future map display in Slice M).
 */
function publicOpenRide(ride: RideDoc) {
  return {
    rideId: ride.rideId,
    state: ride.state,
    requestVersion: ride.requestVersion,
    category: ride.category,
    serviceType: ride.serviceType,
    pickup: publicLatLng(ride.pickup),
    destination: publicLatLng(ride.destination),
    recommendedFareMinor: ride.recommendedFareMinor,
    passengerOfferMinor: ride.passengerOfferMinor,
    paymentMethod: ride.paymentMethod,
    passengerCount: ride.passengerCount,
    // Ora Courier — non-contact parcel summary only (mirrors the invite
    // projection); sender/receiver names+phones are never open-discoverable.
    ...(ride.serviceType === 'courier' && ride.parcel
      ? {
          parcel: {
            parcelCategory: ride.parcel.parcelCategory,
            size: ride.parcel.size,
            weightKg: ride.parcel.weightKg,
            quantity: ride.parcel.quantity,
            description: ride.parcel.description,
          },
        }
      : {}),
    // Ora Courier v2 — itinerary summary for driver offer evaluation:
    // types, locations, labels, shopping items; no contacts exist on stops.
    ...(ride.stops && ride.stops.length > 0
      ? {
          courierProtocolVersion: ride.courierProtocolVersion ?? null,
          stops: ride.stops.map((s) => ({
            seq: s.seq,
            type: s.type,
            location: publicLatLng(s.location),
            label: s.label,
            instructions: s.instructions,
            ...(s.items ? { items: s.items } : {}),
            shopBudgetMinor: s.shopBudgetMinor ?? null,
          })),
          shopping: ride.shopping
            ? {
                totalBudgetMinor: ride.shopping.totalBudgetMinor,
                paymentArrangement: ride.shopping.paymentArrangement,
              }
            : null,
        }
      : {}),
    distanceKm: ride.distanceKm,
    estimatedDurationMin:
      ride.estimatedDurationMin == null
        ? null
        : Math.round(ride.estimatedDurationMin),
    expiresAt: ride.expiresAt,
    createdAt: ride.createdAt,
  };
}

function isOpenDiscoverable(ride: RideDoc, nowMs: number): boolean {
  if (ride.assignedDriverId != null && ride.assignedDriverId !== '') {
    return false;
  }
  if (!EXPIRABLE_STATES.includes(ride.state as (typeof EXPIRABLE_STATES)[number])) {
    return false;
  }
  if (Date.parse(ride.expiresAt) <= nowMs) {
    return false;
  }
  return true;
}

/** Matches Firestore keyset `startAfter` on (createdAt desc, rideId desc). */
function openRideBeforeCursor(
  ride: RideDoc,
  cursor: { createdAt: string; rideId: string },
): boolean {
  if (ride.createdAt < cursor.createdAt) {
    return true;
  }
  if (ride.createdAt > cursor.createdAt) {
    return false;
  }
  return ride.rideId < cursor.rideId;
}

function compareOpenDiscovery(a: RideDoc, b: RideDoc): number {
  if (a.createdAt !== b.createdAt) {
    return a.createdAt > b.createdAt ? -1 : 1;
  }
  if (a.rideId === b.rideId) {
    return 0;
  }
  return a.rideId > b.rideId ? -1 : 1;
}

/**
 * Ride serializer. `viewer` gates payout internals — driverPayoutMinor /
 * platformFeeMinor / payoutCurrency / feePolicyResolution are driver-only:
 * passengers see the agreed fare they pay, never platform-fee internals.
 * (viewer is derived server-side from the caller's uid, never client input.)
 */
type RideViewer = 'driver' | 'passenger';

function publicRide(ride: RideDoc, viewer: RideViewer) {
  return {
    rideId: ride.rideId,
    passengerId: ride.passengerId,
    assignedDriverId: ride.assignedDriverId,
    state: ride.state,
    version: ride.version,
    requestVersion: ride.requestVersion,
    category: ride.category,
    serviceType: ride.serviceType,
    ...(typeof ride.city === 'string' ? { city: ride.city } : {}),
    pickup: ride.pickup,
    destination: ride.destination,
    pricingSnapshotId: ride.pricingSnapshotId,
    recommendedFareMinor: ride.recommendedFareMinor,
    passengerOfferMinor: ride.passengerOfferMinor,
    agreedFareMinor: ride.agreedFareMinor,
    agreedOfferId: ride.agreedOfferId,
    agreedFareCurrency: ride.agreedFareCurrency,
    ...(viewer === 'driver'
      ? {
          driverPayoutMinor: ride.driverPayoutMinor ?? null,
          platformFeeMinor: ride.platformFeeMinor ?? null,
          payoutCurrency: ride.payoutCurrency ?? null,
          feePolicyResolution:
            (ride.feePolicySnapshot as { resolution?: unknown } | null)
              ?.resolution ?? null,
        }
      : {}),
    paymentMethod: ride.paymentMethod,
    passengerCount: ride.passengerCount,
    // Ora Courier — parcel manifest + OTP codes. publicRide is only ever
    // invoked for the passenger or the assigned driver; contacts therefore
    // stay within the two authorized parties. Codes are passenger-only.
    ...(ride.serviceType === 'courier' && ride.parcel
      ? {
          parcel: ride.parcel,
        }
      : {}),
    ...((ride.serviceType === 'courier' ||
      ride.serviceType === 'buy_deliver')
      ? {
          deliveryFailedAt: ride.deliveryFailedAt ?? null,
          deliveryFailedReason: ride.deliveryFailedReason ?? null,
          returnStartedAt: ride.returnStartedAt ?? null,
          returnedAt: ride.returnedAt ?? null,
          pickupPhotoUrl: ride.pickupPhotoUrl ?? null,
        }
      : {}),
    ...(viewer === 'passenger' && ride.parcelOtp
      ? {
          otpCodes: {
            pickup: ride.parcelOtp.pickupCode,
            delivery: ride.parcelOtp.deliveryCode,
            return: ride.parcelOtp.returnCode,
            expiresAt: ride.parcelOtp.expiresAt,
            pickupUsedAt: ride.parcelOtp.pickupUsedAt,
            deliveryUsedAt: ride.parcelOtp.deliveryUsedAt,
            returnUsedAt: ride.parcelOtp.returnUsedAt,
          },
        }
      : {}),
    // Ora Courier v2 — full itinerary + settlement visible to both parties.
    ...(ride.stops && ride.stops.length > 0
      ? {
          courierProtocolVersion: ride.courierProtocolVersion ?? null,
          stops: ride.stops,
          currentStopIndex: ride.currentStopIndex ?? null,
          shopping: ride.shopping ?? null,
          settlement: ride.settlement ?? null,
          evidence: ride.evidence ?? null,
          partialFulfillment: ride.partialFulfillment ?? false,
          disputeStatus: ride.disputeStatus ?? 'none',
          disputeId: ride.disputeId ?? null,
        }
      : {}),
    expiresAt: ride.expiresAt,
    assignedAt: ride.assignedAt,
    arrivedAt: ride.arrivedAt ?? null,
    startedAt: ride.startedAt,
    completedAt: ride.completedAt,
    closedAt: ride.closedAt,
    cancelledBy: ride.cancelledBy,
    cancellationReason: ride.cancellationReason,
    createdAt: ride.createdAt,
    updatedAt: ride.updatedAt,
  };
}

function publicOffer(offer: RideOfferDoc, nowMs: number = Date.now()) {
  const status = effectiveOfferStatus(offer, nowMs);
  return {
    offerId: offer.offerId,
    rideId: offer.rideId,
    driverId: offer.driverId,
    amountMinor: offer.amountMinor,
    currency: offer.currency,
    type: offer.type,
    status,
    requestVersion: offer.requestVersion,
    expiresAt: offer.expiresAt,
    driverSnapshot: offer.driverSnapshot,
    createdAt: offer.createdAt,
    selectedAt: offer.selectedAt,
    withdrawnAt: offer.withdrawnAt,
  };
}

function publicRating(ratingId: string, rating: RatingDoc) {
  return {
    ratingId,
    rideId: rating.rideId,
    raterId: rating.raterId,
    ratedId: rating.ratedId,
    ratingType: rating.ratingType,
    stars: rating.stars,
    createdAt: rating.createdAt,
  };
}

function ratingDocId(rideId: string, ratingType: RatingType): string {
  return `${rideId}_${ratingType}`;
}

/** Phase 2N — derive direction from ride participants; never from client body. */
function deriveRatingDirection(
  ride: RideDoc,
  callerUid: string,
): { ratingType: RatingType; ratedId: string } {
  const isPassenger = ride.passengerId === callerUid;
  const isAssignedDriver = ride.assignedDriverId === callerUid;
  if (!isPassenger && !isAssignedDriver) {
    throw new RideDomainError(
      'FORBIDDEN',
      403,
      'Only the passenger or assigned driver may rate this ride.',
    );
  }
  if (isPassenger) {
    if (ride.assignedDriverId == null || ride.assignedDriverId === '') {
      throw new RideDomainError(
        'STATE_CONFLICT',
        409,
        'Ride has no assigned driver to rate.',
      );
    }
    if (ride.assignedDriverId === callerUid) {
      throw new RideDomainError(
        'FORBIDDEN',
        403,
        'Cannot rate yourself.',
      );
    }
    return {
      ratingType: 'passenger_rates_driver',
      ratedId: ride.assignedDriverId,
    };
  }
  if (ride.passengerId === callerUid) {
    throw new RideDomainError('FORBIDDEN', 403, 'Cannot rate yourself.');
  }
  return {
    ratingType: 'driver_rates_passenger',
    ratedId: ride.passengerId,
  };
}

function assertRatingEligible(state: RideState): void {
  if (
    state !== 'RIDE_COMPLETED' &&
    state !== 'RIDE_CLOSED' &&
    state !== 'RETURNED'
  ) {
    throw new RideDomainError(
      'STATE_CONFLICT',
      409,
      `Ride state ${state} cannot accept ratings.`,
    );
  }
}

function parseStars(raw: unknown): number {
  if (typeof raw !== 'number' || !Number.isInteger(raw) || !Number.isFinite(raw)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'stars must be an integer 1–5.',
    );
  }
  if (raw < 1 || raw > 5) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'stars must be an integer 1–5.',
    );
  }
  return raw;
}

function offerDocId(
  rideId: string,
  driverId: string,
  requestVersion: number,
): string {
  return `${rideId}_${driverId}_v${requestVersion}`;
}

function rejectUnknownKeys(
  body: unknown,
  allowed: Set<string>,
): Record<string, unknown> {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Request body must be a JSON object.',
    );
  }
  const obj = body as Record<string, unknown>;
  const extra = Object.keys(obj).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      `Unknown or forbidden fields: ${extra.join(', ')}.`,
    );
  }
  return obj;
}

async function readIdempotencyReplay(
  db: Firestore,
  key: string,
  requestHash: string,
  actorId: string,
): Promise<IdempotencyReplay | null> {
  const snap = await db.collection(IDEM).doc(key).get();
  if (!snap.exists) return null;
  const rec = snap.data() as {
    requestHash: string;
    actorId?: string;
    status: string;
    responseSnapshot?: { httpStatus: number; body: unknown } | null;
  };
  if (rec.actorId && rec.actorId !== actorId) {
    throw new RideDomainError(
      'IDEMPOTENCY_KEY_REUSED',
      409,
      'Idempotency-Key was reused by a different actor.',
    );
  }
  if (rec.requestHash !== requestHash) {
    throw new RideDomainError(
      'IDEMPOTENCY_KEY_REUSED',
      409,
      'Idempotency-Key was reused with a different request body.',
    );
  }
  if (
    (rec.status === 'SUCCEEDED' || rec.status === 'FAILED') &&
    rec.responseSnapshot
  ) {
    return new IdempotencyReplay(
      rec.responseSnapshot.httpStatus,
      rec.responseSnapshot.body,
    );
  }
  return null;
}

function assertIdempotencyRecord(
  rec: { requestHash: string; actorId?: string; responseSnapshot?: { httpStatus: number; body: unknown } },
  requestHash: string,
  actorId: string,
): IdempotencyReplay | null {
  if (rec.actorId && rec.actorId !== actorId) {
    throw new RideDomainError(
      'IDEMPOTENCY_KEY_REUSED',
      409,
      'Idempotency-Key was reused by a different actor.',
    );
  }
  if (rec.requestHash !== requestHash) {
    throw new RideDomainError(
      'IDEMPOTENCY_KEY_REUSED',
      409,
      'Idempotency-Key was reused with a different request body.',
    );
  }
  if (rec.responseSnapshot) {
    return new IdempotencyReplay(
      rec.responseSnapshot.httpStatus,
      rec.responseSnapshot.body,
    );
  }
  return null;
}

export class RideService {
  private readonly tripLocationRtdb: TripLocationRtdb;
  private readonly streamStore: LocationStreamStore | null;

  constructor(
    private readonly db: Firestore,
    tripLocationRtdb: TripLocationRtdb | null = null,
    streamStore: LocationStreamStore | null = null,
  ) {
    this.tripLocationRtdb = tripLocationRtdb ?? new NullTripLocationRtdb();
    this.streamStore = streamStore;
  }

  /** L2 Step 3 — grant rideAccess after durable DRIVER_ASSIGNED (best-effort). */
  private async afterRideAssigned(input: {
    rideId: string;
    passengerId: string;
    assignedDriverId: string;
    requestId: string;
  }): Promise<void> {
    await grantRideLocationAccess({
      rtdb: this.tripLocationRtdb,
      rideId: input.rideId,
      passengerId: input.passengerId,
      assignedDriverId: input.assignedDriverId,
      requestId: input.requestId,
    });
  }

  /** L2 Step 3 — terminal RTDB + stream cleanup (best-effort / idempotent). */
  private async afterRideTerminal(input: {
    rideId: string;
    assignedDriverId: string | null | undefined;
    requestId: string;
    reason: string;
  }): Promise<void> {
    await cleanupTripLocationOnTerminal({
      db: this.db,
      rtdb: this.tripLocationRtdb,
      rideId: input.rideId,
      assignedDriverId: input.assignedDriverId,
      requestId: input.requestId,
      reason: input.reason,
      streamStore: this.streamStore ?? undefined,
    });
  }

  async createRide(input: {
    caller: AuthenticatedCaller;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const actor = await loadActor(this.db, input.caller.uid);
    assertPassenger(actor);

    const body = rejectUnknownKeys(
      input.body,
      new Set([
        'pickup',
        'destination',
        'city',
        'category',
        'serviceType',
        'passengerOfferMinor',
        'pricingSnapshotId',
        'paymentMethod',
        'passengerCount',
        'parcel',
        'stops',
        'shopping',
      ]),
    );

    const requestHash = hashRequest(body);
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const now = new Date();
    const pickup = parseLatLng(body.pickup, 'pickup');
    const destination = parseLatLng(body.destination, 'destination');
    const city = normalizeCitySlug(body.city);
    if (!city) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'city is required.',
      );
    }
    const category =
      typeof body.category === 'string' && body.category.trim()
        ? body.category.trim()
        : null;
    if (!category) {
      throw new RideDomainError('VALIDATION_ERROR', 400, 'category is required.');
    }
    const serviceType =
      typeof body.serviceType === 'string' && body.serviceType.trim()
        ? body.serviceType.trim()
        : 'ride';
    if (!(RIDE_LIST_SERVICE_TYPES as readonly string[]).includes(serviceType)) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'serviceType must be one of: ride, courier, buy_deliver, intercity, move.',
      );
    }

    // Ora Courier v2 — feature gates + itinerary validation need config.
    const deliveryCfg =
      serviceType === 'courier' || serviceType === 'buy_deliver'
        ? await loadDeliveryConfig(this.db)
        : null;
    if (serviceType === 'buy_deliver' && deliveryCfg?.enableBuyDeliver === false) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'Buy & Deliver is not currently available.',
      );
    }

    // Ora Courier — parcel manifest is mandatory for courier bookings and
    // rejected on every other service type (keeps ride payloads clean).
    let parcel: ParcelDetails | undefined;
    if (serviceType === 'courier') {
      parcel = parseParcelDetails(body.parcel);
    } else if (body.parcel !== undefined) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'parcel is only valid for courier bookings.',
      );
    }

    // Ora Courier v2 — stops itinerary. `buy_deliver` requires stops;
    // `courier` with stops becomes protocol v2 (code-free); `courier`
    // without stops stays protocol v1 (OTP, old-APK compatibility).
    let stops: RideStopDoc[] | undefined;
    if (body.stops !== undefined) {
      if (serviceType !== 'courier' && serviceType !== 'buy_deliver') {
        throw new RideDomainError(
          'VALIDATION_ERROR',
          400,
          'stops is only valid for courier and buy_deliver bookings.',
        );
      }
      stops = parseStops(body.stops, serviceType, deliveryCfg?.maxStops ?? 5);
      if (
        stops[0].location.lat !== pickup.lat ||
        stops[0].location.lng !== pickup.lng ||
        stops[stops.length - 1].location.lat !== destination.lat ||
        stops[stops.length - 1].location.lng !== destination.lng
      ) {
        throw new RideDomainError(
          'VALIDATION_ERROR',
          400,
          'stops must begin at pickup and end at destination.',
        );
      }
      // Prohibited-items enforcement at booking (SHOP item names).
      if (serviceType === 'buy_deliver' && deliveryCfg) {
        for (const stop of stops) {
          for (const item of stop.items ?? []) {
            if (isProhibitedItem(item.name, deliveryCfg)) {
              throw new RideDomainError(
                'VALIDATION_ERROR',
                400,
                `Item "${item.name}" is not permitted for delivery.`,
              );
            }
          }
        }
      }
    }
    if (serviceType === 'buy_deliver' && !stops) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'stops are required for buy_deliver bookings.',
      );
    }

    let shopping: ShoppingDoc | undefined;
    if (serviceType === 'buy_deliver') {
      shopping = parseShopping(
        body.shopping,
        deliveryCfg?.maxShoppingBudgetMinor ?? 300000,
      );
      // Per-shop caps may not exceed the booking budget.
      for (const s of stops ?? []) {
        if (
          s.shopBudgetMinor != null &&
          s.shopBudgetMinor > shopping.totalBudgetMinor
        ) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            `stops[${s.seq}].shopBudgetMinor exceeds the booking budget.`,
          );
        }
      }
    } else if (body.shopping !== undefined) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'shopping is only valid for buy_deliver bookings.',
      );
    }
    const paymentMethod = body.paymentMethod;
    if (
      typeof paymentMethod !== 'string' ||
      !PAYMENT_METHODS.has(paymentMethod)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'paymentMethod must be CASH, WALLET, or ONLINE_PAYMENT.',
      );
    }
    const passengerCount =
      body.passengerCount == null ? 1 : Number(body.passengerCount);
    if (
      !Number.isInteger(passengerCount) ||
      passengerCount < 1 ||
      passengerCount > 6
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'passengerCount must be an integer from 1 to 6.',
      );
    }
    const pricingSnapshotId =
      typeof body.pricingSnapshotId === 'string'
        ? body.pricingSnapshotId
        : '';
    const snapshot = await loadPricingSnapshot(
      this.db,
      pricingSnapshotId,
      now,
    );
    const passengerOfferMinor = assertPositiveIntegerMinor(
      body.passengerOfferMinor,
      'passengerOfferMinor',
    );
    assertOfferWithinBounds(passengerOfferMinor, snapshot);

    // Snapshot↔request consistency: the offer bounds were computed for the
    // category/serviceType stored in snapshot.inputs — a create that disagrees
    // would bind a stale price to different semantics. Fields absent on older
    // snapshots skip the check (backward compatible).
    const snapServiceType = snapshot.inputs?.serviceType;
    if (
      typeof snapServiceType === 'string' &&
      snapServiceType.trim() !== '' &&
      snapServiceType !== serviceType
    ) {
      throw new RideDomainError(
        'PRICING_SNAPSHOT_MISMATCH',
        422,
        'serviceType does not match the pricing snapshot.',
      );
    }
    const snapCategory = snapshot.inputs?.category;
    if (
      typeof snapCategory === 'string' &&
      snapCategory.trim() !== '' &&
      snapCategory !== category.trim().toLowerCase()
    ) {
      throw new RideDomainError(
        'PRICING_SNAPSHOT_MISMATCH',
        422,
        'category does not match the pricing snapshot.',
      );
    }

    const rideId = randomUUID();
    const nowIso = now.toISOString();
    const ride: RideDoc = {
      rideId,
      passengerId: input.caller.uid,
      assignedDriverId: null,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category,
      serviceType,
      city,
      pickup,
      destination,
      routePolyline: null,
      distanceKm:
        typeof snapshot.inputs?.distanceKm === 'number'
          ? (snapshot.inputs.distanceKm as number)
          : null,
      estimatedDurationMin:
        typeof snapshot.inputs?.durationMin === 'number'
          ? (snapshot.inputs.durationMin as number)
          : null,
      pricingSnapshotId: snapshot.snapshotId,
      recommendedFareMinor: snapshot.recommendedFareMinor,
      passengerOfferMinor,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: null,
      driverPayoutMinor: null,
      platformFeeMinor: null,
      payoutCurrency: null,
      paymentMethod: paymentMethod as PaymentMethod,
      paymentIntentId: null,
      passengerCount,
      ...(parcel ? { parcel } : {}),
      // Ora Courier v2 — protocol stamp + itinerary. v1 (no stops) keeps the
      // OTP-era contract so the shipped APK continues to work.
      ...(stops
        ? {
            courierProtocolVersion: COURIER_PROTOCOL_EVIDENCE as 2,
            stops,
            currentStopIndex: 0,
            evidence: { confirms: [], customerAckAt: null },
            settlement: {
              currency: 'PKR',
              deliveryFareMinor: null,
              shoppingTotalMinor: 0,
              serviceFeeMinor:
                typeof snapshot.inputs?.serviceFeeMinor === 'number'
                  ? (snapshot.inputs.serviceFeeMinor as number)
                  : 0,
              stopFeesMinor:
                typeof snapshot.inputs?.stopFeesMinor === 'number'
                  ? (snapshot.inputs.stopFeesMinor as number)
                  : 0,
              totalDueMinor: 0,
              driverReportedStatus: null,
              driverReportedAt: null,
              customerAckAt: null,
              status: 'PENDING' as const,
            },
            partialFulfillment: false,
            disputeStatus: 'none' as const,
            disputeId: null,
          }
        : {}),
      ...(shopping
        ? {
            shopping: {
              ...shopping,
              serviceFeeMinor:
                typeof snapshot.inputs?.serviceFeeMinor === 'number'
                  ? (snapshot.inputs.serviceFeeMinor as number)
                  : 0,
            },
          }
        : {}),
      expiresAt: new Date(now.getTime() + RIDE_SEARCH_TTL_MS).toISOString(),
      assignedAt: null,
      arrivedAt: null,
      startedAt: null,
      completedAt: null,
      closedAt: null,
      cancelledBy: null,
      cancellationReason: null,
      cancellationFeeMinor: null,
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    const responseBody = { data: publicRide(ride, 'passenger') };

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Duplicate request is already in progress.',
          );
        }

        const rideRef = this.db.collection(RIDES).doc(rideId);
        tx.set(rideRef, ride);
        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_CREATE',
          resourceId: rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 201, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });
        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.created',
          aggregateType: 'ride',
          aggregateId: rideId,
          aggregateVersion: 1,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: { rideId, state: 'SEARCHING' },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    return { httpStatus: 201, body: responseBody };
  }

  async getRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const snap = await this.db.collection(RIDES).doc(input.rideId).get();
    if (!snap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ride = snap.data() as RideDoc;
    const uid = input.caller.uid;
    const allowed =
      ride.passengerId === uid || ride.assignedDriverId === uid;
    if (!allowed) {
      throw new RideDomainError('FORBIDDEN', 403, 'Not allowed to read this ride.');
    }
    return {
      httpStatus: 200,
      body: {
        data: publicRide(
          ride,
          ride.assignedDriverId === uid ? 'driver' : 'passenger',
        ),
      },
    };
  }

  /**
   * Phase 2I — authenticated ride history / list against `rides/{rideId}` only.
   * Ownership is derived from token + loadActor role; never from client owner ids.
   */
  async listRides(input: {
    caller: AuthenticatedCaller;
    query: Record<string, unknown>;
  }): Promise<{
    httpStatus: number;
    body: unknown;
    meta: {
      actorRole: RideListQueryRole;
      statusFilter: string;
      serviceType: string | null;
      limit: number;
      hasCursor: boolean;
      resultCount: number;
      hasNextPage: boolean;
    };
  }> {
    const actor = await loadActor(this.db, input.caller.uid);
    const parsed = parseRideListQuery(input.query);
    const isDriverEligible =
      actor.role === 'driver' && actor.driverStatus === 'approved';
    let queryRole: RideListQueryRole;
    if (parsed.as === 'driver') {
      if (!isDriverEligible) {
        throw new RideDomainError(
          'DRIVER_NOT_ELIGIBLE',
          403,
          'Driver is not approved to view driver trips.',
        );
      }
      queryRole = 'driver';
    } else if (parsed.as === 'passenger') {
      queryRole = 'passenger';
    } else {
      queryRole = isDriverEligible ? 'driver' : 'passenger';
    }
    const ownerField =
      queryRole === 'driver' ? 'assignedDriverId' : 'passengerId';
    const uid = input.caller.uid;
    const binding = ownerBinding(uid, queryRole);

    const cursor = parsed.cursor
      ? decodeListCursor(parsed.cursor, binding)
      : null;

    // firebase-admin Query is chainable; keep as any-compatible builder.
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let q: any = this.db.collection(RIDES).where(ownerField, '==', uid);

    if (parsed.serviceType) {
      q = q.where('serviceType', '==', parsed.serviceType);
    }
    if (parsed.status === 'cancelled') {
      q = q.where('state', '==', 'CANCELLED');
    } else if (parsed.status === 'completed') {
      q = q.where('state', 'in', completedStates());
    }

    q = q.orderBy('createdAt', 'desc').orderBy('rideId', 'desc');
    if (cursor) {
      q = q.startAfter(cursor.createdAt, cursor.rideId);
    }
    q = q.limit(parsed.limit);

    const snap = await q.get();
    const rides = snap.docs.map(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (doc: any) =>
        publicRide(doc.data() as RideDoc, queryRole === 'driver' ? 'driver' : 'passenger'),
    );

    let nextCursor: string | null = null;
    if (rides.length === parsed.limit && rides.length > 0) {
      const last = rides[rides.length - 1] as {
        createdAt: string;
        rideId: string;
      };
      nextCursor = encodeListCursor({
        createdAt: last.createdAt,
        rideId: last.rideId,
        v: 1,
        ob: binding,
      });
    }

    return {
      httpStatus: 200,
      body: {
        data: {
          rides,
          nextCursor,
        },
      },
      meta: {
        actorRole: queryRole,
        statusFilter: parsed.status,
        serviceType: parsed.serviceType ?? null,
        limit: parsed.limit,
        hasCursor: cursor != null,
        resultCount: rides.length,
        hasNextPage: nextCursor != null,
      },
    };
  }

  /**
   * Slice M0 — open-ride discovery for approved drivers only.
   * Dedicated from GET /v1/rides (owner/assigned/history scoped).
   */
  async listOpenRides(input: {
    caller: AuthenticatedCaller;
    query: Record<string, unknown>;
  }): Promise<{
    httpStatus: number;
    body: unknown;
    meta: {
      limit: number;
      hasCursor: boolean;
      resultCount: number;
      hasNextPage: boolean;
    };
  }> {
    const actor = await loadActor(this.db, input.caller.uid);
    assertDriverEligible(actor);

    const parsed = parseOpenDiscoveryQuery(input.query);
    const binding = discoveryBinding({
      serviceType: parsed.serviceType,
      category: parsed.category,
    });
    const cursor = parsed.cursor
      ? decodeListCursor(parsed.cursor, binding)
      : null;

    const nowMs = Date.now();
    const scanCap = Math.min(
      Math.max(parsed.limit + 1, parsed.limit * 4),
      OPEN_DISCOVERY_SCAN_CAP,
    );

    // Unordered equality query — works without the composite index required for
    // orderBy(createdAt, rideId). Sort and keyset pagination are applied in-process.
    const snap = await this.db
      .collection(RIDES)
      .where('assignedDriverId', '==', null)
      .where('state', 'in', [...EXPIRABLE_STATES])
      .limit(scanCap)
      .get();

    let eligible: RideDoc[] = [];
    for (const doc of snap.docs) {
      const ride = doc.data() as RideDoc;
      if (!isOpenDiscoverable(ride, nowMs)) continue;
      // Browse filters — exact match on stored fields; narrows the list the
      // driver sees, never what the driver is eligible for.
      if (
        parsed.serviceType !== undefined &&
        ride.serviceType !== parsed.serviceType
      ) {
        continue;
      }
      if (parsed.category !== undefined && ride.category !== parsed.category) {
        continue;
      }
      eligible.push(ride);
    }
    eligible.sort(compareOpenDiscovery);

    if (cursor) {
      eligible = eligible.filter((ride) => openRideBeforeCursor(ride, cursor));
    }

    const hasNextPage =
      eligible.length > parsed.limit || snap.docs.length === scanCap;
    const page = eligible.slice(0, parsed.limit).map(publicOpenRide);

    let nextCursor: string | null = null;
    if (hasNextPage && page.length > 0) {
      const last = page[page.length - 1] as {
        createdAt: string;
        rideId: string;
      };
      nextCursor = encodeListCursor({
        createdAt: last.createdAt,
        rideId: last.rideId,
        v: RIDE_LIST_CURSOR_VERSION,
        ob: binding,
      });
    }

    return {
      httpStatus: 200,
      body: {
        data: {
          rides: page,
          nextCursor,
        },
      },
      meta: {
        limit: parsed.limit,
        hasCursor: cursor != null,
        resultCount: page.length,
        hasNextPage: nextCursor != null,
      },
    };
  }

  async createOffer(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const actor = await loadActor(this.db, input.caller.uid);
    assertDriverEligible(actor);

    const body = rejectUnknownKeys(
      input.body,
      new Set(['type', 'amountMinor', 'expectedRequestVersion', 'message']),
    );
    const requestHash = hashRequest({
      ...body,
      rideId: input.rideId,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const type = body.type as OfferType;
    if (type !== 'PASSENGER_PRICE_ACCEPTED' && type !== 'DRIVER_COUNTEROFFER') {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'type must be PASSENGER_PRICE_ACCEPTED or DRIVER_COUNTEROFFER.',
      );
    }
    const expectedRequestVersion =
      body.expectedRequestVersion == null
        ? 1
        : Number(body.expectedRequestVersion);
    if (!Number.isInteger(expectedRequestVersion) || expectedRequestVersion < 1) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'expectedRequestVersion must be a positive integer.',
      );
    }

    const now = new Date();
    const nowIso = now.toISOString();
    const offerId = offerDocId(
      input.rideId,
      input.caller.uid,
      expectedRequestVersion,
    );

    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;
        assertOfferable(ride.state);
        if (ride.assignedDriverId) {
          throw new RideDomainError(
            'ALREADY_ASSIGNED',
            409,
            'Ride already has an assigned driver.',
          );
        }
        if (ride.requestVersion !== expectedRequestVersion) {
          throw new RideDomainError(
            'OFFER_STALE',
            422,
            'Offer requestVersion does not match the ride.',
          );
        }
        if (Date.parse(ride.expiresAt) <= now.getTime()) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Ride offer window has expired.',
          );
        }

        // Driver may not create offers while already assigned on another ride.
        const activeAssigned = await tx.get(
          this.db
            .collection(RIDES)
            .where('assignedDriverId', '==', input.caller.uid)
            .where('state', '==', 'DRIVER_ASSIGNED')
            .limit(1),
        );
        if (!activeAssigned.empty) {
          throw new RideDomainError(
            'DRIVER_NOT_ELIGIBLE',
            422,
            'Driver already has an active assigned ride.',
          );
        }

        const amountMinor = assertPositiveIntegerMinor(
          body.amountMinor,
          'amountMinor',
        );
        if (type === 'PASSENGER_PRICE_ACCEPTED') {
          if (amountMinor !== ride.passengerOfferMinor) {
            throw new RideDomainError(
              'OFFER_AMOUNT_MISMATCH',
              422,
              'PASSENGER_PRICE_ACCEPTED amount must equal passengerOfferMinor.',
            );
          }
        } else {
          const pricingRef = this.db
            .collection('pricingSnapshots')
            .doc(ride.pricingSnapshotId);
          const pricingSnap = await tx.get(pricingRef);
          if (!pricingSnap.exists) {
            throw new RideDomainError(
              'PRICING_SNAPSHOT_EXPIRED',
              422,
              'Pricing snapshot not found or expired.',
            );
          }
          const snapshot = pricingSnap.data() as {
            offerBoundMinMinor: number;
            offerBoundMaxMinor: number;
            currency: string;
            expiresAt: string;
          };
          if (Date.parse(snapshot.expiresAt) <= now.getTime()) {
            throw new RideDomainError(
              'PRICING_SNAPSHOT_EXPIRED',
              422,
              'Pricing snapshot has expired.',
            );
          }
          assertOfferWithinBounds(amountMinor, {
            snapshotId: ride.pricingSnapshotId,
            recommendedFareMinor: 0,
            offerBoundMinMinor: snapshot.offerBoundMinMinor,
            offerBoundMaxMinor: snapshot.offerBoundMaxMinor,
            currency: snapshot.currency,
            pricingRulesVersion: 'fixture',
            computedAt: nowIso,
            expiresAt: snapshot.expiresAt,
          });
        }

        const offerRef = this.db.collection(OFFERS).doc(offerId);
        const existingOffer = await tx.get(offerRef);
        if (existingOffer.exists) {
          const existing = existingOffer.data() as RideOfferDoc;
          if (existing.status === 'PENDING') {
            throw new RideDomainError(
              'OFFER_ALREADY_EXISTS',
              409,
              'Driver already has a pending offer for this ride.',
            );
          }
          throw new RideDomainError(
            'OFFER_ALREADY_EXISTS',
            409,
            'Driver already submitted an offer for this requestVersion.',
          );
        }

        const offer: RideOfferDoc = {
          offerId,
          rideId: input.rideId,
          driverId: input.caller.uid,
          amountMinor,
          currency: 'PKR',
          type,
          status: 'PENDING',
          requestVersion: ride.requestVersion,
          expiresAt: new Date(now.getTime() + RIDE_OFFER_TTL_MS).toISOString(),
          driverSnapshot: {
            displayName: null,
            role: 'driver',
          },
          createdAt: nowIso,
          selectedAt: null,
          withdrawnAt: null,
        };

        tx.set(offerRef, offer);

        let nextState = ride.state;
        let nextVersion = ride.version;
        if (ride.state === 'SEARCHING') {
          nextState = 'OFFERS_AVAILABLE';
          nextVersion = ride.version + 1;
          tx.update(rideRef, {
            state: nextState,
            version: nextVersion,
            updatedAt: nowIso,
          });
        }

        responseBody = {
          data: {
            ...publicOffer(offer),
            rideState: nextState,
            rideVersion: nextVersion,
          },
        };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_OFFER_CREATE',
          resourceId: offerId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 201, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.offer.received',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: { offerId, driverId: input.caller.uid, amountMinor },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    return { httpStatus: 201, body: responseBody };
  }

  async listOffers(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    limit?: number;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const rideSnap = await this.db.collection(RIDES).doc(input.rideId).get();
    if (!rideSnap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ride = rideSnap.data() as RideDoc;
    if (ride.passengerId !== input.caller.uid) {
      throw new RideDomainError(
        'FORBIDDEN',
        403,
        'Only the ride passenger may list offers.',
      );
    }

    const nowMs = Date.now();
    const limit = Math.min(Math.max(input.limit ?? 50, 1), MAX_OFFERS_SUPERSEDE_IN_TXN);
    const querySnap = await this.db
      .collection(OFFERS)
      .where('rideId', '==', input.rideId)
      .limit(Math.max(limit * 2, limit))
      .get();

    const offers = querySnap.docs
      .map((d) => d.data() as RideOfferDoc)
      .filter((o) => o.requestVersion === ride.requestVersion)
      .map((o) => {
        const status = effectiveOfferStatus(o, nowMs);
        return { ...o, status };
      })
      .filter((o) => o.status === 'PENDING' || o.status === 'SELECTED' || o.status === 'EXPIRED')
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .slice(0, limit);

    return {
      httpStatus: 200,
      body: {
        data: {
          offers: offers.map((o) => publicOffer(o, nowMs)),
          requestVersion: ride.requestVersion,
        },
      },
    };
  }

  async withdrawOffer(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    offerId: string;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const requestHash = hashRequest({
      rideId: input.rideId,
      offerId: input.offerId,
      op: 'withdraw',
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const offerRef = this.db.collection(OFFERS).doc(input.offerId);
        const offerSnap = await tx.get(offerRef);
        if (!offerSnap.exists) {
          throw new RideDomainError('OFFER_NOT_FOUND', 404, 'Offer not found.');
        }
        const offer = offerSnap.data() as RideOfferDoc;
        if (offer.rideId !== input.rideId) {
          throw new RideDomainError('OFFER_NOT_FOUND', 404, 'Offer not found.');
        }
        if (offer.driverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the offering driver may withdraw this offer.',
          );
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;
        if (ride.assignedDriverId) {
          throw new RideDomainError(
            'ALREADY_ASSIGNED',
            409,
            'Cannot withdraw after assignment.',
          );
        }
        if (ride.state === 'CANCELLED' || ride.state === 'EXPIRED') {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Ride state ${ride.state} does not allow offer withdrawal.`,
          );
        }

        if (offer.status === 'WITHDRAWN') {
          responseBody = {
            data: publicOffer({ ...offer, status: 'WITHDRAWN' }, now.getTime()),
          };
          tx.set(idemRef, {
            idempotencyKey,
            requestHash,
            actorId: input.caller.uid,
            operation: 'RIDE_OFFER_WITHDRAW',
            resourceId: input.offerId,
            status: 'SUCCEEDED',
            responseSnapshot: { httpStatus: 200, body: responseBody },
            createdAt: nowIso,
            expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
          });
          return;
        }

        assertOfferWithdrawable(offer, now.getTime());

        tx.update(offerRef, {
          status: 'WITHDRAWN',
          withdrawnAt: nowIso,
        });
        const updated: RideOfferDoc = {
          ...offer,
          status: 'WITHDRAWN',
          withdrawnAt: nowIso,
        };
        responseBody = { data: publicOffer(updated, now.getTime()) };
        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_OFFER_WITHDRAW',
          resourceId: input.offerId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.offer.withdrawn',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: ride.version,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            offerId: offer.offerId,
            driverId: offer.driverId,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    return { httpStatus: 200, body: responseBody };
  }

  async selectOffer(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    offerId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(
      input.body ?? {},
      new Set(['expectedVersion']),
    );
    const requestHash = hashRequest({
      rideId: input.rideId,
      offerId: input.offerId,
      expectedVersion: body.expectedVersion ?? null,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const expectedVersion =
      body.expectedVersion == null ? null : Number(body.expectedVersion);
    if (
      expectedVersion != null &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 1)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'expectedVersion must be a positive integer.',
      );
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const offerRef = this.db.collection(OFFERS).doc(input.offerId);
        const rideSnap = await tx.get(rideRef);
        const offerSnap = await tx.get(offerRef);

        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        if (!offerSnap.exists) {
          throw new RideDomainError('OFFER_NOT_FOUND', 404, 'Offer not found.');
        }

        const ride = rideSnap.data() as RideDoc;
        const offer = offerSnap.data() as RideOfferDoc;

        if (ride.passengerId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the ride passenger may select an offer.',
          );
        }

        // Idempotent success if already assigned to this offer.
        if (
          ride.state === 'DRIVER_ASSIGNED' &&
          ride.agreedOfferId === input.offerId &&
          ride.assignedDriverId === offer.driverId
        ) {
          responseBody = {
            data: {
              rideId: ride.rideId,
              state: ride.state,
              version: ride.version,
              assignedDriverId: ride.assignedDriverId,
              agreedFareMinor: ride.agreedFareMinor,
              agreedOfferId: ride.agreedOfferId,
              currency: ride.agreedFareCurrency,
            },
          };
          tx.set(idemRef, {
            idempotencyKey,
            requestHash,
            actorId: input.caller.uid,
            operation: 'RIDE_OFFER_SELECT',
            resourceId: input.rideId,
            status: 'SUCCEEDED',
            responseSnapshot: { httpStatus: 200, body: responseBody },
            createdAt: nowIso,
            expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
          });
          return;
        }

        if (ride.assignedDriverId) {
          throw new RideDomainError(
            'ALREADY_ASSIGNED',
            409,
            'Ride already has an assigned driver.',
          );
        }
        assertAssignable(ride.state);
        if (Date.parse(ride.expiresAt) <= now.getTime()) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Ride offer window has expired.',
          );
        }
        if (expectedVersion != null && ride.version !== expectedVersion) {
          throw new RideDomainError(
            'VERSION_CONFLICT',
            409,
            'Ride version does not match expectedVersion.',
          );
        }
        if (offer.rideId !== input.rideId) {
          throw new RideDomainError(
            'OFFER_NOT_FOUND',
            404,
            'Offer does not belong to this ride.',
          );
        }
        assertOfferSelectableForAssignment(offer, now.getTime());
        if (offer.requestVersion !== ride.requestVersion) {
          throw new RideDomainError(
            'OFFER_STALE',
            422,
            'Offer requestVersion does not match the ride.',
          );
        }

        // Re-check driver eligibility (user doc) — must be approved.
        const driverRef = this.db.collection('users').doc(offer.driverId);
        const driverSnap = await tx.get(driverRef);
        if (!driverSnap.exists) {
          throw new RideDomainError(
            'DRIVER_NOT_ELIGIBLE',
            422,
            'Driver profile missing.',
          );
        }
        const driver = driverSnap.data() ?? {};
        if (
          driver.banned === true ||
          driver.isActive === false ||
          driver.role !== 'driver' ||
          driver.driverStatus !== 'approved'
        ) {
          throw new RideDomainError(
            'DRIVER_NOT_ELIGIBLE',
            422,
            'Driver is no longer eligible.',
          );
        }

        // Bounded sibling supersede: read pending offers for this ride.
        const pendingQuery = await tx.get(
          this.db
            .collection(OFFERS)
            .where('rideId', '==', input.rideId)
            .where('status', '==', 'PENDING')
            .limit(MAX_OFFERS_SUPERSEDE_IN_TXN),
        );

        // Payout snapshot — read the fee policy INSIDE this transaction (all
        // reads precede writes) so derivation is atomic with assignment and
        // immune to policy changes between check and write.
        const citySlug =
          typeof ride.city === 'string' ? ride.city.trim().toLowerCase() : '';
        const scopedPolicyId = citySlug
          ? `${citySlug}_${ride.category}`
          : null;
        let policyDoc: FeePolicyDoc | null = null;
        if (scopedPolicyId) {
          const snap = await tx.get(
            this.db.collection(FEE_POLICIES_COLLECTION).doc(scopedPolicyId),
          );
          if (snap.exists) {
            policyDoc = parseFeePolicyDoc(scopedPolicyId, snap.data());
          }
        }
        if (policyDoc == null) {
          const snap = await tx.get(
            this.db
              .collection(FEE_POLICIES_COLLECTION)
              .doc(GLOBAL_FEE_POLICY_ID),
          );
          if (snap.exists) {
            policyDoc = parseFeePolicyDoc(GLOBAL_FEE_POLICY_ID, snap.data());
          }
        }
        const payout = derivePayoutSnapshot({
          fareMinor: offer.amountMinor,
          currency: offer.currency,
          policy: policyDoc,
          capturedAt: nowIso,
        });

        const nextVersion = ride.version + 1;
        tx.update(rideRef, {
          state: 'DRIVER_ASSIGNED',
          assignedDriverId: offer.driverId,
          agreedOfferId: offer.offerId,
          agreedFareMinor: offer.amountMinor,
          agreedFareCurrency: offer.currency,
          feePolicySnapshot: payout.feePolicySnapshot,
          driverPayoutMinor: payout.driverPayoutMinor,
          platformFeeMinor: payout.platformFeeMinor,
          payoutCurrency: payout.payoutCurrency,
          assignedAt: nowIso,
          version: nextVersion,
          updatedAt: nowIso,
          // Ora Courier — issue pickup/delivery/return codes at assignment.
          // Single-use, expiring, passenger-visible only.
          // v2 bookings (courierProtocolVersion=2) are code-free — no OTP.
          ...(ride.serviceType === 'courier' &&
          ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE
            ? { parcelOtp: generateParcelOtp(now) }
            : {}),
          // Ora Courier v2 — fare becomes due once an offer is agreed;
          // settlement is computed server-side, never client-supplied.
          ...(ride.courierProtocolVersion === COURIER_PROTOCOL_EVIDENCE &&
          ride.settlement
            ? {
                'settlement.deliveryFareMinor': offer.amountMinor,
                // The agreed fare already includes serviceFeeMinor and
                // stopFeesMinor (estimate_service.ts: they are folded into
                // recommendedFareMinor). Only shopping spend is added on top.
                'settlement.totalDueMinor':
                  offer.amountMinor + (ride.settlement.shoppingTotalMinor ?? 0),
              }
            : {}),
        });

        tx.update(offerRef, {
          status: 'SELECTED',
          selectedAt: nowIso,
        });

        for (const doc of pendingQuery.docs) {
          if (doc.id === offer.offerId) continue;
          tx.update(doc.ref, { status: 'SUPERSEDED' });
        }

        responseBody = {
          data: {
            rideId: ride.rideId,
            state: 'DRIVER_ASSIGNED',
            version: nextVersion,
            assignedDriverId: offer.driverId,
            agreedFareMinor: offer.amountMinor,
            agreedOfferId: offer.offerId,
            currency: offer.currency,
          },
        };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_OFFER_SELECT',
          resourceId: input.rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const selectedEventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(selectedEventId), {
          eventId: selectedEventId,
          eventType: 'ride.offer.selected',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            offerId: offer.offerId,
            driverId: offer.driverId,
            amountMinor: offer.amountMinor,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });

        const assignedEventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(assignedEventId), {
          eventId: assignedEventId,
          eventType: 'ride.assigned',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            offerId: offer.offerId,
            driverId: offer.driverId,
            agreedFareMinor: offer.amountMinor,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    // L2 Step 3 — grant rideAccess from authoritative assignment snapshot.
    const assigned =
      responseBody &&
      typeof responseBody === 'object' &&
      'data' in responseBody
        ? (responseBody as {
            data: { assignedDriverId?: string | null };
          }).data
        : null;
    if (
      assigned &&
      typeof assigned.assignedDriverId === 'string' &&
      assigned.assignedDriverId
    ) {
      await this.afterRideAssigned({
        rideId: input.rideId,
        passengerId: input.caller.uid,
        assignedDriverId: assigned.assignedDriverId,
        requestId: input.correlationId,
      });
    }

    return { httpStatus: 200, body: responseBody };
  }

  async cancelRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(input.body ?? {}, new Set(['reason']));
    const requestHash = hashRequest({
      rideId: input.rideId,
      reason: body.reason ?? null,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const nowIso = new Date().toISOString();
    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;

        if (ride.state === 'CANCELLED') {
          const isOwner =
            ride.passengerId === input.caller.uid ||
            ride.assignedDriverId === input.caller.uid;
          if (!isOwner) {
            throw new RideDomainError(
              'FORBIDDEN',
              403,
              'Not allowed to cancel this ride.',
            );
          }
          responseBody = {
            data: publicRide(
              ride,
              ride.assignedDriverId === input.caller.uid
                ? 'driver'
                : 'passenger',
            ),
          };
          tx.set(idemRef, {
            idempotencyKey,
            requestHash,
            actorId: input.caller.uid,
            operation: 'RIDE_CANCEL',
            resourceId: input.rideId,
            status: 'SUCCEEDED',
            responseSnapshot: { httpStatus: 200, body: responseBody },
            createdAt: nowIso,
            expiresAt: new Date(Date.now() + IDEMPOTENCY_TTL_MS).toISOString(),
          });
          return;
        }

        const isPreAssign =
          ride.state === 'SEARCHING' || ride.state === 'OFFERS_AVAILABLE';
        const isPostAssign =
          ride.assignedDriverId != null &&
          (ride.state === 'DRIVER_ASSIGNED' ||
            ride.state === 'DRIVER_EN_ROUTE' ||
            ride.state === 'DRIVER_ARRIVED' ||
            ride.state === 'RIDE_STARTED' ||
            // Ora Courier v2 — non-custody failed deliveries stay cancellable.
            (ride.courierProtocolVersion === COURIER_PROTOCOL_EVIDENCE &&
              ride.state === 'DELIVERY_FAILED' &&
              !v2HasCustody(ride)));

        let cancelledBy: 'passenger' | 'driver';

        if (isPreAssign) {
          if (ride.passengerId !== input.caller.uid) {
            throw new RideDomainError(
              'FORBIDDEN',
              403,
              'Only the passenger may cancel before assignment.',
            );
          }
          assertCancellablePreAssign(ride.state);
          cancelledBy = 'passenger';
        } else if (isPostAssign) {
          const isPassenger = ride.passengerId === input.caller.uid;
          const isAssignedDriver = ride.assignedDriverId === input.caller.uid;
          if (!isPassenger && !isAssignedDriver) {
            throw new RideDomainError(
              'FORBIDDEN',
              403,
              'Only the passenger or assigned driver may cancel after assignment.',
            );
          }
          // Ora Courier v2 — a failed delivery WITHOUT goods/money in
          // custody may still be cancelled even though DELIVERY_FAILED is
          // not a normally-cancellable state.
          const v2NonCustodyFailed =
            ride.courierProtocolVersion === COURIER_PROTOCOL_EVIDENCE &&
            ride.state === 'DELIVERY_FAILED' &&
            !v2HasCustody(ride);
          if (!v2NonCustodyFailed) {
            assertCancellablePostAssign(ride.state);
          }
          // Ora Courier — once the parcel is picked up (RIDE_STARTED) the
          // booking can only exit via delivery or return-to-sender.
          // v1: parcel in transit by state. v2: blocked only with custody.
          if (
            (ride.serviceType === 'courier' ||
              ride.serviceType === 'buy_deliver') &&
            COURIER_PARCEL_IN_TRANSIT.has(ride.state) &&
            (ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE ||
              v2HasCustody(ride))
          ) {
            throw new RideDomainError(
              'STATE_CONFLICT',
              409,
              'A delivery in progress cannot be cancelled. The driver must complete it or return goods first.',
            );
          }
          cancelledBy = isPassenger ? 'passenger' : 'driver';
        } else {
          // Ora Courier — a parcel in driver custody can never be cancelled
          // (it must be delivered, retried, or returned to sender).
          if (
            (ride.serviceType === 'courier' ||
              ride.serviceType === 'buy_deliver') &&
            COURIER_PARCEL_IN_TRANSIT.has(ride.state) &&
            (ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE ||
              v2HasCustody(ride))
          ) {
            throw new RideDomainError(
              'STATE_CONFLICT',
              409,
              'A delivery in progress cannot be cancelled. The driver must complete it or return goods first.',
            );
          }
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Ride state ${ride.state} cannot be cancelled.`,
          );
        }

        const nextVersion = ride.version + 1;
        const reason =
          typeof body.reason === 'string' ? body.reason.slice(0, 200) : null;

        // All reads before writes (Firestore txn rule).
        let pendingOfferDocs: Array<{
          id: string;
          ref: DocumentReference;
          data: RideOfferDoc;
        }> = [];
        if (isPreAssign) {
          const pendingQuery = await tx.get(
            this.db
              .collection(OFFERS)
              .where('rideId', '==', input.rideId)
              .where('status', '==', 'PENDING')
              .limit(MAX_OFFERS_SUPERSEDE_IN_TXN),
          );
          pendingOfferDocs = pendingQuery.docs.map((doc) => ({
            id: doc.id,
            ref: doc.ref,
            data: doc.data() as RideOfferDoc,
          }));
        }

        // Retain assignedDriverId for audit after post-assign cancel.
        tx.update(rideRef, {
          state: 'CANCELLED',
          version: nextVersion,
          cancelledBy,
          cancellationReason: reason,
          cancellationFeeMinor: 0,
          updatedAt: nowIso,
        });

        for (const doc of pendingOfferDocs) {
          const pendingOffer = doc.data;
          tx.update(doc.ref, { status: 'EXPIRED' });
          // Tiny consistency fix (2K): emit contracted ride.offer.expired.
          const offerEventId = randomUUID();
          tx.set(this.db.collection(OUTBOX).doc(offerEventId), {
            eventId: offerEventId,
            eventType: 'ride.offer.expired',
            aggregateType: 'ride',
            aggregateId: input.rideId,
            aggregateVersion: nextVersion,
            schemaVersion: 1,
            occurredAt: nowIso,
            correlationId: input.correlationId,
            causationId: idempotencyKey,
            payload: {
              rideId: input.rideId,
              offerId: pendingOffer.offerId ?? doc.id,
              driverId: pendingOffer.driverId,
              reason: 'parent_ride_cancelled' as OfferExpireReason,
              expiresAt: pendingOffer.expiresAt,
            },
            publishState: 'PENDING',
            attemptCount: 0,
            nextAttemptAt: nowIso,
          });
        }

        const updated: RideDoc = {
          ...ride,
          state: 'CANCELLED',
          version: nextVersion,
          cancelledBy,
          cancellationReason: reason,
          cancellationFeeMinor: 0,
          updatedAt: nowIso,
        };
        responseBody = {
          data: publicRide(
            updated,
            updated.assignedDriverId === input.caller.uid
              ? 'driver'
              : 'passenger',
          ),
        };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_CANCEL',
          resourceId: input.rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(Date.now() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.cancelled',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: { cancelledBy, fromState: ride.state },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    const cancelledRide =
      responseBody &&
      typeof responseBody === 'object' &&
      'data' in responseBody
        ? (responseBody as { data: { assignedDriverId?: string | null } }).data
        : null;
    await this.afterRideTerminal({
      rideId: input.rideId,
      assignedDriverId: cancelledRide?.assignedDriverId ?? null,
      requestId: input.correlationId,
      reason: 'CANCELLED',
    });

    return { httpStatus: 200, body: responseBody };
  }

  async markEnRoute(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'DRIVER_ASSIGNED',
      toState: 'DRIVER_EN_ROUTE',
      operation: 'RIDE_EN_ROUTE',
      eventType: 'ride.driver.en_route',
    });
  }

  async markArrived(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'DRIVER_EN_ROUTE',
      toState: 'DRIVER_ARRIVED',
      operation: 'RIDE_ARRIVE',
      eventType: 'ride.driver.arrived',
      setArrivedAt: true,
    });
  }

  async startRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'DRIVER_ARRIVED',
      toState: 'RIDE_STARTED',
      operation: 'RIDE_START',
      eventType: 'ride.started',
      setStartedAt: true,
      // Ora Courier — parcel handover is confirmed by the sender's pickup code.
      otpPurpose: 'pickup',
      allowPickupPhoto: true,
    });
  }

  async completeRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'RIDE_STARTED',
      toState: 'RIDE_COMPLETED',
      operation: 'RIDE_COMPLETE',
      eventType: 'ride.completed',
      setCompletedAt: true,
      // Ora Courier — delivery is confirmed by the receiver's delivery code.
      otpPurpose: 'delivery',
    });
  }

  /** Ora Courier — driver reports the delivery attempt failed. */
  async failDelivery(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'RIDE_STARTED',
      toState: 'DELIVERY_FAILED',
      operation: 'DELIVERY_FAIL',
      eventType: 'ride.delivery.failed',
      requireDeliveryFailureReason: true,
    });
  }

  /** Ora Courier — driver retries the delivery after a failed attempt. */
  async retryDelivery(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'DELIVERY_FAILED',
      toState: 'RIDE_STARTED',
      operation: 'DELIVERY_RETRY',
      eventType: 'ride.delivery.retry',
      clearDeliveryFailure: true,
      // Ora Courier v2 — retrying reopens the last failed stop so it can
      // be arrived/confirmed again (no code needed).
      v2ReopenFailedStops: true,
    });
  }

  /** Ora Courier — driver begins returning the parcel to the sender. */
  async startReturn(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'DELIVERY_FAILED',
      toState: 'RETURNING',
      operation: 'RETURN_START',
      eventType: 'ride.return.started',
      setReturnStartedAt: true,
    });
  }

  /** Ora Courier — sender confirms the parcel came back (return code). */
  async completeReturn(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.progressAssignedRide({
      ...input,
      fromState: 'RETURNING',
      toState: 'RETURNED',
      operation: 'RETURN_COMPLETE',
      eventType: 'ride.returned',
      otpPurpose: 'return',
      setCompletedAt: true,
      setReturnedAt: true,
    });
  }

  private async progressAssignedRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
    fromState: RideState;
    toState: RideState;
    operation: string;
    eventType: string;
    setArrivedAt?: boolean;
    setStartedAt?: boolean;
    setCompletedAt?: boolean;
    setReturnedAt?: boolean;
    setReturnStartedAt?: boolean;
    clearDeliveryFailure?: boolean;
    requireDeliveryFailureReason?: boolean;
    allowPickupPhoto?: boolean;
    otpPurpose?: ParcelOtpPurpose;
    v2ReopenFailedStops?: boolean;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(
      input.body ?? {},
      new Set(['expectedVersion', 'otp', 'pickupPhotoUrl', 'reason']),
    );
    const requestHash = hashRequest({
      rideId: input.rideId,
      operation: input.operation,
      expectedVersion: body.expectedVersion ?? null,
      // OTP codes never enter the request hash (avoid hashing secrets); a
      // wrong code is not idempotent-replayable anyway.
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const expectedVersion =
      body.expectedVersion == null ? null : Number(body.expectedVersion);
    if (
      expectedVersion != null &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 1)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'expectedVersion must be a positive integer.',
      );
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;

    // Ora Courier — OTP pre-check (outside the txn so a wrong code can
    // durably increment attempts without aborting writes). The authoritative
    // single-use + code re-check still happens inside the transaction.
    const otpInput =
      typeof body.otp === 'string' ? body.otp.trim() : null;
    const pickupPhotoUrl =
      typeof body.pickupPhotoUrl === 'string'
        ? body.pickupPhotoUrl.trim().slice(0, 500)
        : null;
    if (pickupPhotoUrl != null && pickupPhotoUrl !== '') {
      if (!/^https:\/\//i.test(pickupPhotoUrl)) {
        throw new RideDomainError(
          'VALIDATION_ERROR',
          400,
          'pickupPhotoUrl must be an https URL.',
        );
      }
    }
    let failureReason: DeliveryFailureReason | null = null;
    if (input.requireDeliveryFailureReason) {
      const r = typeof body.reason === 'string' ? body.reason.trim() : '';
      if (!(DELIVERY_FAILURE_REASONS as readonly string[]).includes(r)) {
        throw new RideDomainError(
          'VALIDATION_ERROR',
          400,
          `reason must be one of: ${DELIVERY_FAILURE_REASONS.join(', ')}.`,
        );
      }
      failureReason = r as DeliveryFailureReason;
    }
    if (input.otpPurpose) {
      const preSnap = await this.db.collection(RIDES).doc(input.rideId).get();
      if (preSnap.exists) {
        const preRide = preSnap.data() as RideDoc;
        // Authorization precedes any attempts mutation — a non-assigned
        // caller must never be able to burn the code-attempt budget.
        if (
          preRide.serviceType === 'courier' &&
          preRide.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE &&
          preRide.state === input.fromState &&
          preRide.assignedDriverId === input.caller.uid
        ) {
          const otp = preRide.parcelOtp;
          if (!otp) {
            throw new RideDomainError(
              'STATE_CONFLICT',
              409,
              'Courier confirmation codes have not been issued for this delivery.',
            );
          }
          if ((otp.attempts ?? 0) >= PARCEL_OTP_MAX_ATTEMPTS) {
            throw new RideDomainError(
              'OTP_LOCKED',
              429,
              'Too many invalid code attempts. Contact support.',
            );
          }
          if (Date.parse(otp.expiresAt) <= now.getTime()) {
            throw new RideDomainError(
              'OTP_EXPIRED',
              410,
              'The confirmation code has expired.',
            );
          }
          const usedField = otpUsedFieldForPurpose(input.otpPurpose);
          if (otp[usedField] != null) {
            throw new RideDomainError(
              'OTP_ALREADY_USED',
              409,
              'This confirmation code was already used.',
            );
          }
          const expected = otp[otpFieldForPurpose(input.otpPurpose)];
          if (!otpInput || otpInput !== expected) {
            await this.db
              .collection(RIDES)
              .doc(input.rideId)
              .update({ 'parcelOtp.attempts': (otp.attempts ?? 0) + 1 });
            throw new RideDomainError(
              'OTP_INVALID',
              403,
              'Incorrect confirmation code.',
            );
          }
        }
      }
    }

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;

        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may progress this ride.',
          );
        }

        // Idempotent success if already at target (same logical transition done).
        if (ride.state === input.toState) {
          responseBody = { data: publicRide(ride, 'driver') };
          tx.set(idemRef, {
            idempotencyKey,
            requestHash,
            actorId: input.caller.uid,
            operation: input.operation,
            resourceId: input.rideId,
            status: 'SUCCEEDED',
            responseSnapshot: { httpStatus: 200, body: responseBody },
            createdAt: nowIso,
            expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
          });
          return;
        }

        assertProgression(ride.state, input.fromState, input.toState);

        if (expectedVersion != null && ride.version !== expectedVersion) {
          throw new RideDomainError(
            'VERSION_CONFLICT',
            409,
            'Ride version does not match expectedVersion.',
          );
        }

        // Assignment snapshot must remain immutable.
        if (
          ride.agreedFareMinor == null ||
          ride.agreedOfferId == null ||
          !ride.assignedDriverId
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Ride assignment snapshot is incomplete.',
          );
        }

        // Ora Courier — in-txn single-use re-check (closes the race between
        // the pre-check and commit; the code itself was already verified).
        // v2 deliveries are code-free — the gate only applies when an OTP
        // was actually issued (protocol v1).
        if (
          input.otpPurpose &&
          ride.serviceType === 'courier' &&
          ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE
        ) {
          const otp = ride.parcelOtp;
          const usedField = otpUsedFieldForPurpose(input.otpPurpose);
          if (!otp || otp[usedField] != null) {
            throw new RideDomainError(
              'OTP_ALREADY_USED',
              409,
              'This confirmation code was already used.',
            );
          }
        }

        // Ora Courier v2 — retry reopens the most recent FAILED stop.
        let reopenedStops: RideStopDoc[] | undefined;
        let reopenedIndex: number | undefined;
        if (
          input.v2ReopenFailedStops &&
          ride.courierProtocolVersion === COURIER_PROTOCOL_EVIDENCE &&
          Array.isArray(ride.stops)
        ) {
          let lastFailed = -1;
          ride.stops.forEach((s, i) => {
            if (s.status === 'FAILED') lastFailed = i;
          });
          if (lastFailed >= 0) {
            reopenedStops = ride.stops.map((s, i) =>
              i === lastFailed
                ? {
                    ...s,
                    status: 'PENDING' as StopStatus,
                    failedAt: null,
                    failureReason: null,
                  }
                : s,
            );
            reopenedIndex = lastFailed;
          }
        }

        const nextVersion = ride.version + 1;
        const patch: Record<string, unknown> = {
          state: input.toState,
          version: nextVersion,
          updatedAt: nowIso,
        };
        if (reopenedStops) {
          patch.stops = reopenedStops;
          patch.currentStopIndex = reopenedIndex;
        }
        // Phase 2L: set arrivedAt exactly once on first ARRIVED transition.
        if (input.setArrivedAt && ride.arrivedAt == null) {
          patch.arrivedAt = nowIso;
        }
        if (input.setStartedAt) {
          patch.startedAt = nowIso;
        }
        if (input.setCompletedAt) {
          patch.completedAt = nowIso;
        }
        // Ora Courier — exception/bookkeeping fields.
        if (input.setReturnedAt) {
          patch.returnedAt = nowIso;
        }
        if (input.setReturnStartedAt) {
          patch.returnStartedAt = nowIso;
        }
        if (input.requireDeliveryFailureReason && failureReason) {
          patch.deliveryFailedAt = nowIso;
          patch.deliveryFailedReason = failureReason;
        }
        if (input.clearDeliveryFailure) {
          patch.deliveryFailedReason = null;
        }
        if (
          input.otpPurpose &&
          ride.serviceType === 'courier' &&
          ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE
        ) {
          patch[`parcelOtp.${otpUsedFieldForPurpose(input.otpPurpose)}`] =
            nowIso;
        }
        if (input.allowPickupPhoto && pickupPhotoUrl) {
          patch.pickupPhotoUrl = pickupPhotoUrl;
        }

        tx.update(rideRef, patch);

        const arrivedAtValue =
          input.setArrivedAt && ride.arrivedAt == null
            ? nowIso
            : (ride.arrivedAt ?? null);

        const updated: RideDoc = {
          ...ride,
          state: input.toState,
          version: nextVersion,
          updatedAt: nowIso,
          arrivedAt: arrivedAtValue,
          startedAt: input.setStartedAt ? nowIso : ride.startedAt,
          completedAt: input.setCompletedAt ? nowIso : ride.completedAt,
          returnedAt: input.setReturnedAt ? nowIso : ride.returnedAt,
          returnStartedAt: input.setReturnStartedAt
            ? nowIso
            : ride.returnStartedAt,
          deliveryFailedAt:
            input.requireDeliveryFailureReason && failureReason
              ? nowIso
              : ride.deliveryFailedAt,
          deliveryFailedReason:
            input.requireDeliveryFailureReason && failureReason
              ? failureReason
              : input.clearDeliveryFailure
                ? null
                : ride.deliveryFailedReason,
          pickupPhotoUrl:
            input.allowPickupPhoto && pickupPhotoUrl
              ? pickupPhotoUrl
              : ride.pickupPhotoUrl,
          ...(reopenedStops ? { stops: reopenedStops } : {}),
          ...(reopenedIndex !== undefined
            ? { currentStopIndex: reopenedIndex }
            : {}),
        };
        responseBody = { data: publicRide(updated, 'driver') };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: input.operation,
          resourceId: input.rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: input.eventType,
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            rideId: input.rideId,
            fromState: input.fromState,
            toState: input.toState,
            actorId: input.caller.uid,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    if (
      input.toState === 'RIDE_COMPLETED' ||
      input.toState === 'RETURNED'
    ) {
      const completed =
        responseBody &&
        typeof responseBody === 'object' &&
        'data' in responseBody
          ? (responseBody as {
              data: { assignedDriverId?: string | null };
            }).data
          : null;
      await this.afterRideTerminal({
        rideId: input.rideId,
        assignedDriverId: completed?.assignedDriverId ?? null,
        requestId: input.correlationId,
        reason: input.toState,
      });
    }

    return { httpStatus: 200, body: responseBody };
  }

  // ──────────────────────────────────────────────────────────────
  // Ora Courier v2 — code-free, multi-stop delivery mutations.
  // ──────────────────────────────────────────────────────────────

  /** Read the driver's latest accepted trip fix for proximity evidence. */
  private async latestDriverFixMeters(
    rideId: string,
    stop: { lat: number; lng: number },
    nowMs: number,
  ): Promise<{ nearMeters: number | null; gpsFlag: boolean }> {
    try {
      const latest = await this.tripLocationRtdb?.getTripLocationLatest?.(
        rideId,
      );
      if (!latest || typeof latest.lat !== 'number') {
        return { nearMeters: null, gpsFlag: true };
      }
      const nearMeters = Math.round(haversineMeters(latest, stop));
      const stale =
        typeof latest.ts !== 'number' ||
        nowMs - latest.ts > STOP_CONFIRM_FIX_MAX_AGE_MS;
      return {
        nearMeters,
        gpsFlag: stale || nearMeters > STOP_CONFIRM_NEAR_METERS,
      };
    } catch {
      return { nearMeters: null, gpsFlag: true };
    }
  }

  /**
   * Shared scaffold for v2 delivery mutations: idempotency replay →
   * transaction (idem + ride doc + caller authZ via `authorize`) → patch +
   * idem record + outbox event. `apply` runs inside the txn after all reads.
   */
  private async mutateDelivery(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
    operation: string;
    eventType: string;
    allowedKeys: Set<string>;
    hashExtra?: Record<string, unknown>;
    authorize: (ride: RideDoc) => 'driver' | 'passenger';
    apply: (ctx: {
      ride: RideDoc;
      body: Record<string, unknown>;
      now: Date;
      nowIso: string;
    }) => {
      patch: Record<string, unknown>;
      rideOverrides?: Partial<RideDoc>;
      eventPayload: Record<string, unknown>;
      /** Optional extra document write executed in the same transaction. */
      extraWrite?: {
        collection: string;
        docId: string;
        data: Record<string, unknown>;
      };
    };
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(input.body ?? {}, input.allowedKeys);
    const requestHash = hashRequest({
      rideId: input.rideId,
      operation: input.operation,
      ...(input.hashExtra ?? {}),
      expectedVersion: body.expectedVersion ?? null,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const expectedVersion =
      body.expectedVersion == null ? null : Number(body.expectedVersion);
    if (
      expectedVersion != null &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 1)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'expectedVersion must be a positive integer.',
      );
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;
    let viewer: 'driver' | 'passenger' = 'driver';

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;
        viewer = input.authorize(ride);

        if (expectedVersion != null && ride.version !== expectedVersion) {
          throw new RideDomainError(
            'VERSION_CONFLICT',
            409,
            'Ride version does not match expectedVersion.',
          );
        }

        const applied = input.apply({ ride, body, now, nowIso });
        const nextVersion = ride.version + 1;
        tx.update(rideRef, {
          ...applied.patch,
          version: nextVersion,
          updatedAt: nowIso,
        });
        if (applied.extraWrite) {
          tx.set(
            this.db
              .collection(applied.extraWrite.collection)
              .doc(applied.extraWrite.docId),
            applied.extraWrite.data,
          );
        }

        const updated: RideDoc = {
          ...ride,
          ...(applied.rideOverrides ?? {}),
          version: nextVersion,
          updatedAt: nowIso,
        };
        responseBody = { data: publicRide(updated, viewer) };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: input.operation,
          resourceId: input.rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(Date.now() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: input.eventType,
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: applied.eventPayload,
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    return { httpStatus: 200, body: responseBody };
  }

  private assertV2Delivery(ride: RideDoc): void {
    if (
      ride.courierProtocolVersion !== COURIER_PROTOCOL_EVIDENCE ||
      !Array.isArray(ride.stops) ||
      ride.stops.length === 0
    ) {
      throw new RideDomainError(
        'STATE_CONFLICT',
        409,
        'This booking does not support stop progression.',
      );
    }
  }

  private currentStop(ride: RideDoc): RideStopDoc {
    const idx = ride.currentStopIndex ?? 0;
    const stop = ride.stops?.[idx];
    if (!stop) {
      throw new RideDomainError(
        'STATE_CONFLICT',
        409,
        'No actionable stop remains on this itinerary.',
      );
    }
    return stop;
  }

  /** First index with an actionable status, or -1 when the itinerary is done. */
  private nextActionableIndex(stops: RideStopDoc[]): number {
    return stops.findIndex((s) =>
      s.status === 'PENDING' ||
      s.status === 'ARRIVED' ||
      s.status === 'WAITING_APPROVAL',
    );
  }

  /** Ora Courier v2 — driver marks arrival at the current stop. */
  async arriveAtStop(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    seq: number;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.mutateDelivery({
      ...input,
      operation: 'STOP_ARRIVE',
      eventType: 'delivery.stop.arrived',
      allowedKeys: new Set(['expectedVersion']),
      authorize: (ride) => {
        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may progress stops.',
          );
        }
        this.assertV2Delivery(ride);
        return 'driver';
      },
      apply: ({ ride, nowIso }) => {
        if (
          !new Set<RideState>([
            'DRIVER_ASSIGNED',
            'DRIVER_EN_ROUTE',
            'DRIVER_ARRIVED',
            'RIDE_STARTED',
          ]).has(ride.state)
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Ride state ${ride.state} does not accept stop arrivals.`,
          );
        }
        const stop = this.currentStop(ride);
        if (stop.seq !== input.seq) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} is not the current stop.`,
          );
        }
        if (stop.status === 'ARRIVED') {
          // Idempotent success — same transition already applied.
          return {
            patch: {},
            eventPayload: {
              rideId: input.rideId,
              seq: input.seq,
              actorId: input.caller.uid,
              idempotent: true,
            },
          };
        }
        if (stop.status !== 'PENDING') {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} cannot be arrived from ${stop.status}.`,
          );
        }
        const stops = ride.stops!.map((s) =>
          s.seq === input.seq
            ? { ...s, status: 'ARRIVED' as StopStatus, arrivedAt: nowIso }
            : s,
        );
        const patch: Record<string, unknown> = { stops };
        const rideOverrides: Partial<RideDoc> = { stops };
        // First-stop arrival mirrors the existing DRIVER_ARRIVED semantics.
        if (
          input.seq === 0 &&
          (ride.state === 'DRIVER_ASSIGNED' ||
            ride.state === 'DRIVER_EN_ROUTE')
        ) {
          patch.state = 'DRIVER_ARRIVED';
          rideOverrides.state = 'DRIVER_ARRIVED';
          if (ride.arrivedAt == null) {
            patch.arrivedAt = nowIso;
            rideOverrides.arrivedAt = nowIso;
          }
        }
        return {
          patch,
          rideOverrides,
          eventPayload: {
            rideId: input.rideId,
            seq: input.seq,
            actorId: input.caller.uid,
          },
        };
      },
    });
  }

  /**
   * Ora Courier v2 — driver confirms the current stop (collected / purchased /
   * delivered). Code-free: records timestamp + GPS proximity evidence.
   */
  async confirmStop(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    seq: number;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    // Pre-txn read for GPS evidence (a failed RTDB read must not abort).
    const preSnap = await this.db
      .collection(RIDES)
      .doc(input.rideId)
      .get();
    let evidence: { nearMeters: number | null; gpsFlag: boolean } = {
      nearMeters: null,
      gpsFlag: true,
    };
    if (preSnap.exists) {
      const preRide = preSnap.data() as RideDoc;
      const stop = (preRide.stops ?? []).find((s) => s.seq === input.seq);
      if (stop && preRide.assignedDriverId === input.caller.uid) {
        evidence = await this.latestDriverFixMeters(
          input.rideId,
          stop.location,
          Date.now(),
        );
      }
    }

    let completedRide = false;
    const result = await this.mutateDelivery({
      ...input,
      operation: 'STOP_CONFIRM',
      eventType: 'delivery.stop.confirmed',
      allowedKeys: new Set(['expectedVersion', 'purchaseTotalMinor']),
      hashExtra: { seq: input.seq },
      authorize: (ride) => {
        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may progress stops.',
          );
        }
        this.assertV2Delivery(ride);
        return 'driver';
      },
      apply: ({ ride, body, nowIso }) => {
        const stop = this.currentStop(ride);
        if (stop.seq !== input.seq) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} is not the current stop.`,
          );
        }
        if (stop.status === 'DONE') {
          return {
            patch: {},
            eventPayload: {
              rideId: input.rideId,
              seq: input.seq,
              actorId: input.caller.uid,
              idempotent: true,
            },
          };
        }
        if (stop.status !== 'ARRIVED') {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} must be ARRIVED before confirm (now ${stop.status}).`,
          );
        }

        let purchase: { totalMinor: number; confirmedAt: string } | null = null;
        let shoppingSpentDelta = 0;
        if (stop.type === 'SHOP') {
          const quote = stop.quote;
          if (!quote || quote.approvedAt == null) {
            throw new RideDomainError(
              'STATE_CONFLICT',
              409,
              'Customer must approve the shopping quote before purchase.',
            );
          }
          const total = Number(body.purchaseTotalMinor);
          if (!Number.isInteger(total) || total < 0) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              'purchaseTotalMinor is required for SHOP stops.',
            );
          }
          if (total > quote.totalMinor) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              'Purchase total exceeds the customer-approved quote.',
            );
          }
          if (stop.shopBudgetMinor != null && total > stop.shopBudgetMinor) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              'Purchase total exceeds this shop’s budget cap.',
            );
          }
          const spent = ride.shopping?.spentMinor ?? 0;
          const budget = ride.shopping?.totalBudgetMinor ?? 0;
          if (spent + total > budget) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              'Purchase total exceeds the remaining shopping budget.',
            );
          }
          purchase = { totalMinor: total, confirmedAt: nowIso };
          shoppingSpentDelta = total;
        }

        const stops = ride.stops!.map((s) =>
          s.seq === input.seq
            ? {
                ...s,
                status: 'DONE' as StopStatus,
                doneAt: nowIso,
                confirmedNearMeters: evidence.nearMeters,
                ...(purchase ? { purchase } : {}),
              }
            : s,
        );
        const nextIdx = this.nextActionableIndex(stops);
        const patch: Record<string, unknown> = {
          stops,
          currentStopIndex: nextIdx === -1 ? null : nextIdx,
        };
        const rideOverrides: Partial<RideDoc> = {
          stops,
          currentStopIndex: nextIdx === -1 ? undefined : nextIdx,
        };

        // Evidence ledger.
        const confirms = [
          ...(ride.evidence?.confirms ?? []),
          {
            seq: input.seq,
            at: nowIso,
            nearMeters: evidence.nearMeters,
            gpsFlag: evidence.gpsFlag,
          },
        ];
        patch['evidence.confirms'] = confirms;
        rideOverrides.evidence = {
          confirms,
          customerAckAt: ride.evidence?.customerAckAt ?? null,
        };

        if (shoppingSpentDelta > 0 && ride.shopping) {
          const newSpent = ride.shopping.spentMinor + shoppingSpentDelta;
          patch['shopping.spentMinor'] = newSpent;
          rideOverrides.shopping = {
            ...ride.shopping,
            spentMinor: newSpent,
          };
          if (ride.settlement) {
            const newShoppingTotal =
              ride.settlement.shoppingTotalMinor + shoppingSpentDelta;
            const fare = ride.settlement.deliveryFareMinor ?? 0;
            patch['settlement.shoppingTotalMinor'] = newShoppingTotal;
            patch['settlement.totalDueMinor'] = fare + newShoppingTotal;
            rideOverrides.settlement = {
              ...ride.settlement,
              shoppingTotalMinor: newShoppingTotal,
              totalDueMinor: fare + newShoppingTotal,
            };
          }
        }

        // Custody begins → RIDE_STARTED (mirrors v1 parcel-in-transit).
        const custodyNow = stops.some(
          (s) =>
            s.status === 'DONE' &&
            (s.type === 'PICKUP' || s.type === 'SHOP'),
        );
        if (
          custodyNow &&
          new Set<RideState>([
            'DRIVER_ASSIGNED',
            'DRIVER_EN_ROUTE',
            'DRIVER_ARRIVED',
          ]).has(ride.state)
        ) {
          patch.state = 'RIDE_STARTED';
          patch.startedAt = ride.startedAt ?? nowIso;
          rideOverrides.state = 'RIDE_STARTED';
          rideOverrides.startedAt = ride.startedAt ?? nowIso;
        }

        // Itinerary exhausted → terminal outcome.
        const finalDone =
          stops[stops.length - 1].status === 'DONE';
        const anyFailed = stops.some(
          (s) => s.status === 'FAILED' || s.status === 'SKIPPED',
        );
        if (nextIdx === -1) {
          if (finalDone) {
            patch.state = 'RIDE_COMPLETED';
            patch.completedAt = nowIso;
            rideOverrides.state = 'RIDE_COMPLETED';
            rideOverrides.completedAt = nowIso;
            if (anyFailed) {
              patch.partialFulfillment = true;
              rideOverrides.partialFulfillment = true;
            }
            completedRide = true;
          } else {
            patch.state = 'DELIVERY_FAILED';
            patch.deliveryFailedAt = nowIso;
            patch.deliveryFailedReason = 'OTHER';
            rideOverrides.state = 'DELIVERY_FAILED';
            rideOverrides.deliveryFailedAt = nowIso;
          }
        }

        return {
          patch,
          rideOverrides,
          eventPayload: {
            rideId: input.rideId,
            seq: input.seq,
            actorId: input.caller.uid,
            nearMeters: evidence.nearMeters,
            gpsFlag: evidence.gpsFlag,
            purchaseTotalMinor: purchase?.totalMinor ?? null,
          },
        };
      },
    });

    if (completedRide) {
      const assigned =
        result.body &&
        typeof result.body === 'object' &&
        'data' in result.body
          ? (result.body as {
              data: { assignedDriverId?: string | null };
            }).data
          : null;
      await this.afterRideTerminal({
        rideId: input.rideId,
        assignedDriverId: assigned?.assignedDriverId ?? null,
        requestId: input.correlationId,
        reason: 'RIDE_COMPLETED',
      });
    }
    return result;
  }

  /** Ora Courier v2 — driver reports a stop failure (itinerary continues). */
  async failStop(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    seq: number;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.mutateDelivery({
      ...input,
      operation: 'STOP_FAIL',
      eventType: 'delivery.stop.failed',
      allowedKeys: new Set(['expectedVersion', 'reason']),
      hashExtra: {
        seq: input.seq,
        reason:
          typeof (input.body as Record<string, unknown> | null)?.reason ===
          'string'
            ? ((input.body as Record<string, unknown>).reason as string)
            : null,
      },
      authorize: (ride) => {
        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may progress stops.',
          );
        }
        this.assertV2Delivery(ride);
        return 'driver';
      },
      apply: ({ ride, body, nowIso }) => {
        const reason =
          typeof body.reason === 'string' ? body.reason.trim() : '';
        if (
          !(STOP_FAILURE_REASONS as readonly string[]).includes(reason)
        ) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            `reason must be one of: ${STOP_FAILURE_REASONS.join(', ')}.`,
          );
        }
        const stop = this.currentStop(ride);
        if (stop.seq !== input.seq) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} is not the current stop.`,
          );
        }
        if (stop.status === 'FAILED') {
          return {
            patch: {},
            eventPayload: {
              rideId: input.rideId,
              seq: input.seq,
              actorId: input.caller.uid,
              idempotent: true,
            },
          };
        }
        if (
          stop.status !== 'PENDING' &&
          stop.status !== 'ARRIVED' &&
          stop.status !== 'WAITING_APPROVAL'
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} cannot fail from ${stop.status}.`,
          );
        }
        const stops = ride.stops!.map((s) =>
          s.seq === input.seq
            ? {
                ...s,
                status: 'FAILED' as StopStatus,
                failedAt: nowIso,
                failureReason: reason as StopFailureReason,
              }
            : s,
        );
        const nextIdx = this.nextActionableIndex(stops);
        const patch: Record<string, unknown> = {
          stops,
          currentStopIndex: nextIdx === -1 ? null : nextIdx,
          partialFulfillment: true,
        };
        const rideOverrides: Partial<RideDoc> = {
          stops,
          currentStopIndex: nextIdx === -1 ? undefined : nextIdx,
          partialFulfillment: true,
        };
        // Itinerary exhausted without final dropoff → DELIVERY_FAILED
        // (custody-aware cancellation remains governed by v2HasCustody).
        if (
          nextIdx === -1 &&
          stops[stops.length - 1].status !== 'DONE'
        ) {
          patch.state = 'DELIVERY_FAILED';
          patch.deliveryFailedAt = nowIso;
          patch.deliveryFailedReason = 'OTHER';
          rideOverrides.state = 'DELIVERY_FAILED';
          rideOverrides.deliveryFailedAt = nowIso;
        }
        return {
          patch,
          rideOverrides,
          eventPayload: {
            rideId: input.rideId,
            seq: input.seq,
            actorId: input.caller.uid,
            reason,
          },
        };
      },
    });
  }

  /** buy_deliver — driver submits an itemized quote for the current SHOP stop. */
  async submitStopQuote(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    seq: number;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const cfg = await loadDeliveryConfig(this.db);
    return this.mutateDelivery({
      ...input,
      operation: 'STOP_QUOTE',
      eventType: 'delivery.quote.ready',
      allowedKeys: new Set(['expectedVersion', 'items']),
      hashExtra: { seq: input.seq },
      authorize: (ride) => {
        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may quote purchases.',
          );
        }
        this.assertV2Delivery(ride);
        return 'driver';
      },
      apply: ({ ride, body, nowIso }) => {
        const stop = this.currentStop(ride);
        if (stop.seq !== input.seq) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} is not the current stop.`,
          );
        }
        if (stop.type !== 'SHOP') {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            'Quotes are only valid for SHOP stops.',
          );
        }
        if (
          stop.status !== 'ARRIVED' &&
          !(stop.status === 'WAITING_APPROVAL')
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            `Stop ${input.seq} must be ARRIVED before quoting.`,
          );
        }
        const rawItems = body.items;
        if (!Array.isArray(rawItems) || rawItems.length < 1 || rawItems.length > 50) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            'items must contain 1–50 entries.',
          );
        }
        const items = rawItems.map((it, i) => {
          const o = (it ?? {}) as Record<string, unknown>;
          const name = parcelString(o.name, `items[${i}].name`, {
            min: 1,
            max: 100,
            required: true,
          })!;
          if (isProhibitedItem(name, cfg)) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              `Item "${name}" is not permitted for delivery.`,
            );
          }
          const qty = Number(o.qty ?? 1);
          if (!Number.isInteger(qty) || qty < 1 || qty > 99) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              `items[${i}].qty must be an integer from 1 to 99.`,
            );
          }
          const priceMinor = Number(o.priceMinor);
          if (!Number.isInteger(priceMinor) || priceMinor < 0) {
            throw new RideDomainError(
              'VALIDATION_ERROR',
              400,
              `items[${i}].priceMinor must be a non-negative integer.`,
            );
          }
          const note = parcelString(o.note, `items[${i}].note`, {
            min: 0,
            max: 200,
            required: false,
          });
          return { name, qty, note, priceMinor };
        });
        const totalMinor = items.reduce((s, i) => s + i.priceMinor * i.qty, 0);
        if (stop.shopBudgetMinor != null && totalMinor > stop.shopBudgetMinor) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            'Quote total exceeds this shop’s budget cap.',
          );
        }
        const spent = ride.shopping?.spentMinor ?? 0;
        const budget = ride.shopping?.totalBudgetMinor ?? 0;
        if (spent + totalMinor > budget) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            'Quote total exceeds the remaining shopping budget.',
          );
        }
        const stops = ride.stops!.map((s) =>
          s.seq === input.seq
            ? {
                ...s,
                status: 'WAITING_APPROVAL' as StopStatus,
                quote: {
                  items,
                  totalMinor,
                  quotedAt: nowIso,
                  approvedAt: null,
                  rejectedAt: null,
                },
              }
            : s,
        );
        return {
          patch: { stops },
          rideOverrides: { stops },
          eventPayload: {
            rideId: input.rideId,
            seq: input.seq,
            actorId: input.caller.uid,
            quoteTotalMinor: totalMinor,
          },
        };
      },
    });
  }

  /** buy_deliver — customer approves or rejects the pending shop quote. */
  async respondToStopQuote(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    seq: number;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.mutateDelivery({
      ...input,
      operation: 'STOP_QUOTE_RESPOND',
      eventType: 'delivery.quote.responded',
      allowedKeys: new Set(['expectedVersion', 'decision']),
      hashExtra: {
        seq: input.seq,
        decision:
          typeof (input.body as Record<string, unknown> | null)?.decision ===
          'string'
            ? ((input.body as Record<string, unknown>).decision as string)
            : null,
      },
      authorize: (ride) => {
        if (ride.passengerId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the customer may respond to a shopping quote.',
          );
        }
        this.assertV2Delivery(ride);
        return 'passenger';
      },
      apply: ({ ride, body, nowIso }) => {
        const decision =
          typeof body.decision === 'string'
            ? body.decision.trim().toUpperCase()
            : '';
        if (decision !== 'APPROVE' && decision !== 'REJECT') {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            'decision must be APPROVE or REJECT.',
          );
        }
        const stop = (ride.stops ?? []).find((s) => s.seq === input.seq);
        if (
          !stop ||
          stop.status !== 'WAITING_APPROVAL' ||
          !stop.quote
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'No pending quote on this stop.',
          );
        }
        const approved = decision === 'APPROVE';
        const stops = ride.stops!.map((s) =>
          s.seq === input.seq
            ? {
                ...s,
                status: 'ARRIVED' as StopStatus,
                quote: {
                  ...s.quote!,
                  approvedAt: approved ? nowIso : null,
                  rejectedAt: approved ? null : nowIso,
                },
              }
            : s,
        );
        // Approved-authorization total = spent + Σ approved-unpurchased quotes.
        const approvedTotal =
          (ride.shopping?.spentMinor ?? 0) +
          stops.reduce(
            (sum, s) =>
              sum +
              (s.quote?.approvedAt != null && !s.purchase
                ? s.quote.totalMinor
                : 0),
            0,
          );
        const patch: Record<string, unknown> = { stops };
        const rideOverrides: Partial<RideDoc> = { stops };
        if (ride.shopping) {
          patch['shopping.approvedTotalMinor'] = approvedTotal;
          rideOverrides.shopping = {
            ...ride.shopping,
            approvedTotalMinor: approvedTotal,
          };
        }
        return {
          patch,
          rideOverrides,
          eventPayload: {
            rideId: input.rideId,
            seq: input.seq,
            actorId: input.caller.uid,
            decision,
            quoteTotalMinor: stop.quote.totalMinor,
          },
        };
      },
    });
  }

  /** Ora Courier v2 — driver reports cash collection (never verified). */
  async reportSettlement(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.mutateDelivery({
      ...input,
      operation: 'SETTLEMENT_REPORT',
      eventType: 'delivery.settlement.reported',
      allowedKeys: new Set(['expectedVersion', 'status']),
      hashExtra: {
        status:
          typeof (input.body as Record<string, unknown> | null)?.status ===
          'string'
            ? ((input.body as Record<string, unknown>).status as string)
            : null,
      },
      authorize: (ride) => {
        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may report settlement.',
          );
        }
        this.assertV2Delivery(ride);
        return 'driver';
      },
      apply: ({ ride, body, nowIso }) => {
        const status =
          typeof body.status === 'string'
            ? body.status.trim().toUpperCase()
            : '';
        if (!(SETTLEMENT_REPORTS as readonly string[]).includes(status)) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            `status must be one of: ${SETTLEMENT_REPORTS.join(', ')}.`,
          );
        }
        if (
          !new Set<RideState>([
            'RIDE_COMPLETED',
            'RIDE_CLOSED',
            'RETURNED',
            'DELIVERY_FAILED',
          ]).has(ride.state) ||
          !ride.settlement
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Settlement can only be reported after the delivery concludes.',
          );
        }
        const settlement: SettlementDoc = {
          ...ride.settlement,
          driverReportedStatus: status as SettlementReport,
          driverReportedAt: nowIso,
          status: status === 'PAID' ? 'SETTLED' : 'PENDING',
        };
        return {
          patch: { settlement },
          rideOverrides: { settlement },
          eventPayload: {
            rideId: input.rideId,
            actorId: input.caller.uid,
            reportedStatus: status,
            totalDueMinor: settlement.totalDueMinor,
          },
        };
      },
    });
  }

  /** Ora Courier v2 — customer acknowledges receipt (optional, evidence). */
  async acknowledgeDelivery(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    return this.mutateDelivery({
      ...input,
      operation: 'DELIVERY_ACK',
      eventType: 'delivery.acknowledged',
      allowedKeys: new Set(['expectedVersion']),
      authorize: (ride) => {
        if (ride.passengerId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the customer may acknowledge receipt.',
          );
        }
        this.assertV2Delivery(ride);
        return 'passenger';
      },
      apply: ({ ride, nowIso }) => {
        if (
          !new Set<RideState>([
            'RIDE_COMPLETED',
            'RIDE_CLOSED',
            'DELIVERY_FAILED',
            'RETURNED',
          ]).has(ride.state)
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Receipt can only be acknowledged once the delivery concludes.',
          );
        }
        const evidence = {
          confirms: ride.evidence?.confirms ?? [],
          customerAckAt: ride.evidence?.customerAckAt ?? nowIso,
        };
        const settlement: SettlementDoc | undefined = ride.settlement
          ? { ...ride.settlement, customerAckAt: nowIso }
          : undefined;
        return {
          patch: {
            'evidence.customerAckAt': evidence.customerAckAt,
            ...(settlement ? { 'settlement.customerAckAt': nowIso } : {}),
          },
          rideOverrides: {
            evidence,
            ...(settlement ? { settlement } : {}),
          },
          eventPayload: {
            rideId: input.rideId,
            actorId: input.caller.uid,
          },
        };
      },
    });
  }

  /** Ora Courier v2 — either party opens a dispute within the window. */
  async createDispute(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const cfg = await loadDeliveryConfig(this.db);
    const disputeId = randomUUID();
    const windowMs = cfg.disputeWindowHours * 60 * 60 * 1000;

    const result = await this.mutateDelivery({
      ...input,
      operation: 'DISPUTE_OPEN',
      eventType: 'delivery.dispute.opened',
      allowedKeys: new Set(['expectedVersion', 'category', 'message']),
      hashExtra: { disputeId },
      authorize: (ride) => {
        const isPassenger = ride.passengerId === input.caller.uid;
        const isDriver = ride.assignedDriverId === input.caller.uid;
        if (!isPassenger && !isDriver) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the customer or assigned driver may dispute this booking.',
          );
        }
        this.assertV2Delivery(ride);
        return isPassenger ? 'passenger' : 'driver';
      },
      apply: ({ ride, body, now, nowIso }) => {
        const category =
          typeof body.category === 'string'
            ? body.category.trim().toUpperCase()
            : '';
        if (!(DISPUTE_CATEGORIES as readonly string[]).includes(category)) {
          throw new RideDomainError(
            'VALIDATION_ERROR',
            400,
            `category must be one of: ${DISPUTE_CATEGORIES.join(', ')}.`,
          );
        }
        const message = parcelString(body.message, 'message', {
          min: 1,
          max: 1000,
          required: true,
        })!;
        const concludedAt =
          ride.completedAt ?? ride.returnedAt ?? ride.deliveryFailedAt;
        if (!concludedAt) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Disputes open only after the delivery concludes.',
          );
        }
        if (now.getTime() - Date.parse(concludedAt) > windowMs) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'The dispute window has closed.',
          );
        }
        if (ride.disputeStatus === 'OPEN') {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'A dispute is already open for this booking.',
          );
        }
        // Created inside the same mutation window via the returned patch —
        // the dispute doc itself is written by the wrapping txn below.
        const patch: Record<string, unknown> = {
          disputeStatus: 'OPEN',
          disputeId,
        };
        if (ride.settlement) {
          patch['settlement.status'] = 'DISPUTED';
        }
        const settlement = ride.settlement
          ? { ...ride.settlement, status: 'DISPUTED' as const }
          : undefined;
        return {
          patch,
          rideOverrides: {
            disputeStatus: 'OPEN',
            disputeId,
            ...(settlement ? { settlement } : {}),
          },
          eventPayload: {
            rideId: input.rideId,
            disputeId,
            actorId: input.caller.uid,
            category,
            // message intentionally excluded from the event payload.
          },
          extraWrite: {
            collection: DISPUTES_COLLECTION,
            docId: disputeId,
            data: {
              disputeId,
              rideId: input.rideId,
              reporterUid: input.caller.uid,
              reporterRole:
                ride.passengerId === input.caller.uid
                  ? 'passenger'
                  : 'driver',
              category: category as DisputeCategory,
              message,
              status: 'OPEN',
              createdAt: nowIso,
              resolvedAt: null,
              resolution: null,
            } satisfies DisputeDoc,
          },
        };
      },
    });
    return result;
  }

  async closeRide(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(
      input.body ?? {},
      new Set(['expectedVersion']),
    );
    const requestHash = hashRequest({
      rideId: input.rideId,
      operation: 'RIDE_CLOSE',
      expectedVersion: body.expectedVersion ?? null,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const expectedVersion =
      body.expectedVersion == null ? null : Number(body.expectedVersion);
    if (
      expectedVersion != null &&
      (!Number.isInteger(expectedVersion) || expectedVersion < 1)
    ) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'expectedVersion must be a positive integer.',
      );
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideSnap = await tx.get(rideRef);
        if (!rideSnap.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideSnap.data() as RideDoc;

        const isPassenger = ride.passengerId === input.caller.uid;
        const isAssignedDriver = ride.assignedDriverId === input.caller.uid;
        if (!isPassenger && !isAssignedDriver) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the passenger or assigned driver may close this ride.',
          );
        }

        // Already CLOSED: deterministic success snapshot, no second mutation/event.
        if (ride.state === 'RIDE_CLOSED') {
          responseBody = {
            data: publicRide(ride, isAssignedDriver ? 'driver' : 'passenger'),
          };
          tx.set(idemRef, {
            idempotencyKey,
            requestHash,
            actorId: input.caller.uid,
            operation: 'RIDE_CLOSE',
            resourceId: input.rideId,
            status: 'SUCCEEDED',
            responseSnapshot: { httpStatus: 200, body: responseBody },
            createdAt: nowIso,
            expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
          });
          return;
        }

        assertCloseable(ride.state);

        if (expectedVersion != null && ride.version !== expectedVersion) {
          throw new RideDomainError(
            'VERSION_CONFLICT',
            409,
            'Ride version does not match expectedVersion.',
          );
        }

        const nextVersion = ride.version + 1;
        tx.update(rideRef, {
          state: 'RIDE_CLOSED',
          version: nextVersion,
          closedAt: nowIso,
          updatedAt: nowIso,
        });

        const updated: RideDoc = {
          ...ride,
          state: 'RIDE_CLOSED',
          version: nextVersion,
          closedAt: nowIso,
          updatedAt: nowIso,
        };
        responseBody = {
          data: publicRide(updated, isAssignedDriver ? 'driver' : 'passenger'),
        };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_CLOSE',
          resourceId: input.rideId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 200, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        const actorType = isPassenger ? 'passenger' : 'driver';
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.closed',
          aggregateType: 'ride',
          aggregateId: input.rideId,
          aggregateVersion: nextVersion,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            rideId: input.rideId,
            fromState: 'RIDE_COMPLETED',
            toState: 'RIDE_CLOSED',
            actorId: input.caller.uid,
            actorType,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    const closedRide =
      responseBody &&
      typeof responseBody === 'object' &&
      'data' in responseBody
        ? (responseBody as { data: { assignedDriverId?: string | null } }).data
        : null;
    await this.afterRideTerminal({
      rideId: input.rideId,
      assignedDriverId: closedRide?.assignedDriverId ?? null,
      requestId: input.correlationId,
      reason: 'RIDE_CLOSED',
    });

    return { httpStatus: 200, body: responseBody };
  }

  /**
   * Phase 2J/2K — transactional ride expiry for a single ride.
   * Idempotent: already EXPIRED returns without a second version bump or ride.expired event.
   * Phase 2K: bounded PENDING offer cleanup + ride.offer.expired (in-txn + post-commit multi-pass).
   */
  async expireRide(input: {
    rideId: string;
    correlationId: string;
  }): Promise<ExpireRideResult> {
    const now = new Date();
    const nowIso = now.toISOString();
    const nowMs = now.getTime();

    const result = await this.db.runTransaction(async (tx) => {
      const rideRef = this.db.collection(RIDES).doc(input.rideId);
      const rideSnap = await tx.get(rideRef);
      if (!rideSnap.exists) {
        throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
      }
      const ride = rideSnap.data() as RideDoc;

      if (ride.state === 'EXPIRED') {
        return {
          outcome: 'already_expired' as const,
          rideId: input.rideId,
          offersExpired: 0,
        };
      }

      if (!isExpirable(ride.state)) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          reason: `state_${ride.state}`,
        };
      }

      const expiresAtMs = Date.parse(ride.expiresAt);
      if (!Number.isFinite(expiresAtMs) || expiresAtMs > nowMs) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          reason: 'not_due',
        };
      }

      // Reads before writes (Firestore txn rule).
      const pendingQuery = await tx.get(
        this.db
          .collection(OFFERS)
          .where('rideId', '==', input.rideId)
          .where('status', '==', 'PENDING')
          .limit(MAX_OFFERS_SUPERSEDE_IN_TXN),
      );

      assertExpirable(ride.state);

      const fromState = ride.state;
      const nextVersion = ride.version + 1;
      tx.update(rideRef, {
        state: 'EXPIRED',
        version: nextVersion,
        updatedAt: nowIso,
      });

      const eventId = randomUUID();
      tx.set(this.db.collection(OUTBOX).doc(eventId), {
        eventId,
        eventType: 'ride.expired',
        aggregateType: 'ride',
        aggregateId: input.rideId,
        aggregateVersion: nextVersion,
        schemaVersion: 1,
        occurredAt: nowIso,
        correlationId: input.correlationId,
        causationId: `expire:${input.rideId}`,
        payload: {
          rideId: input.rideId,
          fromState,
          toState: 'EXPIRED',
          reason: 'search_ttl_elapsed',
          expiresAt: ride.expiresAt,
        },
        publishState: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: nowIso,
      });

      let offersExpired = 0;
      for (const doc of pendingQuery.docs) {
        const offer = doc.data() as RideOfferDoc;
        tx.update(doc.ref, { status: 'EXPIRED' });
        this.writeOfferExpiredOutbox(tx, {
          rideId: input.rideId,
          rideVersion: nextVersion,
          offer,
          offerId: offer.offerId ?? doc.id,
          reason: 'parent_ride_expired',
          correlationId: input.correlationId,
          causationId: `expire:${input.rideId}`,
          nowIso,
        });
        offersExpired += 1;
      }

      return {
        outcome: 'expired' as const,
        rideId: input.rideId,
        fromState,
        version: nextVersion,
        offersExpired,
      };
    });

    if (result.outcome === 'expired' || result.outcome === 'already_expired') {
      const extra = await this.cleanupPendingOffersForExpiredRide({
        rideId: input.rideId,
        correlationId: input.correlationId,
      });
      if (result.outcome === 'expired') {
        return { ...result, offersExpired: result.offersExpired + extra };
      }
      return { ...result, offersExpired: result.offersExpired + extra };
    }

    return result;
  }

  /**
   * Phase 2J — bounded sweeper over due pre-assignment rides.
   */
  async sweepExpiredRides(input: {
    correlationId: string;
    limit?: number;
  }): Promise<SweepExpiredRidesResult> {
    const limit = Math.min(
      Math.max(input.limit ?? DEFAULT_SWEEP_BATCH, 1),
      MAX_SWEEP_BATCH,
    );
    const nowIso = new Date().toISOString();

    const snap = await this.db
      .collection(RIDES)
      .where('state', 'in', [...EXPIRABLE_STATES])
      .where('expiresAt', '<=', nowIso)
      .limit(limit)
      .get();

    const result: SweepExpiredRidesResult = {
      scanned: snap.docs.length,
      expired: 0,
      alreadyExpired: 0,
      skipped: 0,
      failed: 0,
    };

    for (const doc of snap.docs) {
      try {
        const outcome = await this.expireRide({
          rideId: doc.id,
          correlationId: input.correlationId,
        });
        if (outcome.outcome === 'expired') result.expired += 1;
        else if (outcome.outcome === 'already_expired') result.alreadyExpired += 1;
        else result.skipped += 1;
      } catch {
        result.failed += 1;
      }
    }

    return result;
  }

  /**
   * Phase 2K — single-offer durable expiry (state-idempotent; no ride.version bump).
   *
   * - offer_ttl_elapsed: PENDING + expiresAt <= now
   * - parent_ride_expired: PENDING + parent ride state === EXPIRED (TTL not required)
   */
  async expireOffer(input: {
    offerId: string;
    correlationId: string;
    reason: 'offer_ttl_elapsed' | 'parent_ride_expired';
  }): Promise<ExpireOfferResult> {
    const now = new Date();
    const nowIso = now.toISOString();
    const nowMs = now.getTime();

    return this.db.runTransaction(async (tx) => {
      const offerRef = this.db.collection(OFFERS).doc(input.offerId);
      const offerSnap = await tx.get(offerRef);
      if (!offerSnap.exists) {
        throw new RideDomainError('OFFER_NOT_FOUND', 404, 'Offer not found.');
      }
      const offer = offerSnap.data() as RideOfferDoc;
      const rideId = offer.rideId;

      if (offer.status === 'EXPIRED') {
        return {
          outcome: 'already_expired' as const,
          offerId: input.offerId,
          rideId,
        };
      }

      if (offer.status !== 'PENDING') {
        return {
          outcome: 'skipped' as const,
          offerId: input.offerId,
          reason: `status_${offer.status}`,
        };
      }

      const rideRef = this.db.collection(RIDES).doc(rideId);
      const rideSnap = await tx.get(rideRef);
      if (!rideSnap.exists) {
        return {
          outcome: 'skipped' as const,
          offerId: input.offerId,
          reason: 'ride_missing',
        };
      }
      const ride = rideSnap.data() as RideDoc;

      if (input.reason === 'offer_ttl_elapsed') {
        const expiresAtMs = Date.parse(offer.expiresAt);
        if (!Number.isFinite(expiresAtMs) || expiresAtMs > nowMs) {
          return {
            outcome: 'skipped' as const,
            offerId: input.offerId,
            reason: 'not_due',
          };
        }
      } else {
        // parent_ride_expired: never expire merely because the parent ride exists.
        if (ride.state !== 'EXPIRED') {
          return {
            outcome: 'skipped' as const,
            offerId: input.offerId,
            reason: `parent_${ride.state}`,
          };
        }
      }

      tx.update(offerRef, { status: 'EXPIRED' });
      this.writeOfferExpiredOutbox(tx, {
        rideId,
        rideVersion: ride.version,
        offer,
        offerId: offer.offerId ?? input.offerId,
        reason: input.reason,
        correlationId: input.correlationId,
        causationId: `expire-offer:${input.offerId}`,
        nowIso,
      });

      return {
        outcome: 'expired' as const,
        offerId: input.offerId,
        rideId,
        reason: input.reason,
      };
    });
  }

  /**
   * Phase 2K — bounded sweeper: PENDING offers with expiresAt <= now.
   */
  async sweepExpiredOffers(input: {
    correlationId: string;
    limit?: number;
  }): Promise<SweepExpiredOffersResult> {
    const limit = Math.min(
      Math.max(input.limit ?? DEFAULT_SWEEP_BATCH, 1),
      MAX_SWEEP_BATCH,
    );
    const nowIso = new Date().toISOString();

    const snap = await this.db
      .collection(OFFERS)
      .where('status', '==', 'PENDING')
      .where('expiresAt', '<=', nowIso)
      .limit(limit)
      .get();

    const result: SweepExpiredOffersResult = {
      scanned: snap.docs.length,
      expired: 0,
      alreadyExpired: 0,
      skipped: 0,
      failed: 0,
    };

    for (const doc of snap.docs) {
      try {
        const outcome = await this.expireOffer({
          offerId: doc.id,
          correlationId: input.correlationId,
          reason: 'offer_ttl_elapsed',
        });
        if (outcome.outcome === 'expired') result.expired += 1;
        else if (outcome.outcome === 'already_expired') result.alreadyExpired += 1;
        else result.skipped += 1;
      } catch {
        result.failed += 1;
      }
    }

    return result;
  }

  /**
   * Phase 2M — transactional NO_SHOW for a single ride (server/worker only).
   * Idempotent: already NO_SHOW returns without version bump or second event.
   * Skips: wrong state, missing arrivedAt, not yet due.
   * No payment / offer / noShowCount mutations.
   */
  async markNoShow(input: {
    rideId: string;
    correlationId: string;
  }): Promise<MarkNoShowResult> {
    const now = new Date();
    const nowIso = now.toISOString();
    const cutoffMs = now.getTime() - RIDE_NO_SHOW_WAIT_MS;

    const result = await this.db.runTransaction(async (tx) => {
      const rideRef = this.db.collection(RIDES).doc(input.rideId);
      const rideSnap = await tx.get(rideRef);
      if (!rideSnap.exists) {
        throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
      }
      const ride = rideSnap.data() as RideDoc;

      if (ride.state === 'NO_SHOW') {
        return {
          outcome: 'already_no_show' as const,
          rideId: input.rideId,
          assignedDriverId: ride.assignedDriverId,
        };
      }

      if (ride.state !== 'DRIVER_ARRIVED') {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          reason: `state_${ride.state}`,
        };
      }

      if (ride.arrivedAt == null) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          reason: 'missing_arrivedAt',
        };
      }

      const arrivedAtMs = Date.parse(ride.arrivedAt);
      if (!Number.isFinite(arrivedAtMs) || arrivedAtMs > cutoffMs) {
        return {
          outcome: 'skipped' as const,
          rideId: input.rideId,
          reason: 'not_due',
        };
      }

      const nextVersion = ride.version + 1;
      tx.update(rideRef, {
        state: 'NO_SHOW',
        version: nextVersion,
        updatedAt: nowIso,
      });

      const eventId = randomUUID();
      tx.set(this.db.collection(OUTBOX).doc(eventId), {
        eventId,
        eventType: 'ride.no_show',
        aggregateType: 'ride',
        aggregateId: input.rideId,
        aggregateVersion: nextVersion,
        schemaVersion: 1,
        occurredAt: nowIso,
        correlationId: input.correlationId,
        causationId: `no-show:${input.rideId}`,
        payload: {
          rideId: input.rideId,
          fromState: 'DRIVER_ARRIVED',
          toState: 'NO_SHOW',
          reason: 'arrived_wait_ttl_elapsed',
          arrivedAt: ride.arrivedAt,
        },
        publishState: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: nowIso,
      });

      return {
        outcome: 'no_show' as const,
        rideId: input.rideId,
        fromState: 'DRIVER_ARRIVED' as RideState,
        version: nextVersion,
        assignedDriverId: ride.assignedDriverId,
      };
    });

    if (result.outcome === 'no_show' || result.outcome === 'already_no_show') {
      const assignedDriverId =
        'assignedDriverId' in result ? result.assignedDriverId : null;
      await this.afterRideTerminal({
        rideId: input.rideId,
        assignedDriverId: assignedDriverId ?? null,
        requestId: input.correlationId,
        reason: 'NO_SHOW',
      });
    }

    return result;
  }

  /**
   * Phase 2M — bounded sweeper over due DRIVER_ARRIVED rides.
   * Multi-pass within one call while a full batch is returned (max 20 passes).
   */
  async sweepNoShowRides(input: {
    correlationId: string;
    limit?: number;
  }): Promise<SweepNoShowRidesResult> {
    const limit = Math.min(
      Math.max(input.limit ?? DEFAULT_SWEEP_BATCH, 1),
      MAX_SWEEP_BATCH,
    );
    const result: SweepNoShowRidesResult = {
      scanned: 0,
      noShowed: 0,
      alreadyNoShow: 0,
      skipped: 0,
      failed: 0,
      passes: 0,
    };

    for (let pass = 0; pass < MAX_NO_SHOW_SWEEP_PASSES; pass++) {
      const cutoffIso = new Date(
        Date.now() - RIDE_NO_SHOW_WAIT_MS,
      ).toISOString();

      const snap = await this.db
        .collection(RIDES)
        .where('state', '==', 'DRIVER_ARRIVED')
        .where('arrivedAt', '<=', cutoffIso)
        .limit(limit)
        .get();

      result.passes += 1;
      result.scanned += snap.docs.length;

      for (const doc of snap.docs) {
        try {
          const outcome = await this.markNoShow({
            rideId: doc.id,
            correlationId: input.correlationId,
          });
          if (outcome.outcome === 'no_show') result.noShowed += 1;
          else if (outcome.outcome === 'already_no_show')
            result.alreadyNoShow += 1;
          else result.skipped += 1;
        } catch {
          result.failed += 1;
        }
      }

      if (snap.docs.length < limit) break;
    }

    return result;
  }

  /**
   * Multi-pass cleanup of PENDING offers under an already-EXPIRED ride (bounded per txn).
   * Does not bump ride.version.
   */
  async cleanupPendingOffersForExpiredRide(input: {
    rideId: string;
    correlationId: string;
  }): Promise<number> {
    let expired = 0;
    for (let pass = 0; pass < MAX_PARENT_OFFER_CLEANUP_PASSES; pass += 1) {
      const snap = await this.db
        .collection(OFFERS)
        .where('rideId', '==', input.rideId)
        .where('status', '==', 'PENDING')
        .limit(MAX_OFFERS_SUPERSEDE_IN_TXN)
        .get();
      if (snap.empty) break;

      let progressed = false;
      for (const doc of snap.docs) {
        const outcome = await this.expireOffer({
          offerId: doc.id,
          correlationId: input.correlationId,
          reason: 'parent_ride_expired',
        });
        if (outcome.outcome === 'expired') {
          expired += 1;
          progressed = true;
        } else if (outcome.outcome === 'already_expired') {
          progressed = true;
        }
      }
      if (!progressed) break;
    }
    return expired;
  }

  private writeOfferExpiredOutbox(
    tx: Transaction,
    input: {
      rideId: string;
      rideVersion: number;
      offer: RideOfferDoc;
      offerId: string;
      reason: OfferExpireReason;
      correlationId: string;
      causationId: string;
      nowIso: string;
    },
  ): void {
    const eventId = randomUUID();
    tx.set(this.db.collection(OUTBOX).doc(eventId), {
      eventId,
      eventType: 'ride.offer.expired',
      aggregateType: 'ride',
      aggregateId: input.rideId,
      aggregateVersion: input.rideVersion,
      schemaVersion: 1,
      occurredAt: input.nowIso,
      correlationId: input.correlationId,
      causationId: input.causationId,
      payload: {
        rideId: input.rideId,
        offerId: input.offerId,
        driverId: input.offer.driverId,
        reason: input.reason,
        expiresAt: input.offer.expiresAt,
      },
      publishState: 'PENDING',
      attemptCount: 0,
      nextAttemptAt: input.nowIso,
    });
  }

  /**
   * Phase 2N — submit immutable stars-only rating (independent aggregate).
   * Ride document is read-only: no state/version/updatedAt/denorm mutation.
   * Outbox aggregate: type `rating`, id = ratingDocId, version = 1 (immutable create).
   */
  async submitRating(input: {
    caller: AuthenticatedCaller;
    rideId: string;
    body: unknown;
    idempotencyKeyHeader: string | undefined;
    correlationId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(input.body ?? {}, new Set(['stars']));
    if (!Object.prototype.hasOwnProperty.call(body, 'stars')) {
      throw new RideDomainError(
        'VALIDATION_ERROR',
        400,
        'stars is required.',
      );
    }
    const stars = parseStars(body.stars);

    const rideSnap = await this.db.collection(RIDES).doc(input.rideId).get();
    if (!rideSnap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ridePreview = rideSnap.data() as RideDoc;
    const direction = deriveRatingDirection(ridePreview, input.caller.uid);
    assertRatingEligible(ridePreview.state);

    const ratingId = ratingDocId(input.rideId, direction.ratingType);
    const requestHash = hashRequest({
      operation: 'RIDE_RATING_SUBMIT',
      rideId: input.rideId,
      ratingType: direction.ratingType,
      stars,
    });
    const replay = await readIdempotencyReplay(
      this.db,
      idempotencyKey,
      requestHash,
      input.caller.uid,
    );
    if (replay) {
      return { httpStatus: replay.httpStatus, body: replay.body };
    }

    const now = new Date();
    const nowIso = now.toISOString();
    let responseBody: unknown;

    try {
      await this.db.runTransaction(async (tx) => {
        const idemRef = this.db.collection(IDEM).doc(idempotencyKey);
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const replayInTxn = assertIdempotencyRecord(
            idemSnap.data() as {
              requestHash: string;
              actorId?: string;
              responseSnapshot?: { httpStatus: number; body: unknown };
            },
            requestHash,
            input.caller.uid,
          );
          if (replayInTxn) throw replayInTxn;
        }

        const rideRef = this.db.collection(RIDES).doc(input.rideId);
        const rideInTxn = await tx.get(rideRef);
        if (!rideInTxn.exists) {
          throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
        }
        const ride = rideInTxn.data() as RideDoc;
        assertRatingEligible(ride.state);
        const derived = deriveRatingDirection(ride, input.caller.uid);
        if (
          derived.ratingType !== direction.ratingType ||
          derived.ratedId !== direction.ratedId
        ) {
          throw new RideDomainError(
            'STATE_CONFLICT',
            409,
            'Ride participants changed; retry rating.',
          );
        }

        const ratingRef = this.db.collection(RATINGS).doc(ratingId);
        const ratingSnap = await tx.get(ratingRef);
        if (ratingSnap.exists) {
          throw new RideDomainError(
            'ALREADY_RATED',
            409,
            'A rating for this ride and direction already exists.',
          );
        }

        const rating: RatingDoc = {
          rideId: input.rideId,
          raterId: input.caller.uid,
          ratedId: derived.ratedId,
          ratingType: derived.ratingType,
          stars,
          createdAt: nowIso,
        };
        // Ride is intentionally not updated (D6/D8).
        tx.set(ratingRef, rating);

        responseBody = { data: publicRating(ratingId, rating) };

        tx.set(idemRef, {
          idempotencyKey,
          requestHash,
          actorId: input.caller.uid,
          operation: 'RIDE_RATING_SUBMIT',
          resourceId: ratingId,
          status: 'SUCCEEDED',
          responseSnapshot: { httpStatus: 201, body: responseBody },
          createdAt: nowIso,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MS).toISOString(),
        });

        const eventId = randomUUID();
        tx.set(this.db.collection(OUTBOX).doc(eventId), {
          eventId,
          eventType: 'ride.rating.submitted',
          // Rating is its own immutable aggregate — do not bump ride.version.
          aggregateType: 'rating',
          aggregateId: ratingId,
          aggregateVersion: 1,
          schemaVersion: 1,
          occurredAt: nowIso,
          correlationId: input.correlationId,
          causationId: idempotencyKey,
          payload: {
            rideId: input.rideId,
            ratingId,
            ratingType: derived.ratingType,
            raterId: input.caller.uid,
            ratedId: derived.ratedId,
            stars,
          },
          publishState: 'PENDING',
          attemptCount: 0,
          nextAttemptAt: nowIso,
        });
      });
    } catch (err) {
      if (err instanceof IdempotencyReplay) {
        return { httpStatus: err.httpStatus, body: err.body };
      }
      throw err;
    }

    return { httpStatus: 201, body: responseBody };
  }

  /**
   * Phase 2N — return only the caller's own rating for the ride (participant-scoped).
   */
  async getMyRating(input: {
    caller: AuthenticatedCaller;
    rideId: string;
  }): Promise<{ httpStatus: number; body: unknown }> {
    const rideSnap = await this.db.collection(RIDES).doc(input.rideId).get();
    if (!rideSnap.exists) {
      throw new RideDomainError('RIDE_NOT_FOUND', 404, 'Ride not found.');
    }
    const ride = rideSnap.data() as RideDoc;
    const direction = deriveRatingDirection(ride, input.caller.uid);
    const ratingId = ratingDocId(input.rideId, direction.ratingType);
    const ratingSnap = await this.db.collection(RATINGS).doc(ratingId).get();
    if (!ratingSnap.exists) {
      throw new RideDomainError(
        'RATING_NOT_FOUND',
        404,
        'No rating found for this ride.',
      );
    }
    const rating = ratingSnap.data() as RatingDoc;
    if (rating.raterId !== input.caller.uid || rating.rideId !== input.rideId) {
      throw new RideDomainError(
        'FORBIDDEN',
        403,
        'Not allowed to read this rating.',
      );
    }
    return {
      httpStatus: 200,
      body: { data: publicRating(ratingId, rating) },
    };
  }
}
