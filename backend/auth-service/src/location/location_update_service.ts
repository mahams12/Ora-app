import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { loadActor } from '../rides/eligibility';
import { RideDomainError } from '../rides/types';
import type { RedisGeoProjectionService } from '../redis/geo_projection';
import { parseAndValidateLocationBody } from './validation';
import {
  LocationDomainError,
  type LocationMode,
  type LocationUpdateSnapshot,
  type ParsedLocationUpdate,
} from './types';

const DRIVERS = 'drivers';
const LOCATION_STREAMS = 'locationStreams';

/** Idle stream registry doc id. */
export function idleStreamDocId(driverId: string): string {
  return driverId;
}

/** Trip stream registry doc id (Phase 1.6). */
export function tripStreamDocId(rideId: string, driverId: string): string {
  return `${rideId}_${driverId}`;
}

/**
 * N2A — validate location update + durable locationStreams cursor.
 * N2C — optional Redis GEO projection after accept (non-authoritative).
 * No RTDB, nearby, or dispatch.
 */
export class LocationUpdateService {
  constructor(
    private readonly db: Firestore,
    private readonly geoProjection: RedisGeoProjectionService | null = null,
  ) {}

  async update(input: {
    caller: AuthenticatedCaller;
    body: unknown;
    requestId?: string;
    nowMs?: number;
  }): Promise<{ httpStatus: number; body: { data: LocationUpdateSnapshot } }> {
    const nowMs = input.nowMs ?? Date.now();
    const driverId = input.caller.uid;

    const driverDoc = await this.assertApprovedOnlineDriver(driverId);

    const parsed = parseAndValidateLocationBody(
      input.body,
      nowMs,
      input.requestId,
    );

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
