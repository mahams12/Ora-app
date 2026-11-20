/**
 * LIVE Firestore emulator query verification for Phase 2I ride list.
 *
 * Proves ownership isolation, filters, keyset pagination, and indexes against
 * real Admin SDK queries — not a concurrency contention harness.
 *
 * Requires FIRESTORE_EMULATOR_HOST.
 *
 * Usage:
 *   npm run test:ride-list-firestore-queries
 */
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';
import {
  encodeListCursor,
  ownerBinding,
} from '../src/rides/list_query';

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
): Promise<void> {
  await db.collection('users').doc(uid).set({
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role,
    driverStatus: role === 'driver' ? 'approved' : 'none',
    isActive: true,
    banned: false,
  });
}

async function seedRide(
  db: Firestore,
  overrides: Record<string, unknown>,
): Promise<string> {
  const rideId = (overrides.rideId as string) ?? `ride-${Date.now()}`;
  const createdAt =
    (overrides.createdAt as string) ?? new Date().toISOString();
  await db
    .collection('rides')
    .doc(rideId)
    .set({
      rideId,
      passengerId: 'p-live',
      assignedDriverId: null,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category: 'economy',
      serviceType: 'ride',
      pickup: { lat: 24.86, lng: 67.0 },
      destination: { lat: 24.9, lng: 67.1 },
      routePolyline: null,
      distanceKm: null,
      estimatedDurationMin: null,
      pricingSnapshotId: 'snap-live',
      recommendedFareMinor: 25000,
      passengerOfferMinor: 25000,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: null,
      paymentMethod: 'CASH',
      paymentIntentId: null,
      passengerCount: 1,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      assignedAt: null,
      startedAt: null,
      completedAt: null,
      closedAt: null,
      cancelledBy: null,
      cancellationReason: null,
      cancellationFeeMinor: null,
      createdAt,
      updatedAt: createdAt,
      ...overrides,
    });
  return rideId;
}

async function list(
  db: Firestore,
  uid: string,
  query: Record<string, string> = {},
) {
  return request(appFor(db, uid))
    .get('/v1/rides')
    .query(query)
    .set('Authorization', 'Bearer t');
}

async function main(): Promise<void> {
  requireEmulator();
  const app = initializeApp(
    getApps().length
      ? undefined
      : { projectId: process.env.GCLOUD_PROJECT || 'ora-app-d8112' },
  );
  const db = getFirestore(app);

  const suffix = `${Date.now()}`;
  const pA = `pA-${suffix}`;
  const pB = `pB-${suffix}`;
  const dA = `dA-${suffix}`;
  const dB = `dB-${suffix}`;

  await seedUser(db, pA, 'passenger');
  await seedUser(db, pB, 'passenger');
  await seedUser(db, dA, 'driver');
  await seedUser(db, dB, 'driver');

  await test('passenger isolation', async () => {
    await seedRide(db, {
      rideId: `ra-${suffix}`,
      passengerId: pA,
      createdAt: '2026-01-10T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `rb-${suffix}`,
      passengerId: pB,
      createdAt: '2026-01-11T00:00:00.000Z',
    });
    const res = await list(db, pA);
    assert(res.status === 200, `status ${res.status}`);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(ids.includes(`ra-${suffix}`), 'missing own ride');
    assert(!ids.includes(`rb-${suffix}`), 'foreign ride leaked');
  });

  await test('driver isolation and unassigned exclusion', async () => {
    await seedRide(db, {
      rideId: `search-${suffix}`,
      passengerId: pA,
      assignedDriverId: null,
      state: 'SEARCHING',
      createdAt: '2026-01-12T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `da-${suffix}`,
      passengerId: pA,
      assignedDriverId: dA,
      state: 'DRIVER_ASSIGNED',
      createdAt: '2026-01-13T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `db-${suffix}`,
      passengerId: pA,
      assignedDriverId: dB,
      state: 'DRIVER_EN_ROUTE',
      createdAt: '2026-01-14T00:00:00.000Z',
    });
    const res = await list(db, dA);
    assert(res.status === 200, `status ${res.status}`);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(ids.includes(`da-${suffix}`), 'missing assigned ride');
    assert(!ids.includes(`search-${suffix}`), 'unassigned leaked');
    assert(!ids.includes(`db-${suffix}`), 'other driver leaked');
  });

  await test('status filters completed/cancelled/EXPIRED', async () => {
    const p = `p-st-${suffix}`;
    await seedUser(db, p, 'passenger');
    await seedRide(db, {
      rideId: `done-${suffix}`,
      passengerId: p,
      state: 'RIDE_COMPLETED',
      assignedDriverId: dA,
      createdAt: '2026-02-01T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `closed-${suffix}`,
      passengerId: p,
      state: 'RIDE_CLOSED',
      assignedDriverId: dA,
      createdAt: '2026-02-02T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `cancel-${suffix}`,
      passengerId: p,
      state: 'CANCELLED',
      createdAt: '2026-02-03T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `expired-${suffix}`,
      passengerId: p,
      state: 'EXPIRED',
      createdAt: '2026-02-04T00:00:00.000Z',
    });

    const completed = await list(db, p, { status: 'completed' });
    assert(completed.status === 200, 'completed status');
    const cStates = completed.body.data.rides.map(
      (r: { state: string }) => r.state,
    );
    assert(
      cStates.every(
        (s: string) => s === 'RIDE_COMPLETED' || s === 'RIDE_CLOSED',
      ),
      'completed filter wrong',
    );
    assert(!cStates.includes('EXPIRED'), 'EXPIRED in completed');

    const cancelled = await list(db, p, { status: 'cancelled' });
    assert(cancelled.body.data.rides.length === 1, 'cancelled count');
    assert(
      cancelled.body.data.rides[0].state === 'CANCELLED',
      'cancelled state',
    );

    const all = await list(db, p, { status: 'all', limit: '50' });
    assert(
      all.body.data.rides.some(
        (r: { state: string }) => r.state === 'EXPIRED',
      ),
      'EXPIRED missing from all',
    );
  });

  await test('serviceType filter', async () => {
    const p = `p-svc-${suffix}`;
    await seedUser(db, p, 'passenger');
    await seedRide(db, {
      rideId: `svc-ride-${suffix}`,
      passengerId: p,
      serviceType: 'ride',
      createdAt: '2026-03-01T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `svc-courier-${suffix}`,
      passengerId: p,
      serviceType: 'courier',
      createdAt: '2026-03-02T00:00:00.000Z',
    });
    const res = await list(db, p, { serviceType: 'courier' });
    assert(res.status === 200, `status ${res.status}`);
    assert(res.body.data.rides.length === 1, 'courier count');
    assert(
      res.body.data.rides[0].serviceType === 'courier',
      'courier type',
    );
  });

  await test('identical timestamp tie-break + cursor pagination', async () => {
    const p = `p-page-${suffix}`;
    await seedUser(db, p, 'passenger');
    const ts = '2026-04-01T12:00:00.000Z';
    await seedRide(db, {
      rideId: `page-a-${suffix}`,
      passengerId: p,
      createdAt: ts,
    });
    await seedRide(db, {
      rideId: `page-m-${suffix}`,
      passengerId: p,
      createdAt: ts,
    });
    await seedRide(db, {
      rideId: `page-z-${suffix}`,
      passengerId: p,
      createdAt: ts,
    });

    const page1 = await list(db, p, { limit: '2' });
    assert(page1.status === 200, `page1 ${page1.status}`);
    const ids1 = page1.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(
      JSON.stringify(ids1) ===
        JSON.stringify([`page-z-${suffix}`, `page-m-${suffix}`]),
      `order ${ids1.join(',')}`,
    );
    assert(page1.body.data.nextCursor, 'missing nextCursor');

    const page2 = await list(db, p, {
      limit: '2',
      cursor: page1.body.data.nextCursor,
    });
    assert(page2.status === 200, `page2 ${page2.status}`);
    const ids2 = page2.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(
      JSON.stringify(ids2) === JSON.stringify([`page-a-${suffix}`]),
      `page2 order ${ids2.join(',')}`,
    );
    assert(page2.body.data.nextCursor === null, 'expected final page');

    const all = [...ids1, ...ids2];
    assert(new Set(all).size === all.length, 'duplicates across pages');
  });

  await test('cross-user cursor rejected; empty results; max limit', async () => {
    const p1 = `p-cur1-${suffix}`;
    const p2 = `p-cur2-${suffix}`;
    await seedUser(db, p1, 'passenger');
    await seedUser(db, p2, 'passenger');
    await seedRide(db, {
      rideId: `cur1-${suffix}`,
      passengerId: p1,
      createdAt: '2026-05-01T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `cur2-${suffix}`,
      passengerId: p1,
      createdAt: '2026-05-02T00:00:00.000Z',
    });

    const page = await list(db, p1, { limit: '1' });
    const stolen = await list(db, p2, {
      cursor: page.body.data.nextCursor,
    });
    assert(stolen.status === 400, 'cross-user cursor must fail');
    assert(
      stolen.body.error.code === 'VALIDATION_ERROR',
      'expected VALIDATION_ERROR',
    );

    const empty = await list(db, p2);
    assert(empty.status === 200, 'empty status');
    assert(empty.body.data.rides.length === 0, 'empty rides');
    assert(empty.body.data.nextCursor === null, 'empty cursor');

    const forgedCursor = encodeListCursor({
      createdAt: '2026-05-02T00:00:00.000Z',
      rideId: `cur2-${suffix}`,
      v: 1,
      ob: ownerBinding(p1, 'passenger'),
    });
    const forged = await list(db, p2, { cursor: forgedCursor });
    assert(forged.status === 400, 'forged owner binding must fail');

    const over = await list(db, p1, { limit: '51' });
    assert(over.status === 400, 'limit 51 rejected');
  });

  await test('forged ownership query params rejected', async () => {
    const res = await list(db, pA, { passengerId: pB });
    assert(res.status === 400, 'passengerId query rejected');
    const res2 = await list(db, dA, { driverId: dB });
    assert(res2.status === 400, 'driverId query rejected');
  });

  console.log(`\nPhase 2I live Firestore query results: ${passed} passed, ${failed} failed`);
  await deleteApp(app);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
