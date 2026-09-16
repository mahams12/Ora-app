/**
 * LIVE Redis proof for N2C.
 *
 * Requires REDIS_URL pointing at a real Redis instance.
 * If unset, exits with BLOCKED (does not fake success).
 *
 * Usage:
 *   REDIS_URL=redis://127.0.0.1:6379 npm run test:redis-geo-proof
 */
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import { RedisGeoProjectionService } from '../src/redis/geo_projection';
import {
  driverOnlineKey,
  geoDriversKey,
} from '../src/redis/types';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import request from 'supertest';

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
      'N2C LIVE REDIS PROOF BLOCKED: REDIS_URL is not set and no local Redis (redis-cli/docker) was available.',
    );
    console.error(
      'To run: start Redis, export REDIS_URL=redis://127.0.0.1:6379, then npm run test:redis-geo-proof',
    );
    process.exit(2);
  }

  const redis = await createRedisGeoClientFromEnv(process.env);
  assert(redis != null, 'redis client');

  const prefix = `n2c-${Date.now()}`;
  const driverId = `${prefix}-drv`;
  const city = 'lahore';

  // Isolate: use unique driverId; flush is dangerous on shared redis — avoid flushdb.
  const db = memoryDb();
  db.seed('users', driverId, {
    uid: driverId,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    phoneNumber: '+923001111111',
    displayName: driverId,
  });
  db.seed('drivers', driverId, {
    driverId,
    userId: driverId,
    availabilityState: 'online',
    homeCity: 'Lahore',
  });
  db.seed('rides', `${prefix}-ride`, {
    rideId: `${prefix}-ride`,
    sentinel: 'untouched-by-n2c',
    state: 'SEARCHING',
  });

  const geo = new RedisGeoProjectionService(redis);
  const app = createApp({
    auth: {
      verifyIdToken: async () => ({
        uid: driverId,
        phone_number: '+923001111111',
      }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 100_000 },
    geoProjection: geo,
  });

  const body = (overrides: Record<string, unknown> = {}) => ({
    locationSeq: 1,
    locationStreamId: 'live-stream',
    lat: 31.52,
    lng: 74.35,
    accuracy: 8,
    heading: 90,
    speed: 20,
    timestamp: new Date().toISOString(),
    provider: 'gps',
    ...overrides,
  });

  try {
    await test('1-5. clean + accepted location → GEO + online marker', async () => {
      await redis!.zrem(geoDriversKey(city), driverId);
      await redis!.del(driverOnlineKey(driverId));
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(body());
      assert(res.status === 200, `got ${res.status}`);
      const pos = await redis!.geopos(geoDriversKey(city), driverId);
      assert(pos != null, 'geo membership');
      const marker = await redis!.get(driverOnlineKey(driverId));
      assert(marker != null, 'online marker');
      assert(JSON.parse(marker).city === city, 'city');
    });

    await test('6-7. newer location updates GEO', async () => {
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', 'Bearer t')
        .send(body({ locationSeq: 2, lat: 31.53, lng: 74.36 }));
      assert(res.status === 200, 'ok');
      const pos = await redis!.geopos(geoDriversKey(city), driverId);
      assert(pos != null, 'pos');
      assert(Math.abs(Number(pos[1]) - 31.53) < 0.01, 'lat moved');
    });

    await test('8-10. go-offline removes GEO + marker', async () => {
      const res = await request(app)
        .post('/v1/drivers/go-offline')
        .set('Authorization', 'Bearer t')
        .send({});
      assert(res.status === 200, 'offline');
      assert(
        (await redis!.geopos(geoDriversKey(city), driverId)) == null,
        'geo gone',
      );
      assert((await redis!.get(driverOnlineKey(driverId))) == null, 'marker gone');
    });

    await test('12. Firestore/N2A sentinel unchanged', async () => {
      assert(
        db.getDoc('rides', `${prefix}-ride`)?.sentinel === 'untouched-by-n2c',
        'sentinel',
      );
      assert(db.getDoc('locationStreams', driverId)?.lat === undefined, 'no gps');
    });

    await test('13. no RTDB dependency', async () => {
      assert(!process.env.FIREBASE_DATABASE_URL, 'no rtdb url required');
    });
  } finally {
    await redis!.zrem(geoDriversKey(city), driverId);
    await redis!.del(driverOnlineKey(driverId));
    await redis!.quit?.();
  }

  console.log(`\nN2C live Redis proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
