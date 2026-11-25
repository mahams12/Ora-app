/**
 * DR-008 / A7 — REAL Firestore emulator concurrency proof for the
 * one-active-ride-per-passenger pointer.
 *
 * memoryDb cannot simulate Firestore optimistic-concurrency retries;
 * this script drives the production RideService.createRide /
 * cancelRide transactions against the local emulator:
 *
 *   1. Sequential guard: create → second create → ACTIVE_RIDE_EXISTS
 *   2. 20-way concurrent createRide, distinct idempotency keys:
 *      exactly 1 succeeds (201), 19 rejected ACTIVE_RIDE_EXISTS,
 *      exactly 1 active ride doc, pointer → winner
 *   3. 10-way concurrent createRide, SAME idempotency key:
 *      all replay the same ride (no 409, no duplicates)
 *   4. Create-vs-cancel at the terminal boundary: final state must be
 *      consistent — at most one active ride and a pointer that matches
 *
 * Run:
 *   firebase emulators:start --only firestore --project ora-local-bench &
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8181 \
 *   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *   FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000 \
 *   npx tsx scripts/run_active_ride_guard_emulator_proof.ts
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { assertScriptFirebaseTarget } from './lib/script_env';
import { RideService } from '../src/rides/ride_service';
import { RideDomainError } from '../src/rides/types';
import {
  ACTIVE_RIDE_STATES,
  PASSENGER_ACTIVE_RIDES_COLLECTION,
} from '../src/rides/active_ride_pointer';

const PREFIX = 'arg_';
let passed = 0;
let failed = 0;

function ok(name: string, cond: boolean, detail = '') {
  if (cond) {
    passed++;
    console.log(`  PASS ${name}`);
  } else {
    failed++;
    console.log(`  FAIL ${name} ${detail}`);
  }
}

const caller = (uid: string) => ({
  uid,
  phoneNumber: '+923001234567',
  email: null,
  disabled: false,
});

const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  city: 'Karachi',
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-arg',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

async function seed(db: FirebaseFirestore.Firestore) {
  await db.collection('users').doc(`${PREFIX}p1`).set({
    uid: `${PREFIX}p1`,
    role: 'passenger',
    isActive: true,
    banned: false,
  });
  await db.collection('users').doc(`${PREFIX}p2`).set({
    uid: `${PREFIX}p2`,
    role: 'passenger',
    isActive: true,
    banned: false,
  });
  await db.collection('pricingSnapshots').doc('snap-arg').set({
    snapshotId: 'snap-arg',
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
    inputs: { distanceKm: 5.2, durationMin: 18 },
  });
}

async function cleanup(db: FirebaseFirestore.Firestore) {
  const cols = [
    'users',
    'rides',
    'idempotencyRecords',
    'outboxEvents',
    PASSENGER_ACTIVE_RIDES_COLLECTION,
  ];
  for (const col of cols) {
    const snap = await db.collection(col).get();
    const batch = db.batch();
    for (const d of snap.docs) {
      if (d.id.startsWith(PREFIX)) batch.delete(d.ref);
    }
    await batch.commit();
  }
  await db.collection('pricingSnapshots').doc('snap-arg').delete();
}

function isActiveRideConflict(err: unknown): boolean {
  return (
    err instanceof RideDomainError && err.code === 'ACTIVE_RIDE_EXISTS'
  );
}

async function activeRideCount(
  db: FirebaseFirestore.Firestore,
  passengerId: string,
): Promise<number> {
  const snap = await db
    .collection('rides')
    .where('passengerId', '==', passengerId)
    .where('state', 'in', [...ACTIVE_RIDE_STATES])
    .get();
  return snap.size;
}

async function main() {
  assertScriptFirebaseTarget(process.env);
  initializeApp({ projectId: 'ora-local-bench' });
  const db = getFirestore();
  const svc = new RideService(db);

  await cleanup(db);
  await seed(db);

  const p1 = `${PREFIX}p1`;
  const p2 = `${PREFIX}p2`;

  // ── 1. Sequential guard ───────────────────────────────────────────────
  console.log('\n[1] sequential: create → second create → 409');
  let firstRideId = '';
  {
    const r1 = await svc.createRide({
      caller: caller(p1),
      body: createBody,
      idempotencyKeyHeader: `${PREFIX}idem-seq-1`,
      correlationId: 'arg-seq',
    });
    ok('first create 201', r1.httpStatus === 201, String(r1.httpStatus));
    firstRideId = (r1.body as { data: { rideId: string } }).data.rideId;

    const ptr = (
      await db
        .collection(PASSENGER_ACTIVE_RIDES_COLLECTION)
        .doc(p1)
        .get()
    ).data() as { activeRideId?: string } | undefined;
    ok('pointer acquired', ptr?.activeRideId === firstRideId, JSON.stringify(ptr));

    let conflict: RideDomainError | null = null;
    try {
      await svc.createRide({
        caller: caller(p1),
        body: createBody,
        idempotencyKeyHeader: `${PREFIX}idem-seq-2`,
        correlationId: 'arg-seq2',
      });
    } catch (e) {
      conflict = e as RideDomainError;
    }
    ok(
      'second create → ACTIVE_RIDE_EXISTS 409',
      conflict?.code === 'ACTIVE_RIDE_EXISTS' && conflict?.httpStatus === 409,
      conflict ? `${conflict.code}/${conflict.httpStatus}` : 'no error',
    );
    const details = conflict?.details as { activeRideId?: string } | undefined;
    ok('409 carries activeRideId', details?.activeRideId === firstRideId);
  }

  // ── 2. 20-way concurrent create, distinct idem keys ──────────────────
  console.log('\n[2] 20 concurrent createRide — distinct idempotency keys');
  {
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, (_, i) =>
        svc.createRide({
          caller: caller(p2),
          body: createBody,
          idempotencyKeyHeader: `${PREFIX}idem-c${i}`,
          correlationId: `arg-c${i}`,
        }),
      ),
    );
    const won = results.filter(
      (r) => r.status === 'fulfilled' && r.value.httpStatus === 201,
    );
    const lost = results.filter(
      (r) =>
        r.status === 'rejected' && isActiveRideConflict(r.reason),
    );
    const other = results.length - won.length - lost.length;
    ok('exactly 1 winner (201)', won.length === 1, `won=${won.length}`);
    ok('exactly 19 ACTIVE_RIDE_EXISTS', lost.length === 19, `lost=${lost.length}`);
    ok('no unexpected outcomes', other === 0, `other=${other}`);

    const winnerRideId = won.length
      ? (won[0] as PromiseFulfilledResult<{ body: { data: { rideId: string } } }>)
          .value.body.data.rideId
      : '';
    const count = await activeRideCount(db, p2);
    ok('exactly 1 active ride doc', count === 1, `count=${count}`);
    const ptr = (
      await db
        .collection(PASSENGER_ACTIVE_RIDES_COLLECTION)
        .doc(p2)
        .get()
    ).data() as { activeRideId?: string } | undefined;
    ok('pointer → winning ride', ptr?.activeRideId === winnerRideId);
    const rideSnap = await db.collection('rides').doc(winnerRideId).get();
    ok('winner ride exists SEARCHING', rideSnap.data()?.state === 'SEARCHING');
    console.log(`    winner=${winnerRideId}`);
  }

  // ── 3. Same-key concurrent replay ─────────────────────────────────────
  console.log('\n[3] 10 concurrent createRide — SAME idempotency key');
  {
    // Fresh passenger p3 for a clean idem space.
    await db.collection('users').doc(`${PREFIX}p3`).set({
      uid: `${PREFIX}p3`,
      role: 'passenger',
      isActive: true,
      banned: false,
    });
    const p3 = `${PREFIX}p3`;
    const results = await Promise.allSettled(
      Array.from({ length: 10 }, () =>
        svc.createRide({
          caller: caller(p3),
          body: createBody,
          idempotencyKeyHeader: `${PREFIX}idem-same`,
          correlationId: 'arg-same',
        }),
      ),
    );
    const statuses = results.map((r) =>
      r.status === 'fulfilled' ? r.value.httpStatus : 'rejected',
    );
    const rideIds = new Set(
      results
        .filter(
          (
            r,
          ): r is PromiseFulfilledResult<{
            httpStatus: number;
            body: unknown;
          }> => r.status === 'fulfilled',
        )
        .map(
          (r) =>
            (r.value.body as { data: { rideId: string } }).data.rideId,
        ),
    );
    ok(
      'all 10 return 201 same ride (idempotent replay)',
      statuses.every((s) => s === 201) && rideIds.size === 1,
      JSON.stringify(statuses),
    );
    const count = await activeRideCount(db, p3);
    ok('still exactly 1 active ride', count === 1, `count=${count}`);
  }

  // ── 4. Create vs cancel at terminal boundary ──────────────────────────
  console.log('\n[4] concurrent create vs cancel — terminal boundary');
  {
    // p1 already has firstRideId active from step 1.
    const cancelP = svc.cancelRide({
      caller: caller(p1),
      rideId: firstRideId,
      body: {},
      idempotencyKeyHeader: `${PREFIX}idem-cancel-1`,
      correlationId: 'arg-cancel',
    });
    const createP = svc.createRide({
      caller: caller(p1),
      body: createBody,
      idempotencyKeyHeader: `${PREFIX}idem-boundary-1`,
      correlationId: 'arg-boundary',
    });
    const [cancelRes, createRes] = await Promise.allSettled([cancelP, createP]);

    const cancelOk =
      cancelRes.status === 'fulfilled' && cancelRes.value.httpStatus === 200;
    const createWon =
      createRes.status === 'fulfilled' && createRes.value.httpStatus === 201;
    const createConflict =
      createRes.status === 'rejected' &&
      isActiveRideConflict(createRes.reason);
    ok(
      'cancel succeeded OR create conflicted — no corruption',
      cancelOk && (createWon || createConflict),
      `cancel=${cancelRes.status} create=${createRes.status}`,
    );

    // Invariant: at most one active ride; pointer consistent.
    const count = await activeRideCount(db, p1);
    ok('≤1 active ride after race', count <= 1, `count=${count}`);
    const ptr = (
      await db
        .collection(PASSENGER_ACTIVE_RIDES_COLLECTION)
        .doc(p1)
        .get()
    ).data() as { activeRideId?: string } | undefined;
    if (ptr?.activeRideId) {
      const pointed = await db
        .collection('rides')
        .doc(ptr.activeRideId)
        .get();
      ok(
        'pointer references an active ride',
        ACTIVE_RIDE_STATES.includes(String(pointed.data()?.state)),
        `state=${pointed.data()?.state}`,
      );
    } else {
      ok('no pointer when no active ride', count === 0, `count=${count}`);
    }
    console.log(
      `    cancel=${cancelRes.status === 'fulfilled' ? cancelRes.value.httpStatus : 'err'} ` +
        `create=${createRes.status === 'fulfilled' ? createRes.value.httpStatus : (createRes.reason as RideDomainError)?.code ?? 'err'}`,
    );
  }

  await cleanup(db);
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
