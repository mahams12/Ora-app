/**
 * N4 — Dispatch wave MVP focused unit tests.
 */
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { createMemoryRedis } from '../redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../redis/types';
import {
  N4_MAX_TOTAL_INVITES,
  N4_RADIUS_KM,
  N4_WAVE_CADENCE_MS,
  N4_WAVE_SIZES,
  waveDocId,
} from '../rides/dispatch_types';

const WORKER = 'test-worker-token-n4-xxxx';
const PICKUP = { lat: 31.52, lng: 74.35 };

function authStub() {
  return {
    verifyIdToken: async () => ({ uid: 'unused', phone_number: '+100' }),
  } as never;
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  redis: RedisGeoClient | null,
) {
  return createApp({
    auth: authStub(),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    redis,
  });
}

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  homeCity: string | null = 'lahore',
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
    ...(homeCity != null ? { homeCity } : {}),
  });
}

async function seedGeo(
  redis: ReturnType<typeof createMemoryRedis>,
  driverId: string,
  lng: number,
  lat: number,
  marker: Partial<DriverOnlineMarker> & { lastLocationTs: number },
) {
  await redis.geoadd(GEO_DRIVERS_KEY, lng, lat, driverId);
  const full: DriverOnlineMarker = {
    driverId,
    accuracy: 8,
    city: marker.city ?? null,
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date().toISOString(),
    ...marker,
  };
  await redis.set(
    driverOnlineKey(driverId),
    JSON.stringify(full),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

/** Place drivers at increasing distance east of pickup (~0.1° ≈ 11km at equator; use smaller steps). */
async function seedDriversNearPickup(
  db: ReturnType<typeof memoryDb>,
  redis: ReturnType<typeof createMemoryRedis>,
  count: number,
  nowMs: number,
  prefix = 'd',
): Promise<string[]> {
  const ids: string[] = [];
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}${i}`;
    ids.push(id);
    seedApprovedOnline(db, id, i % 2 === 0 ? 'lahore' : null);
    // ~0.001° lat ≈ 111m — keep all well within 10km
    await seedGeo(redis, id, PICKUP.lng + i * 0.001, PICKUP.lat, {
      lastLocationTs: nowMs,
      accuracy: 5,
    });
  }
  return ids;
}

function seedDispatchableRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  const now = Date.now();
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: null,
    state: 'SEARCHING',
    version: 1,
    requestVersion: 1,
    category: 'zip',
    serviceType: 'ride',
    pickup: { ...PICKUP, address: 'A' },
    destination: { lat: 31.53, lng: 74.36, address: 'B' },
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
    ...overrides,
  });
}

async function tick(
  app: ReturnType<typeof createApp>,
  rideId: string,
  expectStatus = 200,
) {
  return request(app)
    .post(`/v1/internal/rides/${rideId}/dispatch-tick`)
    .set('X-Ora-Worker-Token', WORKER)
    .expect(expectStatus);
}

describe('N4 dispatch wave MVP', () => {
  it('wave 1 invites up to 5 candidates by distance ASC using pickup lat/lng (no city)', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    const ids = await seedDriversNearPickup(db, redis, 8, now);
    seedDispatchableRide(db, 'r1');
    // city metadata intentionally missing on ride
    const app = appFor(db, redis);

    const res = await tick(app, 'r1');
    expect(res.body.data.outcome).toBe('wave_completed');
    expect(res.body.data.waveNumber).toBe(1);
    expect(res.body.data.invitedCount).toBe(5);
    expect(res.body.data.driverIds).toEqual(ids.slice(0, 5));

    const wave = db.getDoc('rideDispatchWaves', waveDocId('r1', 1));
    expect(wave).toBeTruthy();
    expect(wave!.radiusKm).toBe(N4_RADIUS_KM);
    expect(wave!.driverIds).toEqual(ids.slice(0, 5));
    expect(wave!.requestVersion).toBe(1);

    const ride = db.getDoc('rides', 'r1')!;
    expect(ride.dispatchWave).toBe(1);
    expect(ride.dispatchStatus).toBe('active');
    expect(typeof ride.dispatchNextAt).toBe('string');

    // No offers fabricated
    for (const [path] of db.store.entries()) {
      expect(path.startsWith('rideOffers/')).toBe(false);
    }
    expect(ride.assignedDriverId).toBeNull();
  });

  it('wave 2 invites up to 10 NEW candidates; wave 3 up to 15 NEW; never exceeds 30', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    const ids = await seedDriversNearPickup(db, redis, 40, now);
    seedDispatchableRide(db, 'r2');
    const app = appFor(db, redis);

    const w1 = await tick(app, 'r2');
    expect(w1.body.data.invitedCount).toBe(N4_WAVE_SIZES[0]);
    expect(w1.body.data.driverIds).toEqual(ids.slice(0, 5));

    // Advance clock past cadence
    const rideAfter1 = db.getDoc('rides', 'r2')!;
    const nextAt1 = Date.parse(String(rideAfter1.dispatchNextAt));
    db.seed('rides', 'r2', {
      ...rideAfter1,
      // keep fields; tick uses Date.now() — patch dispatchNextAt to past
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });

    const w2 = await tick(app, 'r2');
    expect(w2.body.data.outcome).toBe('wave_completed');
    expect(w2.body.data.waveNumber).toBe(2);
    expect(w2.body.data.invitedCount).toBe(N4_WAVE_SIZES[1]);
    expect(w2.body.data.driverIds).toEqual(ids.slice(5, 15));
    // no overlap with wave 1
    for (const id of w2.body.data.driverIds as string[]) {
      expect(w1.body.data.driverIds).not.toContain(id);
    }

    db.seed('rides', 'r2', {
      ...db.getDoc('rides', 'r2')!,
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });

    const w3 = await tick(app, 'r2');
    expect(w3.body.data.outcome).toBe('wave_completed');
    expect(w3.body.data.waveNumber).toBe(3);
    expect(w3.body.data.invitedCount).toBe(N4_WAVE_SIZES[2]);
    expect(w3.body.data.driverIds).toEqual(ids.slice(15, 30));

    const all = [
      ...(w1.body.data.driverIds as string[]),
      ...(w2.body.data.driverIds as string[]),
      ...(w3.body.data.driverIds as string[]),
    ];
    expect(all.length).toBe(N4_MAX_TOTAL_INVITES);
    expect(new Set(all).size).toBe(N4_MAX_TOTAL_INVITES);

    const ride = db.getDoc('rides', 'r2')!;
    expect(ride.dispatchWave).toBe(3);
    expect(ride.dispatchStatus).toBe('exhausted');
    expect(ride.dispatchNextAt).toBeNull();

    // Fourth tick must not invite more
    const w4 = await tick(app, 'r2');
    expect(w4.body.data.outcome).toBe('exhausted');
    expect(db.getDoc('rideDispatchWaves', waveDocId('r2', 4))).toBeUndefined();

    void nextAt1;
  });

  it('deduplicates drivers that reappear across N3 responses', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    // Only 5 drivers total — wave 1 takes all; wave 2 must invite 0 new
    const ids = await seedDriversNearPickup(db, redis, 5, now);
    seedDispatchableRide(db, 'r3');
    const app = appFor(db, redis);

    const w1 = await tick(app, 'r3');
    expect(w1.body.data.driverIds).toEqual(ids);

    db.seed('rides', 'r3', {
      ...db.getDoc('rides', 'r3')!,
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });

    const w2 = await tick(app, 'r3');
    expect(w2.body.data.outcome).toBe('wave_completed');
    expect(w2.body.data.waveNumber).toBe(2);
    expect(w2.body.data.invitedCount).toBe(0);
    expect(w2.body.data.driverIds).toEqual([]);
  });

  it('repeated worker tick is idempotent (create-once wave doc)', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 5, now);
    seedDispatchableRide(db, 'r4');
    const app = appFor(db, redis);

    const first = await tick(app, 'r4');
    expect(first.body.data.outcome).toBe('wave_completed');

    // Concurrent retry that still sees wave-0 cursor but wave doc exists.
    db.seed('rides', 'r4', {
      ...db.getDoc('rides', 'r4')!,
      dispatchWave: 0,
      dispatchNextAt: null,
      dispatchStatus: 'none',
    });

    const second = await tick(app, 'r4');
    expect(second.body.data.outcome).toBe('already_completed');
    expect(second.body.data.driverIds).toEqual(first.body.data.driverIds);

    let waveDocs = 0;
    for (const [path] of db.store.entries()) {
      if (path.startsWith('rideDispatchWaves/')) waveDocs += 1;
    }
    expect(waveDocs).toBe(1);
  });

  it('assigned ride stops further dispatch', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 10, now);
    seedDispatchableRide(db, 'r5');
    const app = appFor(db, redis);

    await tick(app, 'r5');
    db.seed('rides', 'r5', {
      ...db.getDoc('rides', 'r5')!,
      state: 'DRIVER_ASSIGNED',
      assignedDriverId: 'd0',
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });

    const res = await tick(app, 'r5');
    expect(res.body.data.outcome).toBe('stopped');
    expect(db.getDoc('rideDispatchWaves', waveDocId('r5', 2))).toBeUndefined();
    expect(db.getDoc('rides', 'r5')!.dispatchStatus).toBe('stopped');
  });

  it('cancelled ride stops further dispatch', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 10, now);
    seedDispatchableRide(db, 'r6');
    const app = appFor(db, redis);

    await tick(app, 'r6');
    db.seed('rides', 'r6', {
      ...db.getDoc('rides', 'r6')!,
      state: 'CANCELLED',
      cancelledBy: 'passenger',
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });

    const res = await tick(app, 'r6');
    expect(res.body.data.outcome).toBe('stopped');
    expect(db.getDoc('rideDispatchWaves', waveDocId('r6', 2))).toBeUndefined();
  });

  it('expired ride stops further dispatch', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 10, now);
    seedDispatchableRide(db, 'r7', {
      expiresAt: new Date(now - 1000).toISOString(),
    });
    const app = appFor(db, redis);

    const res = await tick(app, 'r7');
    expect(res.body.data.outcome).toBe('stopped');
    expect(db.getDoc('rideDispatchWaves', waveDocId('r7', 1))).toBeUndefined();
  });

  it('skips candidate that becomes ineligible between N3 and invite', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    const ids = await seedDriversNearPickup(db, redis, 6, now);
    seedDispatchableRide(db, 'r8');

    const { DispatchWaveService } = await import(
      '../rides/dispatch_wave_service'
    );
    const { NearbyDriversService } = await import('../drivers/nearby_service');
    const nearby = new NearbyDriversService(db as never, redis);
    const originalRevalidate = nearby.isStillEligibleForInvite.bind(nearby);
    let revalidateCalls = 0;
    nearby.isStillEligibleForInvite = async (driverId, opts) => {
      revalidateCalls += 1;
      // First candidate appears eligible in N3 then fails revalidation.
      if (driverId === ids[0]) return false;
      return originalRevalidate(driverId, opts);
    };
    const dispatch = new DispatchWaveService(db as never, nearby);
    const result = await dispatch.tickRide({
      rideId: 'r8',
      correlationId: 'corr-skip',
      nowMs: now,
    });
    expect(result.outcome).toBe('wave_completed');
    expect(result.driverIds).not.toContain(ids[0]);
    expect(result.invitedCount).toBe(5);
    expect(result.driverIds).toEqual(ids.slice(1, 6));
    expect(revalidateCalls).toBeGreaterThan(0);
  });

  it('aborts wave commit on requestVersion mismatch (concurrency)', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 5, now);
    seedDispatchableRide(db, 'r9');
    const app = appFor(db, redis);

    // Intercept: first call findNearby, then bump requestVersion before tick's txn.
    // Simpler: run tick after bumping version mid-flight via service-level test.
    // Use DispatchWaveService directly with a nearby that mutates ride mid-call.
    const { DispatchWaveService } = await import(
      '../rides/dispatch_wave_service'
    );
    const { NearbyDriversService } = await import('../drivers/nearby_service');
    const nearby = new NearbyDriversService(db as never, redis);
    const original = nearby.findNearby.bind(nearby);
    nearby.findNearby = async (input) => {
      const result = await original(input);
      db.seed('rides', 'r9', {
        ...db.getDoc('rides', 'r9')!,
        requestVersion: 2,
      });
      return result;
    };
    const dispatch = new DispatchWaveService(db as never, nearby);
    const result = await dispatch.tickRide({
      rideId: 'r9',
      correlationId: 'corr-rv',
      nowMs: now,
    });
    expect(result.outcome).toBe('skipped');
    expect(result.reason).toBe('request_version_mismatch');
    expect(db.getDoc('rideDispatchWaves', waveDocId('r9', 1))).toBeUndefined();
    void app;
  });

  it('does not require city; uses pickup coordinates for N3', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 3, now);
    seedDispatchableRide(db, 'r10'); // no city field
    const app = appFor(db, redis);

    const res = await tick(app, 'r10');
    expect(res.body.data.outcome).toBe('wave_completed');
    expect(res.body.data.invitedCount).toBe(3);

    const wave = db.getDoc('rideDispatchWaves', waveDocId('r10', 1))!;
    expect(wave.radiusKm).toBe(10);
    expect(Object.prototype.hasOwnProperty.call(wave, 'city')).toBe(false);
  });

  it('does not auto-assign or fabricate/auto-accept offers', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 5, now);
    seedDispatchableRide(db, 'r11');
    const app = appFor(db, redis);

    await tick(app, 'r11');
    const ride = db.getDoc('rides', 'r11')!;
    expect(ride.assignedDriverId).toBeNull();
    expect(ride.state).toBe('SEARCHING');
    expect(ride.agreedOfferId).toBeNull();

    let offerCount = 0;
    for (const [path] of db.store.entries()) {
      if (path.startsWith('rideOffers/')) offerCount += 1;
    }
    expect(offerCount).toBe(0);
  });

  it('worker endpoint requires X-Ora-Worker-Token', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedDispatchableRide(db, 'r12');
    const app = appFor(db, redis);

    await request(app)
      .post('/v1/internal/rides/r12/dispatch-tick')
      .expect(403);

    await request(app)
      .post('/v1/internal/rides/dispatch-sweep')
      .expect(403);

    await request(app)
      .post('/v1/internal/rides/dispatch-sweep')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
  });

  it('handles N3 under-fill safely without assuming 30 candidates', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 2, now);
    seedDispatchableRide(db, 'r13');
    const app = appFor(db, redis);

    const w1 = await tick(app, 'r13');
    expect(w1.body.data.outcome).toBe('wave_completed');
    expect(w1.body.data.invitedCount).toBe(2);

    db.seed('rides', 'r13', {
      ...db.getDoc('rides', 'r13')!,
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });
    const w2 = await tick(app, 'r13');
    expect(w2.body.data.outcome).toBe('wave_completed');
    expect(w2.body.data.invitedCount).toBe(0);

    db.seed('rides', 'r13', {
      ...db.getDoc('rides', 'r13')!,
      dispatchNextAt: new Date(Date.now() - 1000).toISOString(),
    });
    const w3 = await tick(app, 'r13');
    expect(w3.body.data.outcome).toBe('wave_completed');
    expect(w3.body.data.invitedCount).toBe(0);
    expect(db.getDoc('rides', 'r13')!.dispatchStatus).toBe('exhausted');
  });

  it('respects 5-second cadence (not_due before dispatchNextAt)', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 10, now);
    seedDispatchableRide(db, 'r14');
    const app = appFor(db, redis);

    await tick(app, 'r14');
    const ride = db.getDoc('rides', 'r14')!;
    const nextMs = Date.parse(String(ride.dispatchNextAt));
    expect(nextMs - Date.now()).toBeGreaterThan(0);
    expect(nextMs - now).toBeLessThanOrEqual(N4_WAVE_CADENCE_MS + 2000);

    const again = await tick(app, 'r14');
    expect(again.body.data.outcome).toBe('not_due');
    expect(again.body.data.waveNumber).toBe(2);
    expect(db.getDoc('rideDispatchWaves', waveDocId('r14', 2))).toBeUndefined();
  });

  it('dispatch-sweep processes due rides', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const now = Date.now();
    await seedDriversNearPickup(db, redis, 5, now);
    seedDispatchableRide(db, 'r15');
    const app = appFor(db, redis);

    const res = await request(app)
      .post('/v1/internal/rides/dispatch-sweep?limit=10')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);

    expect(res.body.data.scanned).toBeGreaterThanOrEqual(1);
    expect(res.body.data.completed).toBeGreaterThanOrEqual(1);
    expect(db.getDoc('rideDispatchWaves', waveDocId('r15', 1))).toBeTruthy();
  });
});
