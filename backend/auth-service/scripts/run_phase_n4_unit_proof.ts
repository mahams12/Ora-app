/**
 * Standalone N4 unit proof (MemoryDb + MemoryRedis).
 * Usage: npm run test:phase-n4-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { createMemoryRedis } from '../src/redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../src/redis/types';
import { waveDocId } from '../src/rides/dispatch_types';

const WORKER = 'n4-unit-proof-worker-token';
const PICKUP = { lat: 31.52, lng: 74.35 };

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

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    displayName: uid,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

async function seedGeo(
  redis: ReturnType<typeof createMemoryRedis>,
  driverId: string,
  lng: number,
  lat: number,
  lastLocationTs: number,
) {
  await redis.geoadd(GEO_DRIVERS_KEY, lng, lat, driverId);
  const full: DriverOnlineMarker = {
    driverId,
    accuracy: 8,
    city: null,
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date().toISOString(),
    lastLocationTs,
  };
  await redis.set(
    driverOnlineKey(driverId),
    JSON.stringify(full),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

async function main(): Promise<void> {
  const db = memoryDb();
  const redis = createMemoryRedis();
  const now = Date.now();
  const ids: string[] = [];
  for (let i = 0; i < 12; i += 1) {
    const id = `n4d${i}`;
    ids.push(id);
    seedApprovedOnline(db, id);
    await seedGeo(redis, id, PICKUP.lng + i * 0.001, PICKUP.lat, now);
  }

  db.seed('rides', 'n4ride1', {
    rideId: 'n4ride1',
    passengerId: 'p1',
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
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    redis,
  });

  await test('worker auth required', async () => {
    const res = await request(app).post(
      '/v1/internal/rides/n4ride1/dispatch-tick',
    );
    assert(res.status === 403, `expected 403 got ${res.status}`);
  });

  await test('wave 1 invites 5 by pickup lat/lng', async () => {
    const res = await request(app)
      .post('/v1/internal/rides/n4ride1/dispatch-tick')
      .set('X-Ora-Worker-Token', WORKER);
    assert(res.status === 200, `status ${res.status}`);
    assert(res.body.data.outcome === 'wave_completed', 'outcome');
    assert(res.body.data.invitedCount === 5, 'count');
    assert(
      JSON.stringify(res.body.data.driverIds) ===
        JSON.stringify(ids.slice(0, 5)),
      'order',
    );
    assert(db.getDoc('rideDispatchWaves', waveDocId('n4ride1', 1)), 'wave doc');
    assert(db.getDoc('rides', 'n4ride1')!.assignedDriverId == null, 'no assign');
  });

  await test('cadence blocks wave 2 until due', async () => {
    const res = await request(app)
      .post('/v1/internal/rides/n4ride1/dispatch-tick')
      .set('X-Ora-Worker-Token', WORKER);
    assert(res.status === 200, `status ${res.status}`);
    assert(res.body.data.outcome === 'not_due', 'not_due');
  });

  await test('wave 2 invites 10 new after cadence', async () => {
    db.seed('rides', 'n4ride1', {
      ...db.getDoc('rides', 'n4ride1')!,
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await request(app)
      .post('/v1/internal/rides/n4ride1/dispatch-tick')
      .set('X-Ora-Worker-Token', WORKER);
    assert(res.status === 200, `status ${res.status}`);
    assert(res.body.data.waveNumber === 2, 'wave 2');
    assert(res.body.data.invitedCount === 7, `got ${res.body.data.invitedCount}`);
    // 12 total - 5 invited = 7 remaining for wave 2 (under-fill ok)
  });

  await test('no rideOffers created', async () => {
    for (const [path] of db.store.entries()) {
      assert(!path.startsWith('rideOffers/'), `unexpected offer ${path}`);
    }
  });

  console.log(`\nN4 unit proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
