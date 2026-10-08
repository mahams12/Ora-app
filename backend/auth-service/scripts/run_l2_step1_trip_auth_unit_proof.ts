/**
 * L2 Step 1 — trip location authorization unit proof (MemoryDb).
 * Usage: npm run test:l2-step1-trip-auth-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';

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

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
) {
  seedUser(db, uid, { role: 'driver', driverStatus: 'approved' });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

function seedRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: 'd1',
    state: 'DRIVER_ASSIGNED',
    ...overrides,
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
  } as never;
}

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

function baseBody(overrides: Record<string, unknown> = {}) {
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

async function expectAccepted(
  label: string,
  state: string,
): Promise<void> {
  const db = memoryDb();
  seedApprovedOnline(db, 'd1');
  seedRide(db, 'ride-ok', { state, assignedDriverId: 'd1' });
  const before = db.getDoc('locationStreams', 'ride-ok_d1');
  assert(before == null, `${label}: no cursor before`);
  const res = await request(appFor(db, 'd1'))
    .post('/v1/location/update')
    .set('Authorization', 'Bearer t')
    .send(baseBody({ rideId: 'ride-ok' }));
  assert(res.status === 200, `${label}: status ${res.status}`);
  assert(res.body.data.mode === 'trip', `${label}: mode`);
  assert(res.body.data.driverId === 'd1', `${label}: driverId`);
  assert(res.body.data.rideId === 'ride-ok', `${label}: rideId`);
  assert(
    db.getDoc('locationStreams', 'ride-ok_d1')?.lastAcceptedSeq === 1,
    `${label}: cursor advanced`,
  );
}

async function expectForbidden(
  label: string,
  setup: (db: ReturnType<typeof memoryDb>) => void,
  bodyOverrides: Record<string, unknown>,
  callerUid = 'd1',
): Promise<void> {
  const db = memoryDb();
  seedApprovedOnline(db, 'd1');
  seedApprovedOnline(db, 'd2');
  setup(db);
  const res = await request(appFor(db, callerUid))
    .post('/v1/location/update')
    .set('Authorization', 'Bearer t')
    .send(baseBody(bodyOverrides));
  assert(res.status === 403, `${label}: status ${res.status}`);
  assert(
    res.body.error.code === 'RIDE_LOCATION_FORBIDDEN',
    `${label}: code ${res.body.error?.code}`,
  );
  const rideId =
    typeof bodyOverrides.rideId === 'string' ? bodyOverrides.rideId : null;
  if (rideId) {
    assert(
      db.getDoc('locationStreams', `${rideId}_${callerUid}`) == null,
      `${label}: no trip cursor mutation`,
    );
  }
}

async function main(): Promise<void> {
  await test('1. Assigned driver + DRIVER_ASSIGNED → accepted', async () => {
    await expectAccepted('ASSIGNED', 'DRIVER_ASSIGNED');
  });

  await test('2. Assigned driver + DRIVER_EN_ROUTE → accepted', async () => {
    await expectAccepted('EN_ROUTE', 'DRIVER_EN_ROUTE');
  });

  await test('3. Assigned driver + DRIVER_ARRIVED → accepted', async () => {
    await expectAccepted('ARRIVED', 'DRIVER_ARRIVED');
  });

  await test('4. Assigned driver + RIDE_STARTED → accepted', async () => {
    await expectAccepted('STARTED', 'RIDE_STARTED');
  });

  await test('5. Driver not assigned to ride → rejected', async () => {
    await expectForbidden(
      'not-assigned',
      (db) => {
        seedRide(db, 'ride-x', {
          state: 'DRIVER_ASSIGNED',
          assignedDriverId: 'd2',
        });
      },
      { rideId: 'ride-x' },
      'd1',
    );
  });

  await test(
    '6. Driver assigned to ride A cannot publish to ride B → rejected',
    async () => {
      await expectForbidden(
        'cross-ride',
        (db) => {
          seedRide(db, 'ride-a', {
            state: 'DRIVER_ASSIGNED',
            assignedDriverId: 'd1',
          });
          seedRide(db, 'ride-b', {
            state: 'DRIVER_ASSIGNED',
            assignedDriverId: 'd2',
          });
        },
        { rideId: 'ride-b' },
        'd1',
      );
    },
  );

  for (const [n, state] of [
    ['7', 'SEARCHING'],
    ['8', 'OFFERS_AVAILABLE'],
    ['9', 'EXPIRED'],
    ['10', 'CANCELLED'],
    ['11', 'NO_SHOW'],
    ['12', 'RIDE_COMPLETED'],
    ['13', 'RIDE_CLOSED'],
  ] as const) {
    await test(`${n}. ${state} → rejected`, async () => {
      await expectForbidden(
        state,
        (db) => {
          seedRide(db, 'ride-bad', {
            state,
            // Even if somehow still "assigned", wrong state must reject.
            assignedDriverId: 'd1',
          });
        },
        { rideId: 'ride-bad' },
      );
    });
  }

  await test('14. Request body driverId cannot override auth.uid', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedApprovedOnline(db, 'd2');
    seedRide(db, 'ride-d1', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd1',
    });
    seedRide(db, 'ride-d2', {
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd2',
    });

    // Auth as d1, body claims d2, publishes to d1's ride → still d1.
    const ok = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ rideId: 'ride-d1', driverId: 'd2' }));
    assert(ok.status === 200, `got ${ok.status}`);
    assert(ok.body.data.driverId === 'd1', 'auth uid wins');
    assert(db.getDoc('locationStreams', 'ride-d1_d1') != null, 'd1 cursor');
    assert(db.getDoc('locationStreams', 'ride-d1_d2') == null, 'no d2 cursor');
    assert(db.getDoc('locationStreams', 'ride-d2_d2') == null, 'd2 untouched');

    // Auth as d1 cannot publish to d2's ride even with body.driverId=d2.
    const cross = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ rideId: 'ride-d2', driverId: 'd2' }));
    assert(cross.status === 403, `cross status ${cross.status}`);
    assert(
      cross.body.error.code === 'RIDE_LOCATION_FORBIDDEN',
      'cross code',
    );
    assert(
      db.getDoc('locationStreams', 'ride-d2_d1') == null,
      'no forged trip cursor',
    );
    assert(
      db.getDoc('locationStreams', 'ride-d2_d2') == null,
      'victim stream untouched',
    );
  });

  await test('15. Idle/no-ride location path remains unchanged', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    // No rides seeded — idle must still work.
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 3, locationStreamId: 'idle-s' }));
    assert(res.status === 200, `got ${res.status}`);
    assert(res.body.data.mode === 'idle', 'idle mode');
    assert(res.body.data.rideId == null, 'no rideId');
    assert(res.body.data.driverId === 'd1', 'uid');
    assert(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq === 3, 'idle cursor');
    assert(db.getDoc('locationStreams', 'ride-ok_d1') == null, 'no trip doc');
  });

  await test('16. Missing ride document → rejected, no cursor', async () => {
    await expectForbidden(
      'missing-ride',
      () => {
        /* no ride */
      },
      { rideId: 'does-not-exist' },
    );
  });

  console.log(`\nL2 Step 1 trip auth unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
