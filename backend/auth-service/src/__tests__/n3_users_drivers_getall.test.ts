import { describe, it, expect, vi } from 'vitest';
import {
  NearbyDriversService,
  N3_BUSY_RIDE_STATES,
  N3_FIRESTORE_GETALL_MAX,
  computeN3FirestoreRpcTotal,
  createEmptyN3NearbyDiagnostics,
  uniqueGeoMemberIdsInOrder,
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

function wrapDbWithGetAllSpy(db: ReturnType<typeof memoryDb>) {
  let usersGetAllCalls = 0;
  let driversGetAllCalls = 0;
  const origGetAll = db.getAll.bind(db);
  type DocRef = Parameters<typeof origGetAll>[0];
  const getAll = async (...refs: DocRef[]) => {
    if (refs.length > 0) {
      const col = refs[0]!.collection;
      if (col === 'users') usersGetAllCalls += 1;
      if (col === 'drivers') driversGetAllCalls += 1;
    }
    return origGetAll(...refs);
  };
  return {
    db: { ...db, getAll } as ReturnType<typeof memoryDb>,
    usersGetAllCalls: () => usersGetAllCalls,
    driversGetAllCalls: () => driversGetAllCalls,
  };
}

describe('N3 users+drivers getAll batch prefetch', () => {
  it('uniqueGeoMemberIdsInOrder dedupes while preserving GEO order', () => {
    expect(
      uniqueGeoMemberIdsInOrder([
        { member: 'a' },
        { member: 'b' },
        { member: 'a' },
        { member: 'c' },
      ]),
    ).toEqual(['a', 'b', 'c']);
  });

  it('≤100 GEO IDs → one users getAll and one drivers getAll', async () => {
    const base = memoryDb();
    const { db, usersGetAllCalls, driversGetAllCalls } = wrapDbWithGetAllSpy(base);
    const redis = createMemoryRedis();
    for (let i = 0; i < 15; i++) {
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
    expect(usersGetAllCalls()).toBe(1);
    expect(driversGetAllCalls()).toBe(1);
    expect(diag.firestoreUsersBatchRpcs).toBe(1);
    expect(diag.firestoreDriversBatchRpcs).toBe(1);
    expect(diag.firestoreUsersReads).toBe(15);
    expect(diag.firestoreDriversReads).toBe(15);
  });

  it('missing user → user_missing', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'online',
    });
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(result.candidates).toHaveLength(0);
    expect(diag.rejected.user_missing).toBe(1);
  });

  it('missing driver → driver_missing', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
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
    expect(diag.rejected.driver_missing).toBe(1);
  });

  it('banned user rejected', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: true,
    });
    db.seed('drivers', 'd1', { driverId: 'd1', availabilityState: 'online' });
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
    expect(diag.rejected.user_banned).toBe(1);
  });

  it('inactive user rejected', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: false,
      banned: false,
    });
    db.seed('drivers', 'd1', { driverId: 'd1', availabilityState: 'online' });
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
    expect(diag.rejected.user_inactive).toBe(1);
  });

  it('wrong role rejected as user_not_approved', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'passenger',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd1', { driverId: 'd1', availabilityState: 'online' });
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
    expect(diag.rejected.user_not_approved).toBe(1);
  });

  it('unapproved driver rejected', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'pending',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd1', { driverId: 'd1', availabilityState: 'online' });
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
    expect(diag.rejected.user_not_approved).toBe(1);
  });

  it('offline driver rejected', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd1', { driverId: 'd1', availabilityState: 'offline' });
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
  });

  it('eligible driver survives', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    const result = await svc.findNearby({ query: { ...pickup }, nowMs: now });
    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0]!.driverId).toBe('d1');
  });

  it('GEO ordering preserved for survivors', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (const id of ['far', 'near', 'mid']) {
      seedApprovedOnline(db, id);
    }
    await seedGeo(redis, 'far', 0.05, { lastLocationTs: now - 1000 });
    await seedGeo(redis, 'near', 0.001, { lastLocationTs: now - 1000 });
    await seedGeo(redis, 'mid', 0.02, { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    const result = await svc.findNearby({
      query: { ...pickup, limit: 10 },
      nowMs: now,
    });
    expect(result.candidates.map((c) => c.driverId)).toEqual(['near', 'mid', 'far']);
  });

  it('busy Set still rejects busy drivers', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'busy');
    seedApprovedOnline(db, 'free');
    await seedGeo(redis, 'busy', 0.01, { lastLocationTs: now - 1000 });
    await seedGeo(redis, 'free', 0.02, { lastLocationTs: now - 1000 });
    db.seed('rides', 'r1', {
      rideId: 'r1',
      assignedDriverId: 'busy',
      state: N3_BUSY_RIDE_STATES[0],
      passengerId: 'p1',
    });
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
    expect(result.candidates.map((c) => c.driverId)).toEqual(['free']);
  });

  it('isStillEligibleForInvite does not use getAll', async () => {
    const base = memoryDb();
    const getAllSpy = vi.fn(base.getAll.bind(base));
    const db = { ...base, getAll: getAllSpy };
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', 0.01, { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    const ok = await svc.isStillEligibleForInvite('d1', { nowMs: now });
    expect(ok).toBe(true);
    expect(getAllSpy).not.toHaveBeenCalled();
  });

  it('diagnostics separate batch RPC count from logical document reads', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < 3; i++) {
      seedApprovedOnline(db, `d${i}`);
      await seedGeo(redis, `d${i}`, 0.001 * (i + 1), { lastLocationTs: now - 1000 });
    }
    const svc = new NearbyDriversService(db as never, redis);
    let diag = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup, limit: 2 },
      nowMs: now,
      collectDiagnostics: (d) => {
        diag = d;
      },
    });
    expect(diag.firestoreUsersBatchRpcs).toBe(1);
    expect(diag.firestoreDriversBatchRpcs).toBe(1);
    expect(diag.firestoreUsersReads).toBe(3);
    expect(diag.firestoreDriversReads).toBe(3);
    expect(diag.firestoreRpcTotal).toBe(computeN3FirestoreRpcTotal(diag));
    expect(diag.firestoreRpcTotal).toBe(
      diag.firestoreUsersBatchRpcs +
        diag.firestoreDriversBatchRpcs +
        diag.firestoreBusyRideQueries,
    );
  });

  it('getAll chunk size constant matches Firestore limit', () => {
    expect(N3_FIRESTORE_GETALL_MAX).toBe(100);
  });
});
