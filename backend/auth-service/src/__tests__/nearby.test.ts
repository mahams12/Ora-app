import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { createMemoryRedis } from '../redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  N3_REDIS_GEO_COUNT,
  driverOnlineKey,
  geoDriversCityKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../redis/types';
import { N3_BUSY_RIDE_STATES } from '../drivers/nearby_service';

const WORKER = 'test-worker-token-n3-xxxx';

function authStub() {
  return {
    verifyIdToken: async () => ({ uid: 'unused', phone_number: '+100' }),
  } as never;
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

function nearby(
  app: ReturnType<typeof createApp>,
  qs: Record<string, string | number>,
  token: string | null = WORKER,
) {
  const req = request(app).get('/v1/internal/drivers/nearby').query(qs);
  if (token != null) req.set('X-Ora-Worker-Token', token);
  return req;
}

describe('N3 GET /v1/internal/drivers/nearby (coordinate-primary)', () => {
  const now = Date.now();
  const pickup = { lat: 31.52, lng: 74.35 };

  it('1. missing worker token → 403 or 503', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const res = await nearby(appFor(db, redis), { ...pickup }, null);
    expect([403, 503]).toContain(res.status);
  });

  it('2. invalid worker token → 403', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    const res = await nearby(
      appFor(db, redis),
      { ...pickup },
      'wrong-token-xxxxx',
    );
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
  });

  it('3. nearby works without city', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1', null);
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
      city: null,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toHaveLength(1);
    expect(res.body.data.city).toBeUndefined();
  });

  it('4–5. invalid lat/lng → 400', async () => {
    const app = appFor(memoryDb(), createMemoryRedis());
    const badLat = await nearby(app, { lat: 999, lng: 74 });
    expect(badLat.status).toBe(400);
    const badLng = await nearby(app, { lat: 31, lng: 999 });
    expect(badLng.status).toBe(400);
  });

  it('6–8. radius bounds', async () => {
    const app = appFor(memoryDb(), createMemoryRedis());
    expect((await nearby(app, { ...pickup, radiusKm: 0.5 })).status).toBe(400);
    expect((await nearby(app, { ...pickup, radiusKm: 26 })).status).toBe(400);
    expect((await nearby(app, { ...pickup, radiusKm: 'x' })).status).toBe(400);
  });

  it('9–10. limit bounds', async () => {
    const app = appFor(memoryDb(), createMemoryRedis());
    expect((await nearby(app, { ...pickup, limit: 0 })).status).toBe(400);
    expect((await nearby(app, { ...pickup, limit: 101 })).status).toBe(400);
  });

  it('11. Redis healthy + zero candidates → 200 []', async () => {
    const res = await nearby(appFor(memoryDb(), createMemoryRedis()), {
      ...pickup,
    });
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toEqual([]);
  });

  it('12. Redis null → 503 DEPENDENCY_ERROR', async () => {
    const res = await nearby(appFor(memoryDb(), null), { ...pickup });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('DEPENDENCY_ERROR');
  });

  it('12b. Redis georadius throws → 503 DEPENDENCY_ERROR', async () => {
    const failing: RedisGeoClient = {
      ...createMemoryRedis(),
      async georadius() {
        throw new Error('REDIS_DOWN');
      },
    };
    const res = await nearby(appFor(memoryDb(), failing), { ...pickup });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('DEPENDENCY_ERROR');
  });

  it('13. missing online marker → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng, pickup.lat, 'd1');
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toEqual([]);
  });

  it('14. stale marker → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 20_000,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('15. future marker → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now + 60_000,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('16. malformed marker → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await redis.geoadd(GEO_DRIVERS_KEY, pickup.lng, pickup.lat, 'd1');
    await redis.set(driverOnlineKey('d1'), 'not-json', DRIVER_ONLINE_TTL_SECONDS);
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('17. accuracy > 50 → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
      accuracy: 51,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('18. mismatched homeCity / marker city still returned', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1', 'lahore');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
      city: 'karachi',
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toHaveLength(1);
  });

  it('19. driver not approved → dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    db.seed('users', 'd1', {
      uid: 'd1',
      role: 'driver',
      driverStatus: 'pending',
      isActive: true,
      banned: false,
    });
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'online',
      homeCity: 'lahore',
    });
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('20. driver offline → dropped', async () => {
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
      homeCity: 'lahore',
    });
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  for (const state of N3_BUSY_RIDE_STATES) {
    it(`busy ${state} → dropped`, async () => {
      const db = memoryDb();
      const redis = createMemoryRedis();
      seedApprovedOnline(db, 'd1');
      await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
        lastLocationTs: now - 1000,
      });
      db.seed('rides', `r-${state}`, {
        rideId: `r-${state}`,
        assignedDriverId: 'd1',
        state,
        passengerId: 'p1',
      });
      const res = await nearby(appFor(db, redis), { ...pickup });
      expect(res.body.data.candidates).toEqual([]);
    });
  }

  it('25. valid driver returned with exact shape', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng + 0.01, pickup.lat, {
      lastLocationTs: now - 1000,
      accuracy: 8,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.status).toBe(200);
    expect(res.body.data.candidates).toHaveLength(1);
    const c = res.body.data.candidates[0];
    expect(c).toEqual({
      driverId: 'd1',
      distanceKm: expect.any(Number),
      lat: expect.any(Number),
      lng: expect.any(Number),
      lastLocationTs: now - 1000,
      accuracy: 8,
    });
    expect(Object.keys(c).sort()).toEqual(
      [
        'accuracy',
        'distanceKm',
        'driverId',
        'lat',
        'lastLocationTs',
        'lng',
      ].sort(),
    );
  });

  it('26. distance ordering preserved', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'near');
    seedApprovedOnline(db, 'far');
    await seedGeo(redis, 'near', pickup.lng + 0.005, pickup.lat, {
      lastLocationTs: now - 1000,
    });
    await seedGeo(redis, 'far', pickup.lng + 0.05, pickup.lat, {
      lastLocationTs: now - 1000,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates.map((c: { driverId: string }) => c.driverId)).toEqual([
      'near',
      'far',
    ]);
    expect(res.body.data.candidates[0].distanceKm).toBeLessThan(
      res.body.data.candidates[1].distanceKm,
    );
  });

  it('27. limit truncates final response', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < 5; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(redis, id, pickup.lng + 0.001 * (i + 1), pickup.lat, {
        lastLocationTs: now - 1000,
      });
    }
    const res = await nearby(appFor(db, redis), { ...pickup, limit: 2 });
    expect(res.body.data.candidates).toHaveLength(2);
  });

  it('28. Redis COUNT constant is 100', () => {
    expect(N3_REDIS_GEO_COUNT).toBe(100);
  });

  it('29. city query param does not restrict matching', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1', 'lahore');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
      city: 'lahore',
    });
    const res = await nearby(appFor(db, redis), {
      city: 'islamabad',
      ...pickup,
    });
    expect(res.body.data.candidates).toHaveLength(1);
    expect(res.body.data.city).toBe('islamabad');
  });

  it('30. null homeCity driver discoverable', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1', null);
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
      city: null,
    });
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toHaveLength(1);
  });

  it('31. legacy city GEO key is not consulted', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    // Only in legacy city key — not in primary
    await redis.geoadd(geoDriversCityKey('lahore'), pickup.lng, pickup.lat, 'd1');
    await redis.set(
      driverOnlineKey('d1'),
      JSON.stringify({
        driverId: 'd1',
        lastLocationTs: now - 1000,
        accuracy: 8,
        city: 'lahore',
        locationStreamId: 's1',
        locationSeq: 1,
        acceptedAt: new Date().toISOString(),
      }),
      DRIVER_ONLINE_TTL_SECONDS,
    );
    const res = await nearby(appFor(db, redis), { ...pickup });
    expect(res.body.data.candidates).toEqual([]);
  });

  it('JWT /v1/drivers/nearby is not registered', async () => {
    const res = await request(appFor(memoryDb(), createMemoryRedis()))
      .get('/v1/drivers/nearby')
      .set('Authorization', 'Bearer x');
    expect(res.status).toBe(404);
  });
});
