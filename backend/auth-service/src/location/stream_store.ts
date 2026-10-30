/**
 * Durable locationStreams cursor store — the atomic sequence/stream validator
 * that runs BEFORE any geo or trip projection on every accepted GPS packet.
 *
 * Two implementations behind LOCATION_STREAMS_BACKEND (default follows
 * GEO_BACKEND):
 *   - FirestoreLocationStreamStore: locationStreams/{docId} collection
 *     (original; billed 1R+1W per packet).
 *   - RtdbLocationStreamStore (rtdb/rtdb_stream_store.ts): locationStreams/{docId}
 *     RTDB nodes (zero billed ops; uploads free).
 *
 * Semantics are identical on both: CLOSED streams reject, same-stream requires
 * strictly increasing locationSeq, a streamId present in previousStreamIds is
 * a replaced stream and rejects, a new streamId replaces the active stream.
 *
 * Atomicity contract: the cursor accept is a single transaction; the geo
 * projection that follows is a second, guarded transaction. Cursor can never
 * lag geo — on a crash between them geo simply holds the previous position
 * until the next packet (identical ordering guarantee as the original
 * Firestore split — proven, not weakened).
 */
import type { Firestore } from 'firebase-admin/firestore';
import {
  LocationDomainError,
  type LocationMode,
  type LocationUpdateSnapshot,
  type ParsedLocationUpdate,
} from './types';

const LOCATION_STREAMS = 'locationStreams';

export interface LocationStreamAcceptInput {
  docId: string;
  driverId: string;
  mode: LocationMode;
  parsed: ParsedLocationUpdate;
  acceptedAt: string;
}

export interface StreamCleanupResult {
  scanned: number;
  deleted: number;
  skipped: number;
  failed: number;
}

export interface LocationStreamStore {
  /** Atomic cursor validation + advance. Throws LocationDomainError on stale input. */
  accept(input: LocationStreamAcceptInput): Promise<LocationUpdateSnapshot>;
  /** Idempotent close — returns true when a stream was transitioned to CLOSED. */
  close(input: {
    docId: string;
    updatedAtIso: string;
    expiresAtIso: string;
  }): Promise<boolean>;
  /** Storage-hygiene sweep of expired cursor records. */
  sweepExpired(input: {
    limit: number;
    nowMs: number;
  }): Promise<StreamCleanupResult>;
}

export function streamDocExpiresAtMs(
  mode: LocationMode,
  acceptedAtIso: string,
): number {
  const t = Date.parse(acceptedAtIso);
  // Idle: refresh sliding 24h. Trip: long enough until terminal cleanup.
  const ms = mode === 'idle' ? 24 * 60 * 60 * 1000 : 7 * 24 * 60 * 60 * 1000;
  return t + ms;
}

export class FirestoreLocationStreamStore implements LocationStreamStore {
  constructor(private readonly db: Firestore) {}

  async accept(
    input: LocationStreamAcceptInput,
  ): Promise<LocationUpdateSnapshot> {
    const { docId, driverId, mode, parsed, acceptedAt } = input;

    return this.db.runTransaction(async (tx) => {
      const ref = this.db.collection(LOCATION_STREAMS).doc(docId);
      const snap = await tx.get(ref);
      const existing = snap.exists ? (snap.data() ?? {}) : null;
      const expiresAt = new Date(
        streamDocExpiresAtMs(mode, acceptedAt),
      ).toISOString();

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
            expiresAt,
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
            expiresAt,
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
          expiresAt,
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

  async close(input: {
    docId: string;
    updatedAtIso: string;
    expiresAtIso: string;
  }): Promise<boolean> {
    const ref = this.db.collection(LOCATION_STREAMS).doc(input.docId);
    const snap = await ref.get();
    if (!snap.exists) return false;
    const data = snap.data() ?? {};
    if (data.streamState === 'CLOSED') return false;
    await ref.update({
      streamState: 'CLOSED',
      updatedAt: input.updatedAtIso,
      expiresAt: input.expiresAtIso,
    });
    return true;
  }

  async sweepExpired(input: {
    limit: number;
    nowMs: number;
  }): Promise<StreamCleanupResult> {
    const nowIso = new Date(input.nowMs).toISOString();
    const result: StreamCleanupResult = {
      scanned: 0,
      deleted: 0,
      skipped: 0,
      failed: 0,
    };
    const snap = await this.db
      .collection(LOCATION_STREAMS)
      .where('expiresAt', '<=', nowIso)
      .orderBy('expiresAt')
      .limit(input.limit)
      .get();
    result.scanned = snap.docs.length;
    for (const doc of snap.docs) {
      const raw = doc.data().expiresAt;
      const expMs =
        typeof raw === 'string' && raw.trim() !== '' ? Date.parse(raw) : NaN;
      if (!Number.isFinite(expMs) || expMs > input.nowMs) {
        result.skipped += 1;
        continue;
      }
      try {
        await doc.ref.delete();
        result.deleted += 1;
      } catch {
        result.failed += 1;
      }
    }
    return result;
  }
}
