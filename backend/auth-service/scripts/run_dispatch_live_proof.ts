/**
 * LIVE N4 dispatch proof — real Redis GEO + Firestore emulator.
 *
 * Requires:
 *   FIRESTORE_EMULATOR_HOST (via firebase emulators:exec)
 *   REDIS_URL (real Redis)
 *
 * Usage:
 *   REDIS_URL=redis://127.0.0.1:6379 npm run test:dispatch-live-proof
 *   (root script wraps firebase emulators:exec)
 */
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
} from '../src/redis/types';
import { waveDocId } from '../src/rides/dispatch_types';

const WORKER = 'n4-live-proof-worker-tokenx';
const PICKUP = { lat: 31.5204, lng: 74.3587 };

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(err);
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

async function main(): Promise<void> {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error(
      'N4 LIVE PROOF BLOCKED: FIRESTORE_EMULATOR_HOST is not set.',
    );
    console.error(
      'Run via: REDIS_URL=... npm run test:dispatch-live-proof (root package.json)',
    );
    process.exit(2);
  }
  if (!process.env.REDIS_URL?.trim()) {
    console.error('N4 LIVE PROOF BLOCKED: REDIS_URL is not set.');
    process.exit(2);
  }

  const redis = await createRedisGeoClientFromEnv(process.env);
  assert(redis != null, 'redis client');

  const appName = `n4-dispatch-${Date.now()}`;
  const fbApp = initializeApp({ projectId: 'ora-n4-dispatch' }, appName);
  const db = getFirestore(fbApp);
  db.settings({ ignoreUndefinedProperties: true });

  const prefix = `n4live-${Date.now()}`;
  const rideId = `${prefix}-ride`;
  const driverIds = Array.from({ length: 8 }, (_, i) => `${prefix}-d${i}`);
  const now = Date.now();

  try {
    for (let i = 0; i < driverIds.length; i += 1) {
      const id = driverIds[i]!;
      await db.collection('users').doc(id).set({
        uid: id,
        role: 'driver',
        driverStatus: 'approved',
        isActive: true,
        banned: false,
        displayName: id,
      });
      await db.collection('drivers').doc(id).set({
        driverId: id,
        userId: id,
        availabilityState: 'online',
      });
      await redis.geoadd(
        GEO_DRIVERS_KEY,
        PICKUP.lng + i * 0.001,
        PICKUP.lat,
        id,
      );
      await redis.set(
        driverOnlineKey(id),
        JSON.stringify({
          driverId: id,
          lastLocationTs: now,
          accuracy: 8,
          city: null,
          locationStreamId: 's1',
          locationSeq: 1,
          acceptedAt: new Date().toISOString(),
        }),
        DRIVER_ONLINE_TTL_SECONDS,
      );
    }

    await db.collection('rides').doc(rideId).set({
      rideId,
      passengerId: `${prefix}-p`,
      assignedDriverId: null,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category: 'zip',
      serviceType: 'ride',
      pickup: { ...PICKUP },
      destination: { lat: 31.53, lng: 74.36 },
      routePolyline: null,
      distanceKm: null,
      estimatedDurationMin: null,
      pricingSnapshotId: 'ps1',
      recommendedFareMinor: 50000,
      passengerOfferMinor: 45000,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: null,
      paymentMethod: 'CASH',
      paymentIntentId: null,
      passengerCount: 1,
      expiresAt: new Date(now + 15 * 60_000).toISOString(),
      assignedAt: null,
      arrivedAt: null,
      startedAt: null,
      completedAt: null,
      closedAt: null,
      cancelledBy: null,
      cancellationReason: null,
      cancellationFeeMinor: null,
      createdAt: new Date(now).toISOString(),
      updatedAt: new Date(now).toISOString(),
    });

    const app = createApp({
      auth: {
        verifyIdToken: async () => ({ uid: 'x', phone_number: '+1' }),
      } as never,
      db,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 50_000 },
      internalWorkerToken: WORKER,
      redis,
    });

    await test('worker auth rejects missing token', async () => {
      const res = await request(app).post(
        `/v1/internal/rides/${rideId}/dispatch-tick`,
      );
      assert(res.status === 403, `got ${res.status}`);
    });

    await test('live wave 1 via Redis GEO + Firestore', async () => {
      const res = await request(app)
        .post(`/v1/internal/rides/${rideId}/dispatch-tick`)
        .set('X-Ora-Worker-Token', WORKER);
      assert(res.status === 200, `status ${res.status} body=${JSON.stringify(res.body)}`);
      assert(res.body.data.outcome === 'wave_completed', 'outcome');
      assert(res.body.data.invitedCount === 5, `count=${res.body.data.invitedCount}`);
      assert(res.body.data.waveNumber === 1, 'wave');

      const wave = await db
        .collection('rideDispatchWaves')
        .doc(waveDocId(rideId, 1))
        .get();
      assert(wave.exists, 'wave persisted');
      const ride = await db.collection('rides').doc(rideId).get();
      const data = ride.data()!;
      assert(data.dispatchWave === 1, 'cursor');
      assert(data.dispatchStatus === 'active', 'status');
      assert(data.assignedDriverId == null, 'no assign');
    });

    await test('idempotent retick does not duplicate wave 1 invites', async () => {
      // Reset cursor as concurrent retry
      await db.collection('rides').doc(rideId).update({
        dispatchWave: 0,
        dispatchNextAt: null,
        dispatchStatus: 'none',
      });
      const res = await request(app)
        .post(`/v1/internal/rides/${rideId}/dispatch-tick`)
        .set('X-Ora-Worker-Token', WORKER);
      assert(res.status === 200, `status ${res.status}`);
      assert(res.body.data.outcome === 'already_completed', 'idempotent');
    });

    await test('stop after cancel', async () => {
      await db.collection('rides').doc(rideId).update({
        dispatchWave: 1,
        dispatchStatus: 'active',
        dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
        state: 'CANCELLED',
        cancelledBy: 'passenger',
      });
      const res = await request(app)
        .post(`/v1/internal/rides/${rideId}/dispatch-tick`)
        .set('X-Ora-Worker-Token', WORKER);
      assert(res.status === 200, `status ${res.status}`);
      assert(res.body.data.outcome === 'stopped', 'stopped');
      const w2 = await db
        .collection('rideDispatchWaves')
        .doc(waveDocId(rideId, 2))
        .get();
      assert(!w2.exists, 'no wave 2');
    });
  } finally {
    for (const id of driverIds) {
      try {
        await redis.zrem(GEO_DRIVERS_KEY, id);
      } catch {
        /* best-effort */
      }
      try {
        await redis.del(driverOnlineKey(id));
      } catch {
        /* best-effort */
      }
    }
    try {
      await redis.quit?.();
    } catch {
      /* ignore */
    }
    await deleteApp(fbApp);
  }

  console.log(`\nN4 live proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
