/**
 * LIVE Firestore emulator verification for Slice M0 open-ride discovery.
 *
 * Requires FIRESTORE_EMULATOR_HOST.
 *
 * Usage:
 *   npm run test:ride-open-discovery-firestore-queries
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
      pickup: { lat: 24.86, lng: 67.0, address: 'Pickup' },
      destination: { lat: 24.9, lng: 67.1, address: 'Dest' },
      routePolyline: 'SECRET',
      distanceKm: 5,
      estimatedDurationMin: 12,
      pricingSnapshotId: 'snap-live',
      recommendedFareMinor: 25000,
      passengerOfferMinor: 25000,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: { secret: true },
      paymentMethod: 'CASH',
      paymentIntentId: 'pi_secret',
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

async function listOpen(
  db: Firestore,
  uid: string,
  query: Record<string, string> = {},
) {
  return request(appFor(db, uid))
    .get('/v1/rides/open')
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
  const driverId = `d-open-${suffix}`;
  const passengerId = `p-open-${suffix}`;

  await seedUser(db, driverId, 'driver');
  await seedUser(db, passengerId, 'passenger');

  await test('eligible unassigned SEARCHING ride is discoverable', async () => {
    const rideId = `open-eligible-${suffix}`;
    await seedRide(db, {
      rideId,
      passengerId,
      state: 'SEARCHING',
      assignedDriverId: null,
      createdAt: '2026-06-01T00:00:00.000Z',
    });
    const res = await listOpen(db, driverId);
    assert(res.status === 200, `status ${res.status}`);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(ids.includes(rideId), 'eligible ride missing');
    const ride = res.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === rideId,
    );
    assert(ride.requestVersion === 1, 'requestVersion missing');
    assert(!('passengerId' in ride), 'passengerId leaked');
    assert(!('pricingSnapshotId' in ride), 'pricingSnapshotId leaked');
  });

  await test('assigned, terminal, and expired rides excluded', async () => {
    await seedRide(db, {
      rideId: `open-assigned-${suffix}`,
      passengerId,
      assignedDriverId: `d-other-${suffix}`,
      state: 'DRIVER_ASSIGNED',
      createdAt: '2026-06-02T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `open-cancelled-${suffix}`,
      passengerId,
      state: 'CANCELLED',
      assignedDriverId: null,
      createdAt: '2026-06-03T00:00:00.000Z',
    });
    await seedRide(db, {
      rideId: `open-expired-${suffix}`,
      passengerId,
      state: 'SEARCHING',
      assignedDriverId: null,
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
      createdAt: '2026-06-04T00:00:00.000Z',
    });
    const res = await listOpen(db, driverId, { limit: '50' });
    assert(res.status === 200, `status ${res.status}`);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    assert(!ids.includes(`open-assigned-${suffix}`), 'assigned leaked');
    assert(!ids.includes(`open-cancelled-${suffix}`), 'cancelled leaked');
    assert(!ids.includes(`open-expired-${suffix}`), 'expired leaked');
  });

  await test('pagination against live Firestore', async () => {
    const ts = '2026-06-10T12:00:00.000Z';
    const pageIds = [
      `page-a-${suffix}`,
      `page-b-${suffix}`,
      `page-c-${suffix}`,
    ];
    for (const rideId of pageIds) {
      await seedRide(db, {
        rideId,
        passengerId,
        createdAt: ts,
      });
    }
    const page1 = await listOpen(db, driverId, { limit: '2' });
    assert(page1.status === 200, 'page1 status');
    assert(page1.body.data.rides.length === 2, 'page1 count');
    assert(page1.body.data.nextCursor, 'page1 cursor');
    const page2 = await listOpen(db, driverId, {
      limit: '2',
      cursor: page1.body.data.nextCursor,
    });
    assert(page2.status === 200, 'page2 status');
    const all = [
      ...page1.body.data.rides.map((r: { rideId: string }) => r.rideId),
      ...page2.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ];
    assert(new Set(all).size === all.length, 'duplicate page entries');
    const pagedSet = new Set(
      all.filter((id) => pageIds.includes(id)),
    );
    assert(pagedSet.size === 3, 'expected three seeded rides across pages');
    assert(
      [...pagedSet].sort().join(',') === pageIds.sort().join(','),
      'pagination missed seeded rides',
    );
  });

  await deleteApp(app);
  console.log(`\nSlice M0 live proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
