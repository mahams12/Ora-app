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
  LocationDomainError,
  type LocationMode,
  type LocationUpdateSnapshot,
  type ParsedLocationUpdate,
} from './types';

const DRIVERS = 'drivers';
const RIDES = 'rides';
const LOCATION_STREAMS = 'locationStreams';

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

/**
 * N2A — validate location update + durable locationStreams cursor.
 * L2 Step 1 — trip mode requires assigned driver + publishable ride state.
 * L2 Step 3 — after durable accept, best-effort RTDB tripLocations/{rideId}/latest.
 * N2C — optional Redis GEO projection after accept (non-authoritative).
 */
export class LocationUpdateService {
  private readonly tripLocationRtdb: TripLocationRtdb;

  constructor(
    private readonly db: Firestore,
    private readonly geoProjection: RedisGeoProjectionService | null = null,
    tripLocationRtdb: TripLocationRtdb | null = null,
  ) {
    this.tripLocationRtdb = tripLocationRtdb ?? new NullTripLocationRtdb();
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
    const snapshot = await this.acceptInTransaction({
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

  private async acceptInTransaction(input: {
    docId: string;
    driverId: string;
    mode: LocationMode;
    parsed: ParsedLocationUpdate;
    acceptedAt: string;
  }): Promise<LocationUpdateSnapshot> {
    const { docId, driverId, mode, parsed, acceptedAt } = input;

    return this.db.runTransaction(async (tx) => {
      const ref = this.db.collection(LOCATION_STREAMS).doc(docId);
      const snap = await tx.get(ref);
      const existing = snap.exists ? (snap.data() ?? {}) : null;

      if (existing) {
        const activeStreamId =
          typeof existing.activeStreamId === 'string'
            ? existing.activeStreamId
            : '';
        const lastAcceptedSeq =
          typeof existing.lastAcceptedSeq === 'number'
            ? existing.lastAcceptedSeq
            : -1;
        const streamState =
          typeof existing.streamState === 'string'
            ? existing.streamState
            : 'ACTIVE';

        if (streamState === 'CLOSED') {
          throw new LocationDomainError(
            'SEQUENCE_VIOLATION',
            422,
            'Location stream is closed.',
          );
        }

        if (activeStreamId === parsed.locationStreamId) {
          if (parsed.locationSeq <= lastAcceptedSeq) {
            throw new LocationDomainError(
              'SEQUENCE_VIOLATION',
              422,
              'locationSeq must be greater than last accepted sequence.',
            );
          }
          tx.update(ref, {
            lastAcceptedSeq: parsed.locationSeq,
            streamState: 'ACTIVE',
            updatedAt: acceptedAt,
            expiresAt: this.computeExpiresAt(mode, acceptedAt),
          });
        } else {
          const previous =
            Array.isArray(existing.previousStreamIds) &&
            existing.previousStreamIds.every((x) => typeof x === 'string')
              ? ([...existing.previousStreamIds] as string[])
              : [];

          // Late packets from a replaced stream must never overwrite the active stream.
          if (previous.includes(parsed.locationStreamId)) {
            throw new LocationDomainError(
              'SEQUENCE_VIOLATION',
              422,
              'Location stream is no longer active.',
            );
          }

          // New stream replaces active; sequence does not carry over.
          if (activeStreamId) previous.push(activeStreamId);
          tx.update(ref, {
            activeStreamId: parsed.locationStreamId,
            lastAcceptedSeq: parsed.locationSeq,
            streamState: 'ACTIVE',
            previousStreamIds: previous.slice(-5),
            updatedAt: acceptedAt,
            expiresAt: this.computeExpiresAt(mode, acceptedAt),
            ...(mode === 'trip' && parsed.rideId
              ? { rideId: parsed.rideId }
              : {}),
          });
        }
      } else {
        const created: Record<string, unknown> = {
          driverId,
          activeStreamId: parsed.locationStreamId,
          lastAcceptedSeq: parsed.locationSeq,
          streamState: 'ACTIVE',
          previousStreamIds: [],
          createdAt: acceptedAt,
          updatedAt: acceptedAt,
          expiresAt: this.computeExpiresAt(mode, acceptedAt),
        };
        if (mode === 'trip' && parsed.rideId) {
          created.rideId = parsed.rideId;
        }
        tx.set(ref, created);
      }

      return {
        driverId,
        mode,
        rideId: parsed.rideId,
        locationStreamId: parsed.locationStreamId,
        locationSeq: parsed.locationSeq,
        acceptedAt,
      };
    });
  }

  private computeExpiresAt(mode: LocationMode, acceptedAtIso: string): string {
    const t = Date.parse(acceptedAtIso);
    // Idle: refresh sliding 24h. Trip: long enough until terminal cleanup (N2B+).
    const ms = mode === 'idle' ? 24 * 60 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
    return new Date(t + ms).toISOString();
  }
}
