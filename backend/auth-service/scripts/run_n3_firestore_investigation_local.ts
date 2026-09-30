/**
 * N3 Firestore investigation — real staging Firestore + in-process Redis markers.
 * Uses live bench driver docs (_n3BenchPrefix); Redis GEO/MGET is local (known ~2% on staging).
 * Read-only: does not mutate Firestore.
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { performance } from 'node:perf_hooks';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NearbyDriversService } from '../src/drivers/nearby_service';
import type { N3NearbyDiagnostics } from '../src/drivers/nearby_service';
import { createMemoryRedis } from '../src/redis/memory_redis';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../src/redis/types';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const PREFIX =
  process.env.BENCH_PREFIX?.trim() ?? 'n3bench_fs_invest_20260930T070256Z';
const PICKUP = {
  lat: Number(process.env.N3_BENCH_LAT ?? '31.4127578'),
  lng: Number(process.env.N3_BENCH_LNG ?? '74.1725224'),
  radiusKm: Number(process.env.N3_BENCH_RADIUS_KM ?? '10'),
};

const SCENARIOS = [
  { name: 'candidates_10', limit: 10, runs: 5 },
  { name: 'candidates_30', limit: 30, runs: 5 },
  { name: 'candidates_100', limit: 100, runs: 5 },
] as const;

type FsTiming = {
  usersMs: number;
  driversMs: number;
  busyQueryMs: number;
  usersReads: number;
  driversReads: number;
  busyQueries: number;
};

function instrumentFirestore(db: Firestore): { db: Firestore; timing: FsTiming } {
  const timing: FsTiming = {
    usersMs: 0,
    driversMs: 0,
    busyQueryMs: 0,
    usersReads: 0,
    driversReads: 0,
    busyQueries: 0,
  };
  const origCollection = db.collection.bind(db);

  function wrapQuery(query: FirebaseFirestore.Query, collectionId: string) {
    const origGet = query.get.bind(query);
    return new Proxy(query, {
      get(target, prop) {
        if (prop === 'get') {
          return async () => {
            const t0 = performance.now();
            const snap = await origGet();
            const dt = performance.now() - t0;
            if (collectionId === 'rides') {
              timing.busyQueries += 1;
              timing.busyQueryMs += dt;
            }
            return snap;
          };
        }
        const val = Reflect.get(target, prop);
        if (typeof val === 'function') {
          return (...args: unknown[]) => {
            const next = val.apply(target, args);
            if (next && typeof next.get === 'function') {
              return wrapQuery(next as FirebaseFirestore.Query, collectionId);
            }
            return next;
          };
        }
        return val;
      },
    });
  }

  const wrapped = Object.assign(db, {
    collection(collectionPath: string) {
      const col = origCollection(collectionPath);
      return {
        ...col,
        doc(documentPath: string) {
          const ref = col.doc(documentPath);
          return {
            ...ref,
            get: async () => {
              const t0 = performance.now();
              const snap = await ref.get();
              const dt = performance.now() - t0;
              if (collectionPath === 'users') {
                timing.usersReads += 1;
                timing.usersMs += dt;
              } else if (collectionPath === 'drivers') {
                timing.driversReads += 1;
                timing.driversMs += dt;
              }
              return snap;
            },
          };
        },
        where(field: string, op: FirebaseFirestore.WhereFilterOp, value: unknown) {
          return wrapQuery(col.where(field, op, value), collectionPath);
        },
      };
    },
  }) as Firestore;

  return { db: wrapped, timing };
}

function instrumentRedis(base: RedisGeoClient): { client: RedisGeoClient; timing: { ms: number } } {
  const timing = { ms: 0 };
  return {
    timing,
    client: {
      ...base,
      async georadius(input) {
        const t0 = performance.now();
        const hits = await base.georadius(input);
        timing.ms += performance.now() - t0;
        return hits;
      },
      async mget(keys) {
        const t0 = performance.now();
        const vals = await base.mget(keys);
        timing.ms += performance.now() - t0;
        return vals;
      },
      async get(key) {
        return base.get(key);
      },
    },
  };
}

async function seedRedisForBench(redis: RedisGeoClient, ids: string[]) {
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
      locationStreamId: `local-invest-${PREFIX}`,
      locationSeq: 1,
      acceptedAt: new Date().toISOString(),
    };
    await redis.set(driverOnlineKey(id), JSON.stringify(marker), DRIVER_ONLINE_TTL_SECONDS);
  }
}

function pct(values: number[], p: number): number {
  const s = [...values].sort((a, b) => a - b);
  if (s.length === 0) return 0;
  const idx = Math.min(s.length - 1, Math.floor(s.length * p));
  return Math.round(s[idx]!);
}

async function main() {
  const saPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ??
    path.join(here, '../secrets/service-account.json');
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }
  const rawDb = getFirestore();
  const benchSnap = await rawDb
    .collection('drivers')
    .where('_n3BenchPrefix', '==', PREFIX)
    .get();
  const benchIds = benchSnap.docs.map((d) => d.id).sort();
  if (benchIds.length < 100) {
    console.error(
      JSON.stringify({ ok: false, error: `bench drivers=${benchIds.length} prefix=${PREFIX}` }),
    );
    process.exit(2);
  }

  const { db, timing: fsT } = instrumentFirestore(rawDb);
  const baseRedis = createMemoryRedis();
  const { client: redis, timing: redisT } = instrumentRedis(baseRedis);
  await seedRedisForBench(baseRedis, benchIds);
  const svc = new NearbyDriversService(db, redis);

  const report: Record<string, unknown> = {
    ok: true,
    mode: 'real_firestore_local_redis',
    note:
      'Firestore latency is production staging; Redis is in-process (staging Redis ~2% per MGET benchmark).',
    benchPrefix: PREFIX,
    benchDriverCount: benchIds.length,
    pickup: PICKUP,
    callGraph: {
      steps: [
        '1× redis.georadius (≤100 members)',
        '1× redis.mget',
        'sequential per geo hit until limit: users.get → drivers.get → rides busy query',
      ],
      sequentialFirestore: true,
    },
    scenarios: {} as Record<string, unknown>,
  };

  for (const scenario of SCENARIOS) {
    const runs: unknown[] = [];
    const totals: number[] = [];
    const fsTotals: number[] = [];
    const busyTotals: number[] = [];

    for (let i = 0; i < scenario.runs; i++) {
      await seedRedisForBench(baseRedis, benchIds);
      Object.assign(fsT, {
        usersMs: 0,
        driversMs: 0,
        busyQueryMs: 0,
        usersReads: 0,
        driversReads: 0,
        busyQueries: 0,
      });
      redisT.ms = 0;
      let diagnostics: N3NearbyDiagnostics | undefined;
      const t0 = performance.now();
      await svc.findNearby({
        query: {
          lat: PICKUP.lat,
          lng: PICKUP.lng,
          radiusKm: PICKUP.radiusKm,
          limit: scenario.limit,
        },
        requestId: `n3fs-local-${scenario.name}-${i}`,
        collectDiagnostics: (d) => {
          diagnostics = d;
        },
      });
      const totalMs = performance.now() - t0;
      const fsMs = fsT.usersMs + fsT.driversMs + fsT.busyQueryMs;
      totals.push(totalMs);
      fsTotals.push(fsMs);
      busyTotals.push(fsT.busyQueryMs);

      runs.push({
        run: i + 1,
        totalMs: Math.round(totalMs),
        latencyBreakdownMs: {
          redis: Math.round(redisT.ms),
          firestoreUsers: Math.round(fsT.usersMs),
          firestoreDrivers: Math.round(fsT.driversMs),
          firestoreBusyChecks: Math.round(fsT.busyQueryMs),
          firestoreTotal: Math.round(fsMs),
          applicationProcessing: Math.round(Math.max(0, totalMs - fsMs - redisT.ms)),
        },
        diagnostics,
      });
    }

    (report.scenarios as Record<string, unknown>)[scenario.name] = {
      limit: scenario.limit,
      runs,
      summary: {
        totalMs: { p50: pct(totals, 0.5), p95: pct(totals, 0.95) },
        firestoreTotalMs: { p50: pct(fsTotals, 0.5), p95: pct(fsTotals, 0.95) },
        firestoreBusyMs: { p50: pct(busyTotals, 0.5), p95: pct(busyTotals, 0.95) },
        firestoreShareP50Pct:
          pct(totals, 0.5) > 0
            ? Math.round((pct(fsTotals, 0.5) / pct(totals, 0.5)) * 1000) / 10
            : 0,
      },
    };
  }

  const outDir = path.join(repoRoot, 'mobile/.e2e_artifacts');
  mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, 'N3_FIRESTORE_INVESTIGATION_REPORT.json');
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: true, reportPath: outPath }));
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
