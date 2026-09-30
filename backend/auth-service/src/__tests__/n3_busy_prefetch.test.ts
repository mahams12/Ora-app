import { describe, it, expect } from 'vitest';
import {
  NearbyDriversService,
  N3_BUSY_PREFETCH_IN_CHUNK_SIZE,
  N3_BUSY_RIDE_STATES,
  createEmptyN3NearbyDiagnostics,
} from '../drivers/nearby_service';
import { memoryDb } from './helpers/memory_db';
import { createMemoryRedis } from '../redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../redis/types';

const pickup = { lat: 31.52, lng: 74.35 };
const now = Date.now();

function seedApprovedOnline(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    availabilityState: 'online',
  });
}

async function seedGeo(
  redis: ReturnType<typeof createMemoryRedis>,
  driverId: string,
  lngOffset: number,
  marker: Partial<DriverOnlineMarker> & { lastLocationTs: number },
) {
  await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng + lngOffset, pickup.lat, driverId);
  const full: DriverOnlineMarker = {
    driverId,
    accuracy: 8,
    city: null,
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

function seedBusyRide(db: ReturnType<typeof memoryDb>, rideId: string, driverId: string) {
  db.seed('rides', rideId, {
    rideId,
    assignedDriverId: driverId,
    state: N3_BUSY_RIDE_STATES[0],
    passengerId: 'p1',
  });
}

describe('N3 busy-ride batch prefetch', () => {
  it('no geo hits → zero busy queries', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.firestoreBusyRideQueries).toBe(0);
  });

  it('≤ chunk size geo hits → exactly one busy query', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < 10; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(redis, id, 0.001 * (i + 1), { lastLocationTs: now - 1000 });
    }
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup, limit: 10 },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.firestoreBusyRideQueries).toBe(1);
    expect(diag.firestoreUsersReads).toBe(10);
    expect(diag.firestoreDriversReads).toBe(10);
  });

  it('> chunk size → correct number of busy query chunks', async () => {
    const n = N3_BUSY_PREFETCH_IN_CHUNK_SIZE + 1;
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < n; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(redis, id, 0.0001 * (i + 1), { lastLocationTs: now - 1000 });
    }
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup, limit: n },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.firestoreBusyRideQueries).toBe(2);
  });

  it('100 geo hits → four busy chunks (chunk size 30)', async () => {
    const n = 100;
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < n; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(redis, id, 0.00001 * (i + 1), { lastLocationTs: now - 1000 });
    }
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup, limit: 100 },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.firestoreBusyRideQueries).toBe(Math.ceil(n / N3_BUSY_PREFETCH_IN_CHUNK_SIZE));
  });

  it('non-busy state on assigned ride does not mark driver busy', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    db.seed('rides', 'r-search', {
      rideId: 'r-search',
      assignedDriverId: 'd1',
      state: 'SEARCHING',
      passengerId: 'p1',
    });
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(result.candidates).toHaveLength(1);
    expect(diag.rejected.driver_busy).toBe(0);
  });

  it('batch marks busy driver rejected; non-busy remains eligible', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'busy1');
    seedApprovedOnline(db, 'free1');
    await seedGeo(redis, 'busy1', 0.01, { lastLocationTs: now - 1000 });
    await seedGeo(redis, 'free1', 0.02, { lastLocationTs: now - 1000 });
    seedBusyRide(db, 'r-busy', 'busy1');
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup, limit: 10 },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.rejected.driver_busy).toBe(1);
    expect(result.candidates.map((c) => c.driverId)).toEqual(['free1']);
    expect(diag.eligibleCount).toBe(1);
  });

  it('multiple busy drivers rejected from merged batch results', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (const id of ['b1', 'b2', 'ok']) {
      seedApprovedOnline(db, id);
      await seedGeo(redis, id, 0.01 * (id.charCodeAt(0) / 100), {
        lastLocationTs: now - 1000,
      });
    }
    seedBusyRide(db, 'r1', 'b1');
    seedBusyRide(db, 'r2', 'b2');
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup, limit: 10 },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.rejected.driver_busy).toBe(2);
    expect(result.candidates.map((c) => c.driverId)).toEqual(['ok']);
  });

  it('GEO ordering of survivors unchanged', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const ids = ['d2', 'd0', 'd1'];
    for (let i = 0; i < ids.length; i++) {
      seedApprovedOnline(db, ids[i]!);
      await seedGeo(redis, ids[i]!, 0.01 * (i + 1), { lastLocationTs: now - 1000 });
    }
    seedBusyRide(db, 'r', 'd1');
    const svc = new NearbyDriversService(db as never, redis);
    const result = await svc.findNearby({
      query: { ...pickup, limit: 10 },
      nowMs: now,
    });
    expect(result.candidates.map((c) => c.driverId)).toEqual(['d2', 'd0']);
  });

  it('isStillEligibleForInvite busy semantics unchanged (N4 path)', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    seedBusyRide(db, 'r1', 'd1');
    const svc = new NearbyDriversService(db as never, redis);
    const ok = await svc.isStillEligibleForInvite('d1', { nowMs: now });
    expect(ok).toBe(false);
  });

  it('offline driver still rejects before busy set lookup matters', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'offline',
    });
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.rejected.driver_offline).toBe(1);
    expect(diag.firestoreBusyRideQueries).toBe(1);
  });
});
