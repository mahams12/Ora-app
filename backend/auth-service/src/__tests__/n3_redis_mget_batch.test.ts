import { describe, it, expect, vi } from 'vitest';
import {
  NearbyDriversService,
  createEmptyN3NearbyDiagnostics,
  type N3NearbyDiagnostics,
} from '../drivers/nearby_service';
import { memoryDb } from './helpers/memory_db';
import { createMemoryRedis } from '../redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
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
  lngOffset = 0.01,
) {
  await redis.geoadd(
    GEO_DRIVERS_KEY,
    pickup.lng + lngOffset,
    pickup.lat,
    driverId,
  );
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

function wrapRedisForFindNearby(
  base: ReturnType<typeof createMemoryRedis>,
): {
  redis: RedisGeoClient;
  mgetSpy: ReturnType<typeof vi.fn>;
  getSpy: ReturnType<typeof vi.fn>;
} {
  const mgetSpy = vi.fn(base.mget.bind(base));
  const getSpy = vi.fn(base.get.bind(base));
  const redis: RedisGeoClient = {
    ...base,
    mget: mgetSpy,
    get: getSpy,
  };
  return { redis, mgetSpy, getSpy };
}

describe('N3 findNearby Redis MGET batching', () => {
  it('mget receives driver:online keys in GEO hit order', async () => {
    const db = memoryDb();
    const base = createMemoryRedis();
    const { redis, mgetSpy } = wrapRedisForFindNearby(base);
    for (let i = 0; i < 3; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(base, id, { lastLocationTs: now - 1000, driverId: id }, 0.001 * (i + 1));
    }
    const svc = new NearbyDriversService(db as never, redis);
    await svc.findNearby({ query: { ...pickup }, nowMs: now });
    expect(mgetSpy).toHaveBeenCalledTimes(1);
    expect(mgetSpy.mock.calls[0][0]).toEqual([
      driverOnlineKey('d0'),
      driverOnlineKey('d1'),
      driverOnlineKey('d2'),
    ]);
  });

  it('findNearby does not call redis.get (N4 path still uses get separately)', async () => {
    const db = memoryDb();
    const base = createMemoryRedis();
    const { redis, getSpy } = wrapRedisForFindNearby(base);
    seedApprovedOnline(db, 'd1');
    await seedGeo(base, 'd1', { lastLocationTs: now - 1000 });
    const svc = new NearbyDriversService(db as never, redis);
    await svc.findNearby({ query: { ...pickup }, nowMs: now });
    expect(getSpy).not.toHaveBeenCalled();
  });

  it('eligibility and candidate ordering match GEO ASC distance order', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'near');
    seedApprovedOnline(db, 'far');
    await seedGeo(redis, 'far', { lastLocationTs: now - 1000, driverId: 'far' }, 0.05);
    await seedGeo(redis, 'near', { lastLocationTs: now - 1000, driverId: 'near' }, 0.001);
    const svc = new NearbyDriversService(db as never, redis);
    const result = await svc.findNearby({ query: { ...pickup, limit: 10 }, nowMs: now });
    expect(result.candidates.map((c) => c.driverId)).toEqual(['near', 'far']);
  });

  it('missing marker still increments marker_missing; prefetch loads docs before loop', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng + 0.01, pickup.lat, 'd1');
    const svc = new NearbyDriversService(db as never, redis);
    let captured = createEmptyN3NearbyDiagnostics();
    await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(captured.rejected.marker_missing).toBe(1);
    expect(captured.firestoreUsersReads).toBe(1);
    expect(captured.firestoreDriversReads).toBe(1);
    expect(captured.redisGetCount).toBe(1);
  });

  it('stale and bad-accuracy markers reject; prefetch loads all geo docs', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'stale');
    seedApprovedOnline(db, 'badAcc');
    await seedGeo(redis, 'stale', { lastLocationTs: now - 60_000, driverId: 'stale' }, 0.01);
    await seedGeo(redis, 'badAcc', {
      lastLocationTs: now - 1000,
      driverId: 'badAcc',
      accuracy: 999,
    }, 0.02);
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
    expect(captured.rejected.marker_accuracy).toBe(1);
    expect(captured.firestoreUsersReads).toBe(2);
    expect(captured.firestoreDriversReads).toBe(2);
    expect(captured.redisGetCount).toBe(1);
  });

  it('mget failure → DEPENDENCY_ERROR 503', async () => {
    const db = memoryDb();
    const base = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(base, 'd1', { lastLocationTs: now - 1000 });
    const redis: RedisGeoClient = {
      ...base,
      async mget() {
        throw new Error('redis down');
      },
    };
    const svc = new NearbyDriversService(db as never, redis);
    await expect(
      svc.findNearby({ query: { ...pickup }, nowMs: now }),
    ).rejects.toMatchObject({
      code: 'DEPENDENCY_ERROR',
      httpStatus: 503,
    });
  });

  it('mixed geo hits: same rejection buckets as sequential semantics', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'ok');
    await seedGeo(redis, 'ok', { lastLocationTs: now - 1000, driverId: 'ok' }, 0.001);
    await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng + 0.02, pickup.lat, 'ghost');
    const svc = new NearbyDriversService(db as never, redis);
    let captured: N3NearbyDiagnostics = createEmptyN3NearbyDiagnostics();
    const result = await svc.findNearby({
      query: { ...pickup },
      nowMs: now,
      collectDiagnostics: (d) => {
        captured = d;
      },
    });
    expect(result.candidates).toHaveLength(1);
    expect(result.candidates[0].driverId).toBe('ok');
    expect(captured.rejected.marker_missing).toBe(1);
    expect(captured.eligibleCount).toBe(1);
  });
});
