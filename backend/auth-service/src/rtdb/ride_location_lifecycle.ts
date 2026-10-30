import type { Firestore } from 'firebase-admin/firestore';
import { logSafe } from '../http/errors';
import {
  FirestoreLocationStreamStore,
  type LocationStreamStore,
} from '../location/stream_store';
import { NullTripLocationRtdb } from './admin_trip_location_rtdb';
import type { TripLocationLatest, TripLocationRtdb } from './types';

/** Same id formula as location_update_service.tripStreamDocId. */
function tripStreamDocId(rideId: string, driverId: string): string {
  return `${rideId}_${driverId}`;
}

/** Retention after terminal close — aligns with Phase 1.6 stream TTL note. */
const STREAM_CLOSED_EXPIRES_MS = 10 * 60 * 1000;

function isRtdbLive(rtdb: TripLocationRtdb): boolean {
  return !(rtdb instanceof NullTripLocationRtdb);
}

/**
 * L2 Step 3 — grant rideAccess for passenger + assigned driver after DRIVER_ASSIGNED.
 * Best-effort; never throws to ride mutation callers.
 */
export async function grantRideLocationAccess(input: {
  rtdb: TripLocationRtdb;
  rideId: string;
  passengerId: string;
  assignedDriverId: string;
  requestId?: string;
}): Promise<void> {
  if (!isRtdbLive(input.rtdb)) {
    logSafe('RTDB_RIDE_ACCESS_SKIPPED', {
      rideId: input.rideId,
      reason: 'rtdb_not_configured',
      requestId: input.requestId ?? null,
    });
    return;
  }
  try {
    await input.rtdb.grantRideAccess(input.rideId, input.passengerId);
    await input.rtdb.grantRideAccess(input.rideId, input.assignedDriverId);
    logSafe('RTDB_RIDE_ACCESS_GRANTED', {
      rideId: input.rideId,
      requestId: input.requestId ?? null,
    });
  } catch (err) {
    logSafe('RTDB_RIDE_ACCESS_GRANT_FAILED', {
      rideId: input.rideId,
      requestId: input.requestId ?? null,
      errorType: err instanceof Error ? err.name : 'unknown',
    });
  }
}

/**
 * Close trip locationStreams/{rideId}_{driverId} (idempotent).
 * Durable cursor mutation via the configured stream store (Firestore or RTDB).
 */
export async function closeTripLocationStream(input: {
  db: Firestore;
  rideId: string;
  driverId: string | null | undefined;
  nowMs?: number;
  streamStore?: LocationStreamStore;
}): Promise<void> {
  const driverId =
    typeof input.driverId === 'string' && input.driverId.trim() !== ''
      ? input.driverId.trim()
      : null;
  if (driverId == null) return;

  const nowMs = input.nowMs ?? Date.now();
  const nowIso = new Date(nowMs).toISOString();
  const expiresAtIso = new Date(nowMs + STREAM_CLOSED_EXPIRES_MS).toISOString();
  const docId = tripStreamDocId(input.rideId, driverId);
  const store =
    input.streamStore ?? new FirestoreLocationStreamStore(input.db);
  await store.close({ docId, updatedAtIso: nowIso, expiresAtIso });
}

/**
 * L2 Step 3 — terminal cleanup: revoke ACL, delete tripLocations, close stream.
 * Idempotent; best-effort RTDB; stream close is durable Firestore.
 * Never throws to ride mutation callers.
 */
export async function cleanupTripLocationOnTerminal(input: {
  db: Firestore;
  rtdb: TripLocationRtdb;
  rideId: string;
  assignedDriverId: string | null | undefined;
  requestId?: string;
  reason: string;
  streamStore?: LocationStreamStore;
}): Promise<void> {
  try {
    if (isRtdbLive(input.rtdb)) {
      await input.rtdb.revokeRideAccess(input.rideId);
      await input.rtdb.clearTripLocations(input.rideId);
    }
    await closeTripLocationStream({
      db: input.db,
      rideId: input.rideId,
      driverId: input.assignedDriverId,
      streamStore: input.streamStore,
    });
    logSafe('RTDB_TRIP_LOCATION_CLEANUP', {
      rideId: input.rideId,
      reason: input.reason,
      rtdbConfigured: isRtdbLive(input.rtdb),
      requestId: input.requestId ?? null,
    });
  } catch (err) {
    logSafe('RTDB_TRIP_LOCATION_CLEANUP_FAILED', {
      rideId: input.rideId,
      reason: input.reason,
      requestId: input.requestId ?? null,
      errorType: err instanceof Error ? err.name : 'unknown',
    });
  }
}

/**
 * Project accepted trip location to RTDB latest (after durable cursor accept).
 * Best-effort — never throws.
 */
export async function projectAcceptedTripLocationLatest(input: {
  rtdb: TripLocationRtdb;
  rideId: string;
  latest: TripLocationLatest;
  requestId?: string;
}): Promise<'projected' | 'failed' | 'skipped'> {
  if (!isRtdbLive(input.rtdb)) {
    logSafe('RTDB_TRIP_LOCATION_SKIPPED', {
      rideId: input.rideId,
      reason: 'rtdb_not_configured',
      locationSeq: input.latest.locationSeq,
      requestId: input.requestId ?? null,
    });
    return 'skipped';
  }
  try {
    await input.rtdb.setTripLocationLatest(input.rideId, input.latest);
    logSafe('RTDB_TRIP_LOCATION_PROJECTED', {
      rideId: input.rideId,
      locationSeq: input.latest.locationSeq,
      requestId: input.requestId ?? null,
    });
    return 'projected';
  } catch (err) {
    logSafe('RTDB_TRIP_LOCATION_PROJECT_FAILED', {
      rideId: input.rideId,
      locationSeq: input.latest.locationSeq,
      requestId: input.requestId ?? null,
      errorType: err instanceof Error ? err.name : 'unknown',
    });
    return 'failed';
  }
}
