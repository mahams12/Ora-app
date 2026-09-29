/**
 * LIVE Redis proof for N2C + N3 coordinate-primary cutover.
 *
 * Requires REDIS_URL pointing at a real Redis instance.
 * If unset, exits with BLOCKED (does not fake success).
 *
 * Usage:
 *   REDIS_URL=redis://127.0.0.1:6379 npm run test:nearby-redis-proof
 */
import request from 'supertest';
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import { RedisGeoProjectionService } from '../src/redis/geo_projection';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  N3_REDIS_GEO_COUNT,
  driverOnlineKey,
  geoDriversCityKey,
} from '../src/redis/types';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';

const WORKER = 'n3-live-redis-proof-worker-tok';

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

async function main(): Promise<void> {
  if (!process.env.REDIS_URL?.trim()) {
    console.error(
      'N3 LIVE REDIS PROOF BLOCKED: REDIS_URL is not set.',
    );
    console.error(
      'To run: start Redis, export REDIS_URL=redis://127.0.0.1:6379, then npm run test:nearby-redis-proof',
    );
    process.exit(2);
  }

  const redis = await createRedisGeoClientFromEnv(process.env);
  assert(redis != null, 'redis client');

  const prefix = `n3cp-${Date.now()}`;
  const driverA = `${prefix}-a`; // with homeCity
  const driverB = `${prefix}-b`; // without homeCity
  const pickup = { lat: 31.52, lng: 74.35 };
  const now = Date.now();

  const db = memoryDb();
  for (const [id, homeCity] of [
    [driverA, 'lahore'],
    [driverB, null],
  ] as const) {
    db.seed('users', id, {
      uid: id,
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
      displayName: id,
    });
    db.seed('drivers', id, {
      driverId: id,
      userId: id,
      availabilityState: 'online',
      ...(homeCity != null ? { homeCity } : {}),
    });
  }

  const geo = new RedisGeoProjectionService(redis);
  const app = createApp({
    auth: {
      verifyIdToken: async (tok: string) => {
        if (tok === 'tok-a') return { uid: driverA, phone_number: '+100' };
        if (tok === 'tok-b') return { uid: driverB, phone_number: '+101' };
        return { uid: driverA, phone_number: '+100' };
      },
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 100_000 },
    internalWorkerToken: WORKER,
    redis,
    geoProjection: geo,
  });

  const locBody = (overrides: Record<string, unknown> = {}) => ({
    locationSeq: 1,
    locationStreamId: 'live-cp',
    lat: pickup.lat,
    lng: pickup.lng + 0.01,
    accuracy: 8,
    heading: 90,
    speed: 10,
    timestamp: new Date().toISOString(),
    provider: 'gps',
    ...overrides,
  });

  try {
    await test('GEORADIUS COUNT constant is 100', async () => {
      assert(N3_REDIS_GEO_COUNT === 100, `got ${N3_REDIS_GEO_COUNT}`);
    });

    await test('A. driver with homeCity projects into geo:drivers', async () => {
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer tok-a')
        .send(locBody({ locationSeq: 1 }));
      assert(res.status === 200, `status ${res.status}`);
      assert(
        (await redis!.geopos(GEO_DRIVERS_KEY, driverA)) != null,
        'primary membership',
      );
      assert(
        (await redis!.geopos(geoDriversCityKey('lahore'), driverA)) != null,
        'legacy dual-write',
      );
    });

    await test('B. driver WITHOUT homeCity projects into geo:drivers', async () => {
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer tok-b')
        .send(locBody({ locationSeq: 1, lng: pickup.lng + 0.02 }));
      assert(res.status === 200, `status ${res.status}`);
      assert(
        (await redis!.geopos(GEO_DRIVERS_KEY, driverB)) != null,
        'primary without homeCity',
      );
    });

    await test('C. N3 nearby without city returns drivers', async () => {
      const res = await request(app)
        .get('/v1/internal/drivers/nearby')
        .set('X-Ora-Worker-Token', WORKER)
        .query({ ...pickup, radiusKm: 10, limit: 30 });
      assert(res.status === 200, `status ${res.status} body=${JSON.stringify(res.body)}`);
      const ids = res.body.data.candidates.map(
        (c: { driverId: string }) => c.driverId,
      );
      assert(ids.includes(driverA), 'A present');
      assert(ids.includes(driverB), 'B present');
    });

    await test('D. city mismatch does not hide physically nearby driver', async () => {
      // Marker metadata says karachi; homeCity lahore; still in primary GEO near pickup
      await redis!.set(
        driverOnlineKey(driverA),
        JSON.stringify({
          driverId: driverA,
          lastLocationTs: now - 500,
          accuracy: 8,
          city: 'karachi',
          locationStreamId: 'live-cp',
          locationSeq: 2,
          acceptedAt: new Date().toISOString(),
        }),
        DRIVER_ONLINE_TTL_SECONDS,
      );
      const res = await request(app)
        .get('/v1/internal/drivers/nearby')
        .set('X-Ora-Worker-Token', WORKER)
        .query({ city: 'islamabad', ...pickup, radiusKm: 10 });
      assert(res.status === 200, `status ${res.status}`);
      const hit = res.body.data.candidates.find(
        (c: { driverId: string }) => c.driverId === driverA,
      );
      assert(hit != null, 'physical proximity wins over city labels');
    });

    await test('E. stale marker excluded', async () => {
      await redis!.set(
        driverOnlineKey(driverA),
        JSON.stringify({
          driverId: driverA,
          lastLocationTs: now - 60_000,
          accuracy: 8,
          city: 'lahore',
          locationStreamId: 'live-cp',
          locationSeq: 3,
          acceptedAt: new Date().toISOString(),
        }),
        DRIVER_ONLINE_TTL_SECONDS,
      );
      const res = await request(app)
        .get('/v1/internal/drivers/nearby')
        .set('X-Ora-Worker-Token', WORKER)
        .query({ ...pickup });
      const hit = res.body.data.candidates.find(
        (c: { driverId: string }) => c.driverId === driverA,
      );
      assert(hit == null, 'stale excluded');
    });

    await test('F. busy driver excluded', async () => {
      // Refresh A fresh, then mark busy
      await redis!.set(
        driverOnlineKey(driverA),
        JSON.stringify({
          driverId: driverA,
          lastLocationTs: Date.now() - 500,
          accuracy: 8,
          city: 'lahore',
          locationStreamId: 'live-cp',
          locationSeq: 4,
          acceptedAt: new Date().toISOString(),
        }),
        DRIVER_ONLINE_TTL_SECONDS,
      );
      db.seed('rides', `${prefix}-busy`, {
        rideId: `${prefix}-busy`,
        assignedDriverId: driverA,
        state: 'DRIVER_ASSIGNED',
        passengerId: 'p1',
      });
      const res = await request(app)
        .get('/v1/internal/drivers/nearby')
        .set('X-Ora-Worker-Token', WORKER)
        .query({ ...pickup });
      const hit = res.body.data.candidates.find(
        (c: { driverId: string }) => c.driverId === driverA,
      );
      assert(hit == null, 'busy excluded');
    });

    await test('G. offline removes coordinate-primary membership', async () => {
      // Use B (not busy)
      const res = await request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer tok-b')
        .send({});
      assert(res.status === 200, `offline ${res.status}`);
      assert(
        (await redis!.geopos(GEO_DRIVERS_KEY, driverB)) == null,
        'primary gone',
      );
      assert((await redis!.get(driverOnlineKey(driverB))) == null, 'marker gone');
    });
  } finally {
    await redis!.zrem(GEO_DRIVERS_KEY, driverA);
    await redis!.zrem(GEO_DRIVERS_KEY, driverB);
    await redis!.zrem(geoDriversCityKey('lahore'), driverA);
    await redis!.del(driverOnlineKey(driverA));
    await redis!.del(driverOnlineKey(driverB));
    if (redis!.quit) await redis!.quit();
  }

  console.log(`\nN3 coordinate-primary live Redis proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
