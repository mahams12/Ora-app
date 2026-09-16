import { randomUUID } from 'node:crypto';
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
  isExpirable,
} from './state_machine';
import {
  assertOfferSelectableForAssignment,
  assertOfferWithdrawable,
  effectiveOfferStatus,
} from './offer_lifecycle';
import {
  IDEMPOTENCY_TTL_MS,
  IdempotencyReplay,
  MAX_OFFERS_SUPERSEDE_IN_TXN,
  RIDE_NO_SHOW_WAIT_MS,
  RIDE_OFFER_TTL_MS,
  RIDE_SEARCH_TTL_MS,
  RideDomainError,
  type LatLng,
  type OfferType,
  type PaymentMethod,
  type RatingDoc,
  type RatingType,
  type RideDoc,
  type RideOfferDoc,
  type RideState,
} from './types';
import {
  completedStates,
  decodeListCursor,
  encodeListCursor,
  ownerBinding,
  parseRideListQuery,
  type RideListQueryRole,
} from './list_query';
import {
  RIDE_LIST_CURSOR_VERSION,
  discoveryBinding,
  parseOpenDiscoveryQuery,
} from './open_discovery_query';

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
    }
  | { outcome: 'already_no_show'; rideId: string }
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
    distanceKm: ride.distanceKm,
    estimatedDurationMin: ride.estimatedDurationMin,
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

function publicRide(ride: RideDoc) {
  return {
    rideId: ride.rideId,
    passengerId: ride.passengerId,
    assignedDriverId: ride.assignedDriverId,
    state: ride.state,
    version: ride.version,
    requestVersion: ride.requestVersion,
    category: ride.category,
    serviceType: ride.serviceType,
    pickup: ride.pickup,
    destination: ride.destination,
    pricingSnapshotId: ride.pricingSnapshotId,
    recommendedFareMinor: ride.recommendedFareMinor,
    passengerOfferMinor: ride.passengerOfferMinor,
    agreedFareMinor: ride.agreedFareMinor,
    agreedOfferId: ride.agreedOfferId,
    agreedFareCurrency: ride.agreedFareCurrency,
    paymentMethod: ride.paymentMethod,
    passengerCount: ride.passengerCount,
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
  if (state !== 'RIDE_COMPLETED' && state !== 'RIDE_CLOSED') {
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
  constructor(private readonly db: Firestore) {}

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
        'category',
        'serviceType',
        'passengerOfferMinor',
        'pricingSnapshotId',
        'paymentMethod',
        'passengerCount',
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
      paymentMethod: paymentMethod as PaymentMethod,
      paymentIntentId: null,
      passengerCount,
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

    const responseBody = { data: publicRide(ride) };

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
      body: { data: publicRide(ride) },
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
    const queryRole: RideListQueryRole =
      actor.role === 'driver' && actor.driverStatus === 'approved'
        ? 'driver'
        : 'passenger';
    const ownerField =
      queryRole === 'driver' ? 'assignedDriverId' : 'passengerId';
    const uid = input.caller.uid;
    const binding = ownerBinding(uid, queryRole);

    const parsed = parseRideListQuery(input.query);
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
      (doc: any) => publicRide(doc.data() as RideDoc),
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
    const binding = discoveryBinding();
    const cursor = parsed.cursor
      ? decodeListCursor(parsed.cursor, binding)
      : null;

    const nowMs = Date.now();
    const fetchLimit = parsed.limit + 1;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let q: any = this.db
      .collection(RIDES)
      .where('assignedDriverId', '==', null)
      .where('state', 'in', [...EXPIRABLE_STATES])
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc');

    if (cursor) {
      q = q.startAfter(cursor.createdAt, cursor.rideId);
    }
    q = q.limit(fetchLimit);

    const snap = await q.get();
    const eligible: RideDoc[] = [];
    for (const doc of snap.docs) {
      const ride = doc.data() as RideDoc;
      if (!isOpenDiscoverable(ride, nowMs)) continue;
      eligible.push(ride);
      if (eligible.length >= parsed.limit + 1) break;
    }

    const page = eligible.slice(0, parsed.limit).map(publicOpenRide);
    const hasNextPage =
      eligible.length > parsed.limit || snap.docs.length === fetchLimit;

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

        const nextVersion = ride.version + 1;
        tx.update(rideRef, {
          state: 'DRIVER_ASSIGNED',
          assignedDriverId: offer.driverId,
          agreedOfferId: offer.offerId,
          agreedFareMinor: offer.amountMinor,
          agreedFareCurrency: offer.currency,
          feePolicySnapshot: {
            platformFeeType: 'NONE',
            currency: 'PKR',
            capturedAt: nowIso,
          },
          assignedAt: nowIso,
          version: nextVersion,
          updatedAt: nowIso,
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
          responseBody = { data: publicRide(ride) };
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
            ride.state === 'RIDE_STARTED');

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
          assertCancellablePostAssign(ride.state);
          cancelledBy = isPassenger ? 'passenger' : 'driver';
        } else {
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
        responseBody = { data: publicRide(updated) };

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
  }): Promise<{ httpStatus: number; body: unknown }> {
    const idempotencyKey = requireIdempotencyKey(input.idempotencyKeyHeader);
    const body = rejectUnknownKeys(
      input.body ?? {},
      new Set(['expectedVersion']),
    );
    const requestHash = hashRequest({
      rideId: input.rideId,
      operation: input.operation,
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

        if (ride.assignedDriverId !== input.caller.uid) {
          throw new RideDomainError(
            'FORBIDDEN',
            403,
            'Only the assigned driver may progress this ride.',
          );
        }

        // Idempotent success if already at target (same logical transition done).
        if (ride.state === input.toState) {
          responseBody = { data: publicRide(ride) };
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

        const nextVersion = ride.version + 1;
        const patch: Record<string, unknown> = {
          state: input.toState,
          version: nextVersion,
          updatedAt: nowIso,
        };
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
        };
        responseBody = { data: publicRide(updated) };

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

    return { httpStatus: 200, body: responseBody };
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
          responseBody = { data: publicRide(ride) };
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
        responseBody = { data: publicRide(updated) };

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

    return this.db.runTransaction(async (tx) => {
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
      };
    });
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
