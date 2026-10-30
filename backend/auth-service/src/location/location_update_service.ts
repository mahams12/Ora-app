import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { loadActor } from '../rides/eligibility';
import { RideDomainError } from '../rides/types';
import type { RedisGeoProjectionService } from '../redis/geo_projection';
import type { TripLocationRtdb } from '../rtdb/types';
import { NullTripLocationRtdb } from '../rtdb/admin_trip_location_rtdb';
import { projectAcceptedTripLocationLatest } from '../rtdb/ride_location_lifecycle';
import { parseAndValidateLocationBody } from './validation';
import {
  FirestoreLocationStreamStore,
  type LocationStreamStore,
} from './stream_store';
import {
  LocationDomainError,
  type LocationMode,
  type LocationUpdateSnapshot,
} from './types';

const DRIVERS = 'drivers';
const RIDES = 'rides';

/**
 * Ride states that allow trip-mode live location publishing (L2 Step 1).
 * Matches L1 `driverLocationShouldWatch` and N3 busy states.
 */
export const LOCATION_PUBLISH_RIDE_STATES = [
  'DRIVER_ASSIGNED',
  'DRIVER_EN_ROUTE',
  'DRIVER_ARRIVED',
  'RIDE_STARTED',
] as const;

export type LocationPublishRideState =
  (typeof LOCATION_PUBLISH_RIDE_STATES)[number];

/** Idle stream registry doc id. */
export function idleStreamDocId(driverId: string): string {
  return driverId;
}

/** Trip stream registry doc id (Phase 1.6). */
export function tripStreamDocId(rideId: string, driverId: string): string {
  return `${rideId}_${driverId}`;
}

/** Peek non-empty rideId without full GPS validation (auth gate only). */
export function peekRideIdFromBody(body: unknown): string | null {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const rideId = (body as Record<string, unknown>).rideId;
  if (rideId == null || rideId === '') return null;
  if (typeof rideId !== 'string') return null;
  const trimmed = rideId.trim();
  return trimmed === '' ? null : trimmed;
}

export const DEFAULT_ELIGIBILITY_CACHE_TTL_MS = 15_000;

/**
 * Bounded TTL cache for the users+drivers eligibility snapshot that is
 * otherwise re-read on every GPS packet (2 of the ~4 per-packet reads).
 *
 * Staleness is bounded and safe: matching eligibility is re-checked
 * authoritatively against drivers/{id} at match time, so a just-banned or
 * just-offline driver can only write geo markers for up to ttlMs — never
 * become incorrectly matchable. Availability transitions in the same
 * process invalidate the entry immediately via `invalidate`. Only
 * successful eligibility loads are cached — failures re-evaluate every
 * call (fail-closed).
 *
 * Shared across routers by app composition so the availability service can
 * invalidate entries on go-online/go-offline transitions.
 */
export class DriverEligibilityCache {
  private readonly entries = new Map<
    string,
    { driverData: Record<string, unknown> | null; expiresAtMs: number }
  >();
  private hits = 0;
  private misses = 0;

  constructor(
    private readonly ttlMs: number = DEFAULT_ELIGIBILITY_CACHE_TTL_MS,
    private readonly now: () => number = Date.now,
  ) {}

  /** Returns the cached driver data on a fresh hit, undefined otherwise. */
  get(driverId: string): Record<string, unknown> | null | undefined {
    const entry = this.entries.get(driverId);
    if (entry && entry.expiresAtMs > this.now()) {
      this.hits += 1;
      return entry.driverData;
    }
    this.misses += 1;
    return undefined;
  }

  set(driverId: string, driverData: Record<string, unknown> | null): void {
    if (this.ttlMs <= 0) return;
    this.entries.set(driverId, {
      driverData,
      expiresAtMs: this.now() + this.ttlMs,
    });
  }

  invalidate(driverId: string): void {
    this.entries.delete(driverId);
  }

  stats(): { hits: number; misses: number; size: number } {
    return { hits: this.hits, misses: this.misses, size: this.entries.size };
  }
}

export interface LocationUpdateServiceOptions {
  /**
   * Shared eligibility cache — inject the app-composed instance so the
   * availability service can invalidate it on status transitions.
   * Defaults to a fresh 15s-TTL cache when not provided.
   */
  eligibilityCache?: DriverEligibilityCache;
  /**
   * Cursor store override (LOCATION_STREAMS_BACKEND). Defaults to the
   * Firestore-backed store preserving the original transaction semantics.
   */
  streamStore?: LocationStreamStore;
}

/**
 * N2A — validate location update + durable locationStreams cursor.
 * L2 Step 1 — trip mode requires assigned driver + publishable ride state.
 * L2 Step 3 — after durable accept, best-effort RTDB tripLocations/{rideId}/latest.
 * N2C — optional Redis GEO projection after accept (non-authoritative).
 */
export class LocationUpdateService {
  private readonly tripLocationRtdb: TripLocationRtdb;
  private readonly eligibilityCache: DriverEligibilityCache;
  private readonly streamStore: LocationStreamStore;

  constructor(
    private readonly db: Firestore,
    private readonly geoProjection: RedisGeoProjectionService | null = null,
    tripLocationRtdb: TripLocationRtdb | null = null,
    options: LocationUpdateServiceOptions = {},
  ) {
    this.tripLocationRtdb = tripLocationRtdb ?? new NullTripLocationRtdb();
    this.eligibilityCache =
      options.eligibilityCache ?? new DriverEligibilityCache();
    this.streamStore =
      options.streamStore ?? new FirestoreLocationStreamStore(db);
  }

  async update(input: {
    caller: AuthenticatedCaller;
    body: unknown;
    requestId?: string;
    nowMs?: number;
  }): Promise<{ httpStatus: number; body: { data: LocationUpdateSnapshot } }> {
    const nowMs = input.nowMs ?? Date.now();
    // Identity is auth.uid only — never trust body.driverId.
    const driverId = input.caller.uid;

    const driverDoc = await this.assertApprovedOnlineDriver(driverId);

    // Trip authorization before GPS accept / locationStreams mutation.
    const rideIdForAuth = peekRideIdFromBody(input.body);
    if (rideIdForAuth != null) {
      await this.assertTripPublishAuthorization(rideIdForAuth, driverId);
    }

    const parsed = parseAndValidateLocationBody(
      input.body,
      nowMs,
      input.requestId,
    );

    // Defense in depth: parsed rideId must be the same id that was authorized.
    if (parsed.rideId != null) {
      if (rideIdForAuth == null || parsed.rideId !== rideIdForAuth) {
        throw new LocationDomainError(
          'RIDE_LOCATION_FORBIDDEN',
          403,
          'Driver is not authorized to publish location for this ride.',
        );
      }
    }

    const mode: LocationMode = parsed.rideId == null ? 'idle' : 'trip';
    const docId =
      mode === 'idle'
        ? idleStreamDocId(driverId)
        : tripStreamDocId(parsed.rideId!, driverId);

    const acceptedAt = new Date(nowMs).toISOString();
    const snapshot = await this.streamStore.accept({
      docId,
      driverId,
      mode,
      parsed,
      acceptedAt,
    });

    // L2 Step 3: RTDB projection ONLY after durable locationStreams accept.
    // Failure must not roll back accept or change HTTP success.
    if (mode === 'trip' && parsed.rideId != null) {
      await projectAcceptedTripLocationLatest({
        rtdb: this.tripLocationRtdb,
        rideId: parsed.rideId,
        latest: {
          lat: parsed.lat,
          lng: parsed.lng,
          accuracy: parsed.accuracy,
          heading: parsed.heading,
          speed: parsed.speed,
          ts: parsed.timestampMs,
          acceptedAt,
          driverId,
          locationSeq: parsed.locationSeq,
          locationStreamId: parsed.locationStreamId,
        },
        requestId: input.requestId,
      });
    }

    // N2C: best-effort Redis projection — never fail the accepted N2A update.
    if (this.geoProjection) {
      await this.geoProjection.projectAcceptedLocation({
        driverId,
        lat: parsed.lat,
        lng: parsed.lng,
        accuracy: parsed.accuracy,
        locationStreamId: parsed.locationStreamId,
        locationSeq: parsed.locationSeq,
        lastLocationTs: parsed.timestampMs,
        acceptedAt,
        homeCity: driverDoc?.homeCity,
        requestId: input.requestId,
      });
    }

    return { httpStatus: 200, body: { data: snapshot } };
  }

  private async assertApprovedOnlineDriver(
    uid: string,
  ): Promise<Record<string, unknown> | null> {
    const cached = this.eligibilityCache.get(uid);
    if (cached !== undefined) return cached;
    const driverData = await this.loadApprovedOnlineDriver(uid);
    this.eligibilityCache.set(uid, driverData);
    return driverData;
  }

  private async loadApprovedOnlineDriver(
    uid: string,
  ): Promise<Record<string, unknown> | null> {
    let actor;
    try {
      actor = await loadActor(this.db, uid);
    } catch (err) {
      if (err instanceof RideDomainError) {
        throw new LocationDomainError(err.code, err.httpStatus, err.message);
      }
      throw err;
    }
    if (actor.role !== 'driver' || actor.driverStatus !== 'approved') {
      throw new LocationDomainError(
        'DRIVER_NOT_APPROVED',
        403,
        'Driver must be approved to update location.',
      );
    }

    const driverSnap = await this.db.collection(DRIVERS).doc(uid).get();
    const data = driverSnap.exists ? (driverSnap.data() ?? {}) : null;
    const availabilityState =
      data && data.availabilityState === 'online' ? 'online' : 'offline';
    if (availabilityState !== 'online') {
      throw new LocationDomainError(
        'FORBIDDEN',
        403,
        'Driver must be online to update location.',
      );
    }
    return data;
  }

  /**
   * L2 Step 1 — prove caller may publish trip location for rideId.
   * Must run before any locationStreams trip cursor mutation.
   */
  private async assertTripPublishAuthorization(
    rideId: string,
    callerUid: string,
  ): Promise<void> {
    const rideSnap = await this.db.collection(RIDES).doc(rideId).get();
    if (!rideSnap.exists) {
      throw new LocationDomainError(
        'RIDE_LOCATION_FORBIDDEN',
        403,
        'Driver is not authorized to publish location for this ride.',
      );
    }
    const ride = rideSnap.data() ?? {};
    const assignedDriverId =
      typeof ride.assignedDriverId === 'string' ? ride.assignedDriverId : null;
    if (assignedDriverId == null || assignedDriverId !== callerUid) {
      throw new LocationDomainError(
        'RIDE_LOCATION_FORBIDDEN',
        403,
        'Driver is not authorized to publish location for this ride.',
      );
    }
    const state = typeof ride.state === 'string' ? ride.state : '';
    if (
      !(LOCATION_PUBLISH_RIDE_STATES as readonly string[]).includes(state)
    ) {
      throw new LocationDomainError(
        'RIDE_LOCATION_FORBIDDEN',
        403,
        'Driver is not authorized to publish location for this ride.',
      );
    }
  }

}
