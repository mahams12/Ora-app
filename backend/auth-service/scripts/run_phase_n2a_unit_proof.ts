/**
 * Standalone N2A unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-n2a-unit-proof
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
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

async function main(): Promise<void> {
  await test('1. unauthenticated → 401', async () => {
    const db = memoryDb();
    const app = createApp({
      auth: {
        verifyIdToken: async () => {
          throw new Error('bad');
        },
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
    const res = await request(app).post('/v1/location/update').send(baseBody());
    assert(res.status === 401, `got ${res.status}`);
  });

  await test('2. passenger rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', { role: 'passenger' });
    const res = await request(appFor(db, 'p1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody());
    assert(res.status === 403, `got ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_APPROVED', 'code');
  });

  await test('3. pending driver rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'd-p', { role: 'driver', driverStatus: 'pending' });
    const res = await request(appFor(db, 'd-p'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody());
    assert(res.status === 403, `got ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_APPROVED', 'code');
  });

  await test('4. suspended driver rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'd-s', { role: 'driver', driverStatus: 'suspended' });
    const res = await request(appFor(db, 'd-s'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody());
    assert(res.status === 403, `got ${res.status}`);
  });

  await test('5. approved offline rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', { role: 'driver', driverStatus: 'approved' });
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'offline',
    });
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody());
    assert(res.status === 403, `got ${res.status}`);
    assert(res.body.error.code === 'FORBIDDEN', 'offline code');
  });

  await test('6. approved online accepted', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody());
    assert(res.status === 200, `got ${res.status}`);
    assert(res.body.data.mode === 'idle', 'idle');
    assert(res.body.data.locationSeq === 1, 'seq');
  });

  await test('7-11. invalid coords/accuracy/speed', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    for (const [label, body] of [
      ['lat', baseBody({ lat: 99 })],
      ['lng', baseBody({ lng: 200 })],
      ['nan', baseBody({ lat: Number.NaN })],
      ['inf', baseBody({ lng: Number.POSITIVE_INFINITY })],
      ['acc', baseBody({ accuracy: 51 })],
      ['speed', baseBody({ speed: 201 })],
    ] as const) {
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(body);
      assert(res.status === 422, `${label} status ${res.status}`);
      assert(res.body.error.code === 'INVALID_LOCATION', `${label} code`);
    }
  });

  await test('12. timestamp older than 15s → STALE', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const old = new Date(Date.now() - 20_000).toISOString();
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ timestamp: old }));
    assert(res.status === 422, `got ${res.status}`);
    assert(res.body.error.code === 'STALE_LOCATION', 'code');
  });

  await test('13. future beyond 5s → STALE', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const fut = new Date(Date.now() + 10_000).toISOString();
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ timestamp: fut }));
    assert(res.status === 422, `got ${res.status}`);
    assert(res.body.error.code === 'STALE_LOCATION', 'code');
  });

  await test('14-17. sequence monotonicity', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    const a = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1 }));
    assert(a.status === 200, 'first');
    const b = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 2 }));
    assert(b.status === 200, 'increasing');
    const dup = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 2 }));
    assert(dup.status === 422 && dup.body.error.code === 'SEQUENCE_VIOLATION', 'dup');
    const lower = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1 }));
    assert(
      lower.status === 422 && lower.body.error.code === 'SEQUENCE_VIOLATION',
      'lower',
    );
  });

  await test('18. new stream resets sequence', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 10, locationStreamId: 'stream-a' }));
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1, locationStreamId: 'stream-b' }));
    assert(res.status === 200, `got ${res.status}`);
    assert(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq === 1, 'reset');
    assert(
      db.getDoc('locationStreams', 'd1')?.activeStreamId === 'stream-b',
      'active',
    );
  });

  await test('19. old stream rejected', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1, locationStreamId: 'stream-a' }));
    await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1, locationStreamId: 'stream-b' }));
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 99, locationStreamId: 'stream-a' }));
    assert(res.status === 422, `got ${res.status}`);
    assert(res.body.error.code === 'SEQUENCE_VIOLATION', 'old stream');
  });

  await test('20-23. idle vs trip isolation', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    const idle = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 5, locationStreamId: 'idle-s' }));
    assert(idle.status === 200 && idle.body.data.mode === 'idle', 'idle');
    const trip = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(
        baseBody({
          rideId: 'ride-1',
          locationSeq: 1,
          locationStreamId: 'trip-s',
        }),
      );
    assert(trip.status === 200 && trip.body.data.mode === 'trip', 'trip');
    assert(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq === 5, 'idle doc');
    assert(
      db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq === 1,
      'trip doc',
    );
    const trip2 = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(
        baseBody({
          rideId: 'ride-2',
          locationSeq: 1,
          locationStreamId: 'trip-s2',
        }),
      );
    assert(trip2.status === 200, 'trip2');
    assert(
      db.getDoc('locationStreams', 'ride-1_d1')?.lastAcceptedSeq === 1,
      'ride1 intact',
    );
    assert(
      db.getDoc('locationStreams', 'ride-2_d1')?.lastAcceptedSeq === 1,
      'ride2',
    );
  });

  await test('24. body driverId cannot target another driver', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    seedApprovedOnline(db, 'd2');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ driverId: 'd2' }));
    assert(res.status === 200, '200');
    assert(res.body.data.driverId === 'd1', 'auth uid');
    assert(db.getDoc('locationStreams', 'd1') != null, 'd1 stream');
    assert(db.getDoc('locationStreams', 'd2') == null, 'd2 untouched');
  });

  await test('25. firestore.rules deny locationStreams client writes', async () => {
    const rules = readFileSync(
      resolve(process.cwd(), '../../firestore.rules'),
      'utf8',
    );
    const idx = rules.indexOf('match /locationStreams/{');
    assert(idx >= 0, 'match present');
    assert(
      /allow read,\s*write:\s*if false/.test(rules.slice(idx, idx + 180)),
      'deny',
    );
  });

  await test('26. concurrent same-sequence converge safely', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    const results = await Promise.all([
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 1 })),
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 1 })),
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 1 })),
    ]);
    const oks = results.filter((r) => r.status === 200);
    const conflicts = results.filter(
      (r) => r.status === 422 && r.body.error.code === 'SEQUENCE_VIOLATION',
    );
    assert(oks.length === 1, `exactly one accept got ${oks.length}`);
    assert(conflicts.length === 2, `two conflicts got ${conflicts.length}`);
    assert(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq === 1, 'cursor');
  });

  await test('27. concurrent ordered requests preserve monotonic cursor', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 1 }));
    const results = await Promise.all([
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 2 })),
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 3 })),
      request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(baseBody({ locationSeq: 4 })),
    ]);
    for (const r of results) {
      assert(r.status === 200, `got ${r.status}`);
    }
    assert(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq === 4, 'max');
  });

  await test('28-29. cursor persisted without GPS history', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    await request(appFor(db, 'd1'))
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(baseBody({ locationSeq: 7, lat: 31.1, lng: 74.2 }));
    const doc = db.getDoc('locationStreams', 'd1');
    assert(doc?.lastAcceptedSeq === 7, 'seq');
    assert(doc?.activeStreamId === 'stream-a', 'stream');
    assert(doc?.driverId === 'd1', 'driverId');
    assert(doc?.lat === undefined, 'no lat');
    assert(doc?.lng === undefined, 'no lng');
    assert(doc?.heading === undefined, 'no heading');
    assert(doc?.speed === undefined, 'no speed');
  });

  console.log(`\nN2A unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
