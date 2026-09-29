/**
 * Standalone N3 unit proof (MemoryDb + MemoryRedis) — coordinate-primary.
 * Usage: npm run test:phase-n3-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import { createMemoryRedis } from '../src/redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  N3_REDIS_GEO_COUNT,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../src/redis/types';

const WORKER = 'n3-unit-proof-worker-token';

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
    auth: {
      verifyIdToken: async () => ({ uid: 'unused', phone_number: '+100' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    redis,
  });
}

async function main(): Promise<void> {
  const now = Date.now();
  const pickup = { lat: 31.52, lng: 74.35 };

  await test('Redis COUNT constant is 100', async () => {
    assert(N3_REDIS_GEO_COUNT === 100, `got ${N3_REDIS_GEO_COUNT}`);
  });

  await test('healthy empty without city → 200 []', async () => {
    const res = await request(appFor(memoryDb(), createMemoryRedis()))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup });
    assert(res.status === 200, `status ${res.status}`);
    assert(Array.isArray(res.body.data.candidates), 'candidates array');
    assert(res.body.data.candidates.length === 0, 'empty');
  });

  await test('redis null → 503 DEPENDENCY_ERROR', async () => {
    const res = await request(appFor(memoryDb(), null))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup });
    assert(res.status === 503, `status ${res.status}`);
    assert(res.body.error.code === 'DEPENDENCY_ERROR', res.body.error?.code);
  });

  await test('valid candidate without city query', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1', null);
    await seedGeo(redis, 'd1', pickup.lng + 0.01, pickup.lat, {
      lastLocationTs: now - 1000,
      city: null,
    });
    const res = await request(appFor(db, redis))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup });
    assert(res.status === 200, `status ${res.status}`);
    assert(res.body.data.candidates.length === 1, 'one candidate');
    assert(res.body.data.candidates[0].driverId === 'd1', 'driverId');
  });

  await test('stale marker dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 20_000,
    });
    const res = await request(appFor(db, redis))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup });
    assert(res.body.data.candidates.length === 0, 'stale dropped');
  });

  await test('busy DRIVER_ASSIGNED dropped', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    seedApprovedOnline(db, 'd1');
    await seedGeo(redis, 'd1', pickup.lng, pickup.lat, {
      lastLocationTs: now - 1000,
    });
    db.seed('rides', 'r1', {
      rideId: 'r1',
      assignedDriverId: 'd1',
      state: 'DRIVER_ASSIGNED',
      passengerId: 'p1',
    });
    const res = await request(appFor(db, redis))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup });
    assert(res.body.data.candidates.length === 0, 'busy dropped');
  });

  await test('distance ordering + limit', async () => {
    const db = memoryDb();
    const redis = createMemoryRedis();
    for (let i = 0; i < 4; i++) {
      const id = `d${i}`;
      seedApprovedOnline(db, id);
      await seedGeo(
        redis,
        id,
        pickup.lng + 0.002 * (i + 1),
        pickup.lat,
        { lastLocationTs: now - 1000 },
      );
    }
    const res = await request(appFor(db, redis))
      .get('/v1/internal/drivers/nearby')
      .set('X-Ora-Worker-Token', WORKER)
      .query({ ...pickup, limit: 2 });
    assert(res.body.data.candidates.length === 2, 'limit 2');
    assert(res.body.data.candidates[0].driverId === 'd0', 'nearest first');
    assert(
      res.body.data.candidates[0].distanceKm <
        res.body.data.candidates[1].distanceKm,
      'ASC',
    );
  });

  await test('JWT /v1/drivers/nearby not registered', async () => {
    const res = await request(appFor(memoryDb(), createMemoryRedis()))
      .get('/v1/drivers/nearby')
      .set('Authorization', 'Bearer t');
    assert(res.status === 404, `got ${res.status}`);
  });

  console.log(`\nN3 unit proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
