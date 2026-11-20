/**
 * L2 Step 3A — LIVE staging RTDB proof (Admin + TripLocationRtdb abstraction).
 *
 * Requires:
 *   FIREBASE_PROJECT_ID=ora-app-d8112
 *   FIREBASE_DATABASE_URL=https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app
 *   GOOGLE_APPLICATION_CREDENTIALS=<staging Admin SA>
 *
 * Does NOT print credentials. Writes only under a dedicated proof ride id, then cleans up.
 */
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import request from 'supertest';
import { createApp } from '../src/app';
import { AdminTripLocationRtdb } from '../src/rtdb/admin_trip_location_rtdb';
import {
  cleanupTripLocationOnTerminal,
  grantRideLocationAccess,
} from '../src/rtdb/ride_location_lifecycle';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import {
  rideAccessRidePath,
  rideAccessUidPath,
  tripLocationLatestPath,
  tripLocationsRidePath,
} from '../src/rtdb/paths';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const EXPECTED_HOST =
  'ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app';
const EXPECTED_URL = `https://${EXPECTED_HOST}`;
const EXPECTED_PROJECT = 'ora-app-d8112';

type Evidence = Record<string, unknown>;

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function hostnameOf(url: string): string {
  return url.replace(/^https?:\/\//, '').split('/')[0] ?? '';
}

async function main(): Promise<void> {
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  const databaseURL = process.env.FIREBASE_DATABASE_URL?.trim();
  assert(projectId === EXPECTED_PROJECT, `Unexpected FIREBASE_PROJECT_ID`);
  assert(databaseURL === EXPECTED_URL, `FIREBASE_DATABASE_URL must be exact staging URL`);
  assert(
    hostnameOf(databaseURL) === EXPECTED_HOST,
    'RTDB hostname mismatch',
  );
  assert(
    Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim()),
    'GOOGLE_APPLICATION_CREDENTIALS required',
  );

  const proofRideId = `l2s3a-proof-${Date.now().toString(36)}`;
  const proofPassengerUid = `l2s3a-pax-${Date.now().toString(36)}`;
  const proofDriverUid = `l2s3a-drv-${Date.now().toString(36)}`;

  const evidence: Evidence = {
    step: 'L2_STEP_3A',
    verdict: 'PENDING',
    capturedAt: new Date().toISOString(),
    staging: {
      firebaseProjectId: projectId,
      cloudRunService: process.env.STAGING_CLOUD_RUN_SERVICE ?? 'ora-auth-service-staging',
      cloudRunRevision: process.env.STAGING_CLOUD_RUN_REVISION ?? null,
      oraEnv: 'staging',
      hasFirebaseDatabaseUrlEnv: true,
      rtdbHostname: EXPECTED_HOST,
      rtdbUrlExactMatch: databaseURL === EXPECTED_URL,
    },
    proofRideId,
    proofPassengerUid,
    proofDriverUid,
    proofs: {} as Record<string, unknown>,
    safety: {
      usedExactConsoleVerifiedUrl: true,
      didNotCreateDatabase: true,
      didNotTouchProductionService: true,
    },
  };

  // Single Admin app — never a second named production app.
  for (const a of getApps()) {
    await deleteApp(a);
  }
  const app = initializeApp({
    projectId,
    databaseURL,
    // applicationDefault via GOOGLE_APPLICATION_CREDENTIALS
  });
  const dbRtdb = getDatabase(app);
  const rtdb = new AdminTripLocationRtdb(dbRtdb);

  const proofs = evidence.proofs as Record<string, unknown>;

  try {
    // ---------- A. grantRideAccess ----------
    await grantRideLocationAccess({
      rtdb,
      rideId: proofRideId,
      passengerId: proofPassengerUid,
      assignedDriverId: proofDriverUid,
      requestId: 'l2s3a-grant',
    });
    const paxAccess = (
      await dbRtdb.ref(rideAccessUidPath(proofRideId, proofPassengerUid)).get()
    ).val();
    const drvAccess = (
      await dbRtdb.ref(rideAccessUidPath(proofRideId, proofDriverUid)).get()
    ).val();
    assert(paxAccess === true, 'passenger rideAccess not true');
    assert(drvAccess === true, 'driver rideAccess not true');
    proofs.accessGrantVerified = true;
    console.log('PASS A grantRideAccess live readback');

    // ---------- B. setTripLocationLatest ----------
    const latest = {
      lat: -89.123456, // clearly synthetic (near south pole — not a real trip)
      lng: 179.654321,
      accuracy: 1.5,
      heading: 42,
      speed: 0,
      ts: Date.now(),
      acceptedAt: new Date().toISOString(),
      driverId: proofDriverUid,
      locationSeq: 1,
      locationStreamId: 'l2s3a-stream-proof',
    };
    await rtdb.setTripLocationLatest(proofRideId, latest);
    const latestSnap = (
      await dbRtdb.ref(tripLocationLatestPath(proofRideId)).get()
    ).val() as Record<string, unknown> | null;
    assert(latestSnap != null, 'latest missing after write');
    for (const k of [
      'lat',
      'lng',
      'accuracy',
      'heading',
      'speed',
      'ts',
      'acceptedAt',
      'driverId',
      'locationSeq',
      'locationStreamId',
    ] as const) {
      assert(latestSnap[k] === latest[k], `latest field mismatch: ${k}`);
    }
    assert(latestSnap.driverId === proofDriverUid, 'driverId must be server proof uid');
    proofs.latestLocationWriteVerified = true;
    proofs.latestFields = Object.keys(latestSnap).sort();
    console.log('PASS B setTripLocationLatest live readback');

    // ---------- C. E2E projection via same LocationUpdateService path ----------
    // Uses in-memory durable cursor + LIVE Admin RTDB (same code path as Cloud Run).
    // Avoids mutating real customer rides / requiring device auth tokens.
    const mem = memoryDb();
    mem.seed('users', proofDriverUid, {
      uid: proofDriverUid,
      phoneNumber: '+923009999001',
      displayName: 'L2S3A Proof Driver',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    mem.seed('drivers', proofDriverUid, {
      driverId: proofDriverUid,
      userId: proofDriverUid,
      availabilityState: 'online',
    });
    mem.seed('rides', proofRideId, {
      rideId: proofRideId,
      passengerId: proofPassengerUid,
      assignedDriverId: proofDriverUid,
      state: 'DRIVER_ASSIGNED',
      version: 2,
      agreedOfferId: 'l2s3a-offer',
      agreedFareMinor: 1000,
    });

    const e2eApp = createApp({
      auth: {
        verifyIdToken: async () => ({
          uid: proofDriverUid,
          phone_number: '+923009999001',
        }),
      } as never,
      db: mem as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      tripLocationRtdb: rtdb,
    });

    const e2eBody = {
      rideId: proofRideId,
      locationSeq: 7,
      locationStreamId: 'l2s3a-e2e-stream',
      lat: -88.5,
      lng: 178.25,
      accuracy: 3,
      heading: 10,
      speed: 1.2,
      timestamp: new Date().toISOString(),
      provider: 'gps',
    };
    const res = await request(e2eApp)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer proof-token')
      .send(e2eBody);
    assert(res.status === 200, `E2E location update HTTP ${res.status}`);

    const projected = (
      await dbRtdb.ref(tripLocationLatestPath(proofRideId)).get()
    ).val() as Record<string, unknown> | null;
    assert(projected != null, 'E2E projected latest missing');
    assert(projected.lat === e2eBody.lat, 'E2E lat mismatch');
    assert(projected.lng === e2eBody.lng, 'E2E lng mismatch');
    assert(projected.locationSeq === 7, 'E2E locationSeq mismatch');
    assert(projected.driverId === proofDriverUid, 'E2E driverId must be auth uid');
    assert(
      projected.locationStreamId === 'l2s3a-e2e-stream',
      'E2E locationStreamId mismatch',
    );
    const streamDoc = mem
      .collection('locationStreams')
      .doc(`${proofRideId}_${proofDriverUid}`);
    // memory helper may differ — read via get if available
    let streamAccepted = false;
    try {
      const snap = await (streamDoc as { get: () => Promise<{ exists: boolean; data: () => Record<string, unknown> }> }).get();
      streamAccepted = snap.exists && Number(snap.data()?.lastAcceptedSeq) === 7;
    } catch {
      streamAccepted = false;
    }
    proofs.endToEndProjectionVerified = true;
    proofs.endToEndMode =
      'local_createApp_memory_cursor_plus_live_AdminTripLocationRtdb';
    proofs.endToEndHttpStatus = res.status;
    proofs.endToEndStreamCursorAccepted = streamAccepted;
    console.log('PASS C E2E accept→live RTDB projection');

    // ---------- D. Terminal cleanup ----------
    // Seed a trip stream on memory db so closeTripLocationStream can run.
    mem.seed('locationStreams', `${proofRideId}_${proofDriverUid}`, {
      streamId: `${proofRideId}_${proofDriverUid}`,
      driverId: proofDriverUid,
      rideId: proofRideId,
      mode: 'trip',
      streamState: 'OPEN',
      lastAcceptedSeq: 7,
      updatedAt: new Date().toISOString(),
    });

    await cleanupTripLocationOnTerminal({
      db: mem as never,
      rtdb,
      rideId: proofRideId,
      assignedDriverId: proofDriverUid,
      requestId: 'l2s3a-cleanup-1',
      reason: 'RIDE_COMPLETED',
    });

    const accessAfter = (
      await dbRtdb.ref(rideAccessRidePath(proofRideId)).get()
    ).val();
    const tripAfter = (
      await dbRtdb.ref(tripLocationsRidePath(proofRideId)).get()
    ).val();
    assert(accessAfter == null, 'rideAccess still present after cleanup');
    assert(tripAfter == null, 'tripLocations still present after cleanup');
    proofs.terminalCleanupVerified = true;
    console.log('PASS D terminal cleanup live verified');

    // ---------- E. Idempotent repeated cleanup ----------
    await cleanupTripLocationOnTerminal({
      db: mem as never,
      rtdb,
      rideId: proofRideId,
      assignedDriverId: proofDriverUid,
      requestId: 'l2s3a-cleanup-2',
      reason: 'RIDE_COMPLETED',
    });
    const accessAfter2 = (
      await dbRtdb.ref(rideAccessRidePath(proofRideId)).get()
    ).val();
    const tripAfter2 = (
      await dbRtdb.ref(tripLocationsRidePath(proofRideId)).get()
    ).val();
    assert(accessAfter2 == null, 'rideAccess residual after repeated cleanup');
    assert(tripAfter2 == null, 'tripLocations residual after repeated cleanup');
    proofs.repeatedCleanupVerified = true;
    console.log('PASS E repeated cleanup idempotent');

    // ---------- G. Final sweep of proof paths ----------
    await dbRtdb.ref(rideAccessRidePath(proofRideId)).remove();
    await dbRtdb.ref(tripLocationsRidePath(proofRideId)).remove();
    await dbRtdb.ref(`__ora_proof_connectivity`).remove().catch(() => undefined);
    proofs.cleanupCompleted = true;
    console.log('PASS G final proof data removed');

    evidence.verdict = 'GREEN_LIVE_STAGING_RTDB_PROOF_CLOSED';
  } catch (err) {
    evidence.verdict = 'RED_OR_YELLOW_PROOF_FAILED';
    evidence.errorType = err instanceof Error ? err.name : 'unknown';
    evidence.errorMessage = err instanceof Error ? err.message.slice(0, 300) : String(err).slice(0, 300);
    // Best-effort cleanup on failure
    try {
      await dbRtdb.ref(rideAccessRidePath(proofRideId)).remove();
      await dbRtdb.ref(tripLocationsRidePath(proofRideId)).remove();
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    const out = resolve(
      __dirname,
      '../../../mobile/.e2e_artifacts/L2_STEP3A_LIVE_STAGING_RTDB_PROOF.json',
    );
    // partial write here; caller may enrich with regression
    writeFileSync(out, JSON.stringify(evidence, null, 2) + '\n');
    console.log('EVIDENCE_PARTIAL=' + out);
    await deleteApp(app).catch(() => undefined);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
