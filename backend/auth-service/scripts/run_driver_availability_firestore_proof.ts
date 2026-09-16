/**
 * LIVE Firestore emulator verification for N1 driver availability.
 *
 * Requires FIRESTORE_EMULATOR_HOST.
 *
 * Usage:
 *   npm run test:driver-availability-firestore
 */
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';

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

function requireEmulator(): void {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      'FIRESTORE_EMULATOR_HOST is not set. Run via firebase emulators:exec.',
    );
  }
}

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
  } as never;
}

function appFor(db: Firestore, uid: string) {
  return createApp({
    auth: authFor(uid),
    db,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 100_000 },
  });
}

async function seedUser(
  db: Firestore,
  uid: string,
  role: 'passenger' | 'driver',
  driverStatus: string = 'approved',
): Promise<void> {
  await db.collection('users').doc(uid).set({
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role,
    driverStatus: role === 'driver' ? driverStatus : 'none',
    isActive: true,
    banned: false,
  });
}

async function main(): Promise<void> {
  requireEmulator();

  const appName = `n1-avail-${Date.now()}`;
  const fbApp = initializeApp({ projectId: 'ora-n1-avail' }, appName);
  const db = getFirestore(fbApp);
  db.settings({ ignoreUndefinedProperties: true });

  const suffix = `${Date.now()}-${Math.floor(Math.random() * 1e6)}`;
  const driverId = `drv-n1-${suffix}`;
  const passengerId = `pax-n1-${suffix}`;
  const pendingId = `pend-n1-${suffix}`;

  await seedUser(db, driverId, 'driver', 'approved');
  await seedUser(db, passengerId, 'passenger');
  await seedUser(db, pendingId, 'driver', 'pending');

  // Seed an unrelated ride to prove it is untouched.
  const rideId = `ride-n1-${suffix}`;
  await db.collection('rides').doc(rideId).set({
    rideId,
    state: 'SEARCHING',
    passengerId: passengerId,
    createdAt: new Date().toISOString(),
    sentinel: 'untouched-by-n1',
  });

  await test('1. approved driver starts with no drivers doc (offline)', async () => {
    const snap = await db.collection('drivers').doc(driverId).get();
    assert(!snap.exists, 'drivers doc must not exist initially');
  });

  await test('2. authenticated go-online', async () => {
    const res = await request(appFor(db, driverId))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 200, `expected 200 got ${res.status}`);
    assert(res.body.data.availabilityState === 'online', 'state online');
    assert(res.body.data.driverId === driverId, 'driverId matches auth');
  });

  await test('3. Firestore shows ONLINE', async () => {
    const snap = await db.collection('drivers').doc(driverId).get();
    assert(snap.exists, 'drivers doc exists');
    assert(snap.data()?.availabilityState === 'online', 'availabilityState online');
    assert(snap.data()?.driverId === driverId, 'driverId field');
    assert(typeof snap.data()?.lastOnlineAt === 'string', 'lastOnlineAt set');
  });

  await test('4. authenticated go-offline', async () => {
    const res = await request(appFor(db, driverId))
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(res.status === 200, `expected 200 got ${res.status}`);
    assert(res.body.data.availabilityState === 'offline', 'state offline');
  });

  await test('5. Firestore shows OFFLINE', async () => {
    const snap = await db.collection('drivers').doc(driverId).get();
    assert(snap.exists, 'drivers doc exists');
    assert(
      snap.data()?.availabilityState === 'offline',
      'availabilityState offline',
    );
  });

  await test('6. unauthorized actors cannot transition', async () => {
    const pax = await request(appFor(db, passengerId))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(pax.status === 403, `passenger expected 403 got ${pax.status}`);
    assert(pax.body.error.code === 'DRIVER_NOT_APPROVED', 'passenger code');

    const pend = await request(appFor(db, pendingId))
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(pend.status === 403, `pending expected 403 got ${pend.status}`);
    assert(pend.body.error.code === 'DRIVER_NOT_APPROVED', 'pending code');

    const after = await db.collection('drivers').doc(driverId).get();
    assert(
      after.data()?.availabilityState === 'offline',
      'driver state unchanged by unauthorized',
    );
  });

  await test('7. repeated mutation is safe', async () => {
    const app = appFor(db, driverId);
    const a = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    const b = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(a.status === 200 && b.status === 200, 'both online ok');
    const c = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    const d = await request(app)
      .post('/v1/drivers/go-offline')
      .set('Authorization', 'Bearer t')
      .send({});
    assert(c.status === 200 && d.status === 200, 'both offline ok');
    const snap = await db.collection('drivers').doc(driverId).get();
    assert(snap.data()?.availabilityState === 'offline', 'final offline');
  });

  await test('8. unrelated ride/offer data unchanged', async () => {
    const ride = await db.collection('rides').doc(rideId).get();
    assert(ride.exists, 'ride still exists');
    assert(ride.data()?.sentinel === 'untouched-by-n1', 'ride sentinel');
    assert(ride.data()?.state === 'SEARCHING', 'ride state unchanged');
  });

  console.log(`\nN1 live proof: ${passed} passed, ${failed} failed`);
  await deleteApp(fbApp);
  if (getApps().length === 0) {
    /* noop */
  }
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
