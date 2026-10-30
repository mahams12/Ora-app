/**
 * RTDB locationStreams cursor store — zero-billed-op mirror of
 * FirestoreLocationStreamStore behind LOCATION_STREAMS_BACKEND=rtdb.
 *
 * Layout: `locationStreams/{docId}` where docId = driverId (idle) or
 * `${rideId}_${driverId}` (trip):
 *   { driverId, activeStreamId, lastAcceptedSeq, streamState,
 *     previousStreamIds[], rideId?, expiresAtMs, createdAt, updatedAt }
 *
 * `accept` runs in ONE RTDB transaction per doc — the same check-then-act
 * atomicity as the Firestore transaction (RTDB serializes per-node
 * transactions, so concurrent publishers and multi-instance writes stay
 * correct). Rejection is an abort (committed:false) with the reason captured
 * out-of-band so the caller can throw the right domain error.
 *
 * Semantics are byte-identical to the Firestore store:
 *   CLOSED → reject; same stream → strictly increasing seq; streamId in
 *   previousStreamIds → reject (replaced stream); new streamId → replaces
 *   active and resets seq.
 *
 * `expiresAtMs` is numeric so `orderByChild('expiresAtMs')` +
 * `.indexOn:["expiresAtMs"]` drives the hygiene sweep without downloads of
 * fresh nodes.
 */
import {
  LocationDomainError,
  type LocationUpdateSnapshot,
} from '../location/types';
import {
  streamDocExpiresAtMs,
  type LocationStreamAcceptInput,
  type LocationStreamStore,
  type StreamCleanupResult,
} from '../location/stream_store';
import type { RtdbRefLike } from './rtdb_geo_client';

const LOCATION_STREAMS = 'locationStreams';

type RejectReason = 'CLOSED' | 'SEQ' | 'REPLACED';

function rejectError(reason: RejectReason | null): LocationDomainError {
  switch (reason) {
    case 'CLOSED':
      return new LocationDomainError(
        'SEQUENCE_VIOLATION',
        422,
        'Location stream is closed.',
      );
    case 'REPLACED':
      return new LocationDomainError(
        'SEQUENCE_VIOLATION',
        422,
        'Location stream is no longer active.',
      );
    default:
      return new LocationDomainError(
        'SEQUENCE_VIOLATION',
        422,
        'locationSeq must be greater than last accepted sequence.',
      );
  }
}

export class RtdbLocationStreamStore implements LocationStreamStore {
  constructor(private readonly root: RtdbRefLike) {}

  private ref(docId: string): RtdbRefLike {
    return this.root.child(`${LOCATION_STREAMS}/${docId}`);
  }

  async accept(
    input: LocationStreamAcceptInput,
  ): Promise<LocationUpdateSnapshot> {
    const { docId, driverId, mode, parsed, acceptedAt } = input;
    const expiresAtMs = streamDocExpiresAtMs(mode, acceptedAt);
    let rejected: RejectReason | null = null;

    const result = await this.ref(docId).transaction((current) => {
      const existing =
        current != null && typeof current === 'object'
          ? (current as Record<string, unknown>)
          : null;

      if (existing == null) {
        const created: Record<string, unknown> = {
          driverId,
          activeStreamId: parsed.locationStreamId,
          lastAcceptedSeq: parsed.locationSeq,
          streamState: 'ACTIVE',
          previousStreamIds: [],
          createdAt: acceptedAt,
          updatedAt: acceptedAt,
          expiresAtMs,
        };
        if (mode === 'trip' && parsed.rideId) created.rideId = parsed.rideId;
        return created;
      }

      const streamState =
        typeof existing.streamState === 'string'
          ? existing.streamState
          : 'ACTIVE';
      if (streamState === 'CLOSED') {
        rejected = 'CLOSED';
        return undefined;
      }

      const activeStreamId =
        typeof existing.activeStreamId === 'string'
          ? existing.activeStreamId
          : '';
      const lastAcceptedSeq =
        typeof existing.lastAcceptedSeq === 'number'
          ? existing.lastAcceptedSeq
          : -1;

      if (activeStreamId === parsed.locationStreamId) {
        if (parsed.locationSeq <= lastAcceptedSeq) {
          rejected = 'SEQ';
          return undefined;
        }
        return {
          ...existing,
          lastAcceptedSeq: parsed.locationSeq,
          streamState: 'ACTIVE',
          updatedAt: acceptedAt,
          expiresAtMs,
        };
      }

      const previous =
        Array.isArray(existing.previousStreamIds) &&
        existing.previousStreamIds.every((x) => typeof x === 'string')
          ? ([...existing.previousStreamIds] as string[])
          : [];

      // Late packets from a replaced stream must never overwrite the active stream.
      if (previous.includes(parsed.locationStreamId)) {
        rejected = 'REPLACED';
        return undefined;
      }

      // New stream replaces active; sequence does not carry over.
      if (activeStreamId) previous.push(activeStreamId);
      return {
        ...existing,
        activeStreamId: parsed.locationStreamId,
        lastAcceptedSeq: parsed.locationSeq,
        streamState: 'ACTIVE',
        previousStreamIds: previous.slice(-5),
        updatedAt: acceptedAt,
        expiresAtMs,
        ...(mode === 'trip' && parsed.rideId ? { rideId: parsed.rideId } : {}),
      };
    });

    if (!result.committed) throw rejectError(rejected);

    return {
      driverId,
      mode,
      rideId: parsed.rideId,
      locationStreamId: parsed.locationStreamId,
      locationSeq: parsed.locationSeq,
      acceptedAt,
    };
  }

  async close(input: {
    docId: string;
    updatedAtIso: string;
    expiresAtIso: string;
  }): Promise<boolean> {
    const expiresAtMs = Date.parse(input.expiresAtIso);
    let closed = false;
    await this.ref(input.docId).transaction((current) => {
      const existing =
        current != null && typeof current === 'object'
          ? (current as Record<string, unknown>)
          : null;
      if (existing == null || existing.streamState === 'CLOSED') return current;
      closed = true;
      return {
        ...existing,
        streamState: 'CLOSED',
        updatedAt: input.updatedAtIso,
        expiresAtMs,
      };
    });
    return closed;
  }

  async sweepExpired(input: {
    limit: number;
    nowMs: number;
  }): Promise<StreamCleanupResult> {
    const result: StreamCleanupResult = {
      scanned: 0,
      deleted: 0,
      skipped: 0,
      failed: 0,
    };
    const snap = await this.root
      .child(LOCATION_STREAMS)
      .orderByChild('expiresAtMs')
      .endAt(input.nowMs)
      .limitToFirst(input.limit)
      .get();
    const children: Array<{ key: string | null; val: unknown }> = [];
    snap.forEach((child) => {
      children.push({ key: child.key, val: child.val() });
    });
    result.scanned = children.length;
    for (const c of children) {
      if (c.key == null) continue;
      const exp =
        c.val != null && typeof c.val === 'object'
          ? (c.val as Record<string, unknown>).expiresAtMs
          : undefined;
      if (typeof exp !== 'number' || exp > input.nowMs) {
        result.skipped += 1;
        continue;
      }
      try {
        await this.root.child(`${LOCATION_STREAMS}/${c.key}`).remove();
        result.deleted += 1;
      } catch {
        result.failed += 1;
      }
    }
    return result;
  }
}

export function createRtdbLocationStreamStore(
  root: RtdbRefLike,
): RtdbLocationStreamStore {
  return new RtdbLocationStreamStore(root);
}
