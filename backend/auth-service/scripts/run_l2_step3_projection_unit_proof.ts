/**
 * L2 Step 3 — projection unit proof (MemoryDb + MemoryTripLocationRtdb).
 * Usage: npm run test:l2-step3-projection-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { MemoryTripLocationRtdb } from '../src/rtdb/memory_trip_location_rtdb';
import { tripLocationLatestPath } from '../src/rtdb/paths';

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

function seedApprovedOnline(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

function body(overrides: Record<string, unknown> = {}) {
  return {
    locationSeq: 1,
    locationStreamId: 'stream-a',
    lat: 31.52,
    lng: 74.35,
    accuracy: 8,
    heading: 90,
    speed: 20,
    timestamp: new Date().toISOString(),
    provider: 'gps',
    ...overrides,
  };
}

async function main(): Promise<void> {
  await test('A. trip accept projects RTDB latest', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    db.seed('rides', 'ride-1', {
      rideId: 'ride-1',
      passengerId: 'p1',
      assignedDriverId: 'd1',
      state: 'DRIVER_ASSIGNED',
    });
    const app = createApp({
      auth: {
        verifyIdToken: async () => ({ uid: 'd1', phone_number: '+1' }),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      tripLocationRtdb: rtdb,
    });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body({ rideId: 'ride-1' }));
    assert(res.status === 200, `status ${res.status}`);
    assert(db.getDoc('locationStreams', 'ride-1_d1') != null, 'cursor');
    assert(
      (rtdb.get(tripLocationLatestPath('ride-1')) as { driverId: string })
        .driverId === 'd1',
      'rtdb driverId',
    );
  });

  await test('C. idle does not write tripLocations', async () => {
    const db = memoryDb();
    const rtdb = new MemoryTripLocationRtdb();
    seedApprovedOnline(db, 'd1');
    const app = createApp({
      auth: {
        verifyIdToken: async () => ({ uid: 'd1', phone_number: '+1' }),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      tripLocationRtdb: rtdb,
    });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(body());
    assert(res.status === 200 && res.body.data.mode === 'idle', 'idle');
    assert(rtdb.store.size === 0, 'no rtdb writes');
  });

  console.log(`\nL2 Step 3 projection unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
