/**
 * Standalone N1 unit proof (MemoryDb — not live Firestore).
 * Usage: npm run test:phase-n1-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

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

function seedApprovedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  seedUser(db, uid, {
    role: 'driver',
    driverStatus: 'approved',
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

async function main(): Promise<void> {
  await test('1. unauthenticated go-online rejected', async () => {
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
    const res = await request(app).post('/v1/drivers/go-online').send({});
    assert(res.status === 401, `expected 401 got ${res.status}`);
    assert(res.body.error.code === 'UNAUTHENTICATED', 'code');
  });

  await test('2. passenger go-online rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', { role: 'passenger' });
    const res = await request(appFor(db, 'p1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 403, `expected 403 got ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_APPROVED', 'code');
    assert(db.getDoc('drivers', 'p1') === undefined, 'no drivers doc');
  });

  await test('3. unapproved driver go-online rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'd-pending', { role: 'driver', driverStatus: 'pending' });
    const res = await request(appFor(db, 'd-pending'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 403, `got ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_APPROVED', 'code');
  });

  await test('4. suspended driver go-online rejected', async () => {
    const db = memoryDb();
    seedUser(db, 'd-susp', { role: 'driver', driverStatus: 'suspended' });
    const res = await request(appFor(db, 'd-susp'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 403, `got ${res.status}`);
    assert(res.body.error.code === 'DRIVER_NOT_APPROVED', 'code');
  });

  await test('5. approved driver go-online succeeds', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 200, `got ${res.status}`);
    assert(res.body.data.driverId === 'd1', 'driverId');
    assert(res.body.data.availabilityState === 'online', 'online');
  });

  await test('6. approved driver go-offline succeeds', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      userId: 'd1',
      availabilityState: 'online',
    });
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 200, `got ${res.status}`);
    assert(res.body.data.availabilityState === 'offline', 'offline');
  });

  await test('7. offline → online', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(db.getDoc('drivers', 'd1')?.availabilityState === 'online', 'online');
  });

  await test('8. online → offline', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(
      db.getDoc('drivers', 'd1')?.availabilityState === 'offline',
      'offline',
    );
  });

  await test('9. repeated go-online idempotent', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    const a = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const firstUpdatedAt = db.getDoc('drivers', 'd1')?.updatedAt;
    const b = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(a.status === 200 && b.status === 200, 'both 200');
    assert(b.body.data.availabilityState === 'online', 'online');
    assert(db.getDoc('drivers', 'd1')?.updatedAt === firstUpdatedAt, 'no-op');
  });

  await test('10. repeated go-offline idempotent', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const off1 = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    const firstUpdatedAt = db.getDoc('drivers', 'd1')?.updatedAt;
    const off2 = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(off1.status === 200 && off2.status === 200, 'both 200');
    assert(off2.body.data.availabilityState === 'offline', 'offline');
    assert(db.getDoc('drivers', 'd1')?.updatedAt === firstUpdatedAt, 'no-op');
  });

  await test('11. client cannot select another driver', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    seedApprovedDriver(db, 'd2');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({ driverId: 'd2' });
    assert(res.status === 200, '200');
    assert(res.body.data.driverId === 'd1', 'auth uid');
    assert(db.getDoc('drivers', 'd1')?.availabilityState === 'online', 'd1');
    assert(db.getDoc('drivers', 'd2') === undefined, 'd2 untouched');
  });

  await test('12. client cannot force availabilityState via body', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const res = await request(appFor(db, 'd1'))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({ availabilityState: 'online' });
    assert(res.status === 200, '200');
    assert(res.body.data.availabilityState === 'offline', 'server state');
    assert(
      db.getDoc('drivers', 'd1')?.availabilityState === 'offline',
      'persisted',
    );
  });

  await test('12b. firestore.rules deny client writes to drivers', async () => {
    // Resolved from auth-service cwd (npm --prefix / npm run in package).
    const rulesPath = resolve(process.cwd(), '../../firestore.rules');
    const rules = readFileSync(rulesPath, 'utf8');
    const idx = rules.indexOf('match /drivers/{');
    assert(idx >= 0, 'drivers match present');
    const slice = rules.slice(idx, idx + 180);
    assert(/allow read,\s*write:\s*if false/.test(slice), 'deny write');
  });

  await test('13. concurrent go-online converge', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    const results = await Promise.all([
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-online')
        .set('Authorization', 'Bearer t')
        .send({}),
    ]);
    for (const res of results) {
      assert(res.status === 200, `got ${res.status}`);
      assert(res.body.data.availabilityState === 'online', 'online');
    }
    assert(db.getDoc('drivers', 'd1')?.availabilityState === 'online', 'final');
  });

  await test('14. concurrent go-offline converge', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const results = await Promise.all([
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
      request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({}),
    ]);
    for (const res of results) {
      assert(res.status === 200, `got ${res.status}`);
      assert(res.body.data.availabilityState === 'offline', 'offline');
    }
    assert(
      db.getDoc('drivers', 'd1')?.availabilityState === 'offline',
      'final',
    );
  });

  await test('15. Firestore persistence after mutations', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    assert(db.getDoc('drivers', 'd1') === undefined, 'starts absent');
    await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const online = db.getDoc('drivers', 'd1');
    assert(online?.availabilityState === 'online', 'online');
    assert(online?.driverId === 'd1', 'driverId');
    assert(online?.userId === 'd1', 'userId');
    assert(typeof online?.lastOnlineAt === 'string', 'lastOnlineAt');
    await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(
      db.getDoc('drivers', 'd1')?.availabilityState === 'offline',
      'offline',
    );
  });

  console.log(`\nN1 unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
