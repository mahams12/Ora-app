import { describe, it, expect } from 'vitest';
import {
  NearbyDriversService,
  N3_BUSY_RIDE_STATES,
  compactN3RejectionCounts,
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
  marker: Partial<DriverOnlineMarker> & { lastLocationTs: number },
) {
  await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng + 0.01, pickup.lat, driverId);
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

describe('N3 findNearby diagnostics', () => {
  it('empty GEO → zero counts', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(result.candidates).toEqual([]);
    expect(captured.geoHits).toBe(0);
    expect(captured.redisGetCount).toBe(0);
    expect(captured.firestoreUsersReads).toBe(0);
    expect(captured.eligibleCount).toBe(0);
    expect(compactN3RejectionCounts(captured.rejected)).toEqual({});
  });

  it('one eligible driver → 1 geo, 1 redis marker batch, batch getAll + busy', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(result.candidates).toHaveLength(1);
    expect(captured.geoHits).toBe(1);
    expect(captured.redisGetCount).toBe(1);
    expect(captured.firestoreUsersReads).toBe(1);
    expect(captured.firestoreDriversReads).toBe(1);
    expect(captured.firestoreUsersBatchRpcs).toBe(1);
    expect(captured.firestoreDriversBatchRpcs).toBe(1);
    expect(captured.firestoreBusyRideQueries).toBe(1);
    expect(captured.firestoreRpcTotal).toBe(3);
    expect(captured.eligibleCount).toBe(1);
    expect(compactN3RejectionCounts(captured.rejected)).toEqual({});
  });

  it('stale marker → marker_not_fresh; prefetch still loads user/driver docs', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', { lastLocationTs: now - 60_000 });
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.marker_not_fresh).toBe(1);
    expect(captured.firestoreUsersReads).toBe(1);
    expect(captured.firestoreDriversReads).toBe(1);
    expect(captured.firestoreUsersBatchRpcs).toBe(1);
    expect(captured.firestoreDriversBatchRpcs).toBe(1);
    expect(captured.redisGetCount).toBe(1);
    expect(captured.firestoreBusyRideQueries).toBe(1);
  });

  it('offline driver → driver_offline, 2 firestore reads, no busy query', async () => {
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
    await seedGeo(redis, 'd1', { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.driver_offline).toBe(1);
    expect(captured.firestoreUsersReads).toBe(1);
    expect(captured.firestoreDriversReads).toBe(1);
    expect(captured.firestoreBusyRideQueries).toBe(1);
  });

  it('busy driver → driver_busy bucket', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', { lastLocationTs: now - 1000 });
    db.seed('rides', 'r1', {
      rideId: 'r1',
      assignedDriverId: 'd1',
      state: N3_BUSY_RIDE_STATES[0],
      passengerId: 'p1',
    });
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.driver_busy).toBe(1);
    expect(captured.firestoreBusyRideQueries).toBe(1);
    expect(captured.eligibleCount).toBe(0);
  });

  it('limit caps eligible count; one batched marker read per invocation', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < 5; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await redis.geoadd(
        GEO_DRIVERS_KEY,
        pickup.lng + 0.001 * (i + 1),
        pickup.lat,
        id,
      );
      await seedGeo(redis, id, {
        lastLocationTs: now - 1000,
        driverId: id,
      });
    }
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup, limit: 2 },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.geoHits).toBe(5);
    expect(captured.redisGetCount).toBe(1);
    expect(captured.eligibleCount).toBe(2);
    expect(captured.firestoreBusyRideQueries).toBe(1);
  });
});
