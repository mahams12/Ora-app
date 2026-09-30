/**
 * Seed / cleanup isolated N3 staging benchmark drivers (Firestore + Redis).
 * Prefix: n3bench_<BENCH_PREFIX>_* — does not touch real user UIDs.
 *
 * Usage:
 *   BENCH_PREFIX=20260929T094800Z npx tsx scripts/seed_n3_staging_benchmark.ts seed [count]
 *   BENCH_PREFIX=20260929T094800Z npx tsx scripts/seed_n3_staging_benchmark.ts cleanup
 */
import { initializeApp, cert, getApps, applicationDefault } from 'firebase-admin/app';
import fs from 'node:fs';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../src/redis/types';

const here = path.dirname(
  // Bundled CJS (Cloud Run Job) vs tsx (local).
  typeof __dirname !== 'undefined' ? __filename : fileURLToPath(import.meta.url),
);
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

const MODE = process.argv[2] ?? 'seed';
const COUNT = Math.min(
  100,
  Math.max(1, Number.parseInt(process.argv[3] ?? '100', 10) || 100),
);
const PREFIX = process.env.BENCH_PREFIX?.trim() || `n3bench_${Date.now()}`;
const PICKUP = {
  lat: Number(process.env.N3_BENCH_LAT ?? '31.4127578'),
  lng: Number(process.env.N3_BENCH_LNG ?? '74.1725224'),
};

function driverId(i: number): string {
  return `${PREFIX}_d${String(i).padStart(3, '0')}`;
}

async function seedFirestore(db: ReturnType<typeof getFirestore>, ids: string[]) {
  const batchSize = 400;
  for (let start = 0; start < ids.length; start += batchSize) {
    const batch = db.batch();
    for (const id of ids.slice(start, start + batchSize)) {
      batch.set(db.collection('users').doc(id), {
        uid: id,
        role: 'driver',
        driverStatus: 'approved',
        isActive: true,
        banned: false,
        displayName: `N3 bench ${id.slice(-8)}`,
        _n3Bench: true,
        _n3BenchPrefix: PREFIX,
      });
      batch.set(db.collection('drivers').doc(id), {
        driverId: id,
        userId: id,
        availabilityState: 'online',
        homeCity: 'lahore',
        _n3Bench: true,
        _n3BenchPrefix: PREFIX,
      });
    }
    await batch.commit();
  }
}

async function seedRedis(
  redis: NonNullable<Awaited<ReturnType<typeof createRedisGeoClientFromEnv>>>,
  ids: string[],
) {
  const now = Date.now();
  for (let i = 0; i < ids.length; i++) {
    const id = ids[i]!;
    const lng = PICKUP.lng + 0.00005 * (i + 1);
    await redis.geoadd(GEO_DRIVERS_KEY, lng, PICKUP.lat, id);
    const marker: DriverOnlineMarker = {
      driverId: id,
      lastLocationTs: now - 500,
      accuracy: 8,
      city: 'lahore',
      locationStreamId: `bench-${PREFIX}`,
      locationSeq: 1,
      acceptedAt: new Date().toISOString(),
    };
    await redis.set(
      driverOnlineKey(id),
      JSON.stringify(marker),
      DRIVER_ONLINE_TTL_SECONDS,
    );
  }
}

async function cleanupFirestore(db: ReturnType<typeof getFirestore>) {
  for (const col of ['users', 'drivers'] as const) {
    const snap = await db
      .collection(col)
      .where('_n3BenchPrefix', '==', PREFIX)
      .get();
    if (snap.empty) continue;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

async function listBenchDriverIds(db: ReturnType<typeof getFirestore>): Promise<string[]> {
  const snap = await db
    .collection('drivers')
    .where('_n3BenchPrefix', '==', PREFIX)
    .get();
  return snap.docs.map((d) => d.id);
}

async function cleanupRedis(
  redis: NonNullable<Awaited<ReturnType<typeof createRedisGeoClientFromEnv>>>,
  ids: string[],
) {
  for (const id of ids) {
    await redis.zrem(GEO_DRIVERS_KEY, id);
    await redis.del(driverOnlineKey(id));
  }
}

function initFirebase() {
  if (getApps().length) return;
  const envSa = process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim();
  if (envSa && fs.existsSync(envSa)) {
    initializeApp({ credential: cert(envSa) });
    return;
  }
  if (fs.existsSync(saPath)) {
    initializeApp({ credential: cert(saPath) });
    return;
  }
  initializeApp({ credential: applicationDefault() });
}

async function main() {
  initFirebase();
  const db = getFirestore();
  const redis = await createRedisGeoClientFromEnv(process.env);
  if (!redis) {
    console.error(JSON.stringify({ ok: false, error: 'REDIS_URL not set' }));
    process.exit(2);
  }

  const ids = Array.from({ length: COUNT }, (_, i) => driverId(i));

  try {
    if (MODE === 'seed') {
      await seedFirestore(db, ids);
      await seedRedis(redis, ids);
      console.log(
        JSON.stringify({
          ok: true,
          mode: 'seed',
          prefix: PREFIX,
          count: ids.length,
          pickup: PICKUP,
          sampleDriverId: ids[0],
        }),
      );
      return;
    }
    if (MODE === 'refresh') {
      const benchIds = await listBenchDriverIds(db);
      if (benchIds.length === 0) {
        console.error(JSON.stringify({ ok: false, error: 'no bench drivers to refresh' }));
        process.exit(2);
      }
      const now = Date.now();
      for (let i = 0; i < benchIds.length; i++) {
        const id = benchIds[i]!;
        const lng = PICKUP.lng + 0.00005 * (i + 1);
        await redis.geoadd(GEO_DRIVERS_KEY, lng, PICKUP.lat, id);
        const marker: DriverOnlineMarker = {
          driverId: id,
          lastLocationTs: now - 500,
          accuracy: 8,
          city: 'lahore',
          locationStreamId: `bench-${PREFIX}`,
          locationSeq: 1,
          acceptedAt: new Date().toISOString(),
        };
        await redis.set(
          driverOnlineKey(id),
          JSON.stringify(marker),
          DRIVER_ONLINE_TTL_SECONDS,
        );
      }
      console.log(
        JSON.stringify({ ok: true, mode: 'refresh', prefix: PREFIX, count: benchIds.length }),
      );
      return;
    }
    if (MODE === 'cleanup') {
      const benchIds = await listBenchDriverIds(db);
      await cleanupRedis(redis, benchIds.length ? benchIds : ids);
      await cleanupFirestore(db);
      console.log(
        JSON.stringify({
          ok: true,
          mode: 'cleanup',
          prefix: PREFIX,
          removed: benchIds.length,
        }),
      );
      return;
    }
    throw new Error('usage: seed [count] | cleanup');
  } finally {
    await redis.quit?.();
  }
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
