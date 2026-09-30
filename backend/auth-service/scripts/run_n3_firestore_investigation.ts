/**
 * N3 Firestore bottleneck investigation — read-only instrumentation.
 * Same NearbyDriversService + real Firestore + Memorystore as VPC benchmark;
 * does NOT change production code paths.
 *
 * Env: FIREBASE_PROJECT_ID, REDIS_URL, BENCH_PREFIX (seeded bench drivers).
 */
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { performance } from 'node:perf_hooks';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NearbyDriversService } from '../src/drivers/nearby_service';
import type { N3NearbyDiagnostics } from '../src/drivers/nearby_service';
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
  type RedisGeoClient,
} from '../src/redis/types';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const PREFIX = process.env.BENCH_PREFIX?.trim() ?? '';
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

type RedisTiming = {
  georadiusMs: number;
  mgetMs: number;
  georadiusOps: number;
  mgetOps: number;
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

function instrumentRedis(base: RedisGeoClient): { client: RedisGeoClient; timing: RedisTiming } {
  const timing: RedisTiming = {
    georadiusMs: 0,
    mgetMs: 0,
    georadiusOps: 0,
    mgetOps: 0,
  };
  return {
    timing,
    client: {
      ...base,
      async georadius(input) {
        timing.georadiusOps += 1;
        const t0 = performance.now();
        const hits = await base.georadius(input);
        timing.georadiusMs += performance.now() - t0;
        return hits;
      },
      async mget(keys) {
        timing.mgetOps += 1;
        const t0 = performance.now();
        const vals = await base.mget(keys);
        timing.mgetMs += performance.now() - t0;
        return vals;
      },
      async get(key) {
        return base.get(key);
      },
    },
  };
}

async function listBenchDriverIds(db: Firestore): Promise<string[]> {
  if (!PREFIX) return [];
  const snap = await db.collection('drivers').where('_n3BenchPrefix', '==', PREFIX).get();
  return snap.docs.map((d) => d.id).sort();
}

async function refreshMarkers(redis: RedisGeoClient, ids: string[]) {
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
      locationStreamId: `invest-${PREFIX}`,
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
  if (!getApps().length) {
    initializeApp({ credential: applicationDefault() });
  }
  const rawDb = getFirestore();
  const redisBase = await createRedisGeoClientFromEnv(process.env);
  if (!redisBase) {
    console.error(JSON.stringify({ ok: false, error: 'REDIS_URL missing' }));
    process.exit(2);
  }
  if (!PREFIX) {
    console.error(JSON.stringify({ ok: false, error: 'BENCH_PREFIX missing' }));
    process.exit(2);
  }

  const benchIds = await listBenchDriverIds(rawDb);
  if (benchIds.length < 100) {
    console.error(
      JSON.stringify({
        ok: false,
        error: `expected >=100 bench drivers, got ${benchIds.length}`,
      }),
    );
    process.exit(2);
  }

  const { db, timing: fsTimingRef } = instrumentFirestore(rawDb);
  const { client: redis, timing: redisTimingRef } = instrumentRedis(redisBase);
  const svc = new NearbyDriversService(db, redis);

  const report: Record<string, unknown> = {
    ok: true,
    mode: 'firestore_investigation_vpc',
    startedAt: new Date().toISOString(),
    benchPrefix: PREFIX,
    benchDriverCount: benchIds.length,
    pickup: PICKUP,
    cloudRunRevision: process.env.K_REVISION ?? null,
    callGraph: {
      sequence: [
        'redis.georadius (1×, up to N3_REDIS_GEO_COUNT=100 hits)',
        'redis.mget (1×, one key per geo hit)',
        'for each geo hit in order until limit eligible:',
        '  users/{driverId}.get (sequential await)',
        '  drivers/{driverId}.get (sequential await)',
        '  rides query assignedDriverId==driverId AND state IN busy (limit 1, sequential await)',
      ],
      sequentialFirestore: true,
    },
    scenarios: {} as Record<string, unknown>,
  };

  for (const scenario of SCENARIOS) {
    const runs: unknown[] = [];
    const totals: number[] = [];
    const redisTotals: number[] = [];
    const fsTotals: number[] = [];
    const busyTotals: number[] = [];

    for (let i = 0; i < scenario.runs; i++) {
      Object.assign(fsTimingRef, {
        usersMs: 0,
        driversMs: 0,
        busyQueryMs: 0,
        usersReads: 0,
        driversReads: 0,
        busyQueries: 0,
      });
      Object.assign(redisTimingRef, {
        georadiusMs: 0,
        mgetMs: 0,
        georadiusOps: 0,
        mgetOps: 0,
      });

      await refreshMarkers(redis, benchIds);
      let diagnostics: N3NearbyDiagnostics | undefined;
      const t0 = performance.now();
      await svc.findNearby({
        query: {
          lat: PICKUP.lat,
          lng: PICKUP.lng,
          radiusKm: PICKUP.radiusKm,
          limit: scenario.limit,
        },
        requestId: `n3fs-invest-${scenario.name}-${i}`,
        collectDiagnostics: (d) => {
          diagnostics = d;
        },
      });
      const totalMs = performance.now() - t0;
      const redisMs = redisTimingRef.georadiusMs + redisTimingRef.mgetMs;
      const fsMs =
        fsTimingRef.usersMs + fsTimingRef.driversMs + fsTimingRef.busyQueryMs;
      const appMs = Math.max(0, totalMs - redisMs - fsMs);

      totals.push(totalMs);
      redisTotals.push(redisMs);
      fsTotals.push(fsMs);
      busyTotals.push(fsTimingRef.busyQueryMs);

      runs.push({
        run: i + 1,
        totalMs: Math.round(totalMs),
        latencyBreakdownMs: {
          redis: Math.round(redisMs),
          firestoreUsers: Math.round(fsTimingRef.usersMs),
          firestoreDrivers: Math.round(fsTimingRef.driversMs),
          firestoreBusyChecks: Math.round(fsTimingRef.busyQueryMs),
          firestoreTotal: Math.round(fsMs),
          applicationProcessing: Math.round(appMs),
        },
        diagnostics: diagnostics ?? null,
        instrumentedCounts: {
          usersReads: fsTimingRef.usersReads,
          driversReads: fsTimingRef.driversReads,
          busyQueries: fsTimingRef.busyQueries,
        },
      });
    }

    (report.scenarios as Record<string, unknown>)[scenario.name] = {
      limit: scenario.limit,
      runs,
      summary: {
        runs: scenario.runs,
        totalMs: { p50: pct(totals, 0.5), p95: pct(totals, 0.95) },
        redisMs: { p50: pct(redisTotals, 0.5), p95: pct(redisTotals, 0.95) },
        firestoreTotalMs: { p50: pct(fsTotals, 0.5), p95: pct(fsTotals, 0.95) },
        firestoreBusyMs: { p50: pct(busyTotals, 0.5), p95: pct(busyTotals, 0.95) },
        firestoreShareOfTotalP50:
          pct(totals, 0.5) > 0
            ? Math.round((pct(fsTotals, 0.5) / pct(totals, 0.5)) * 1000) / 10
            : 0,
      },
    };
  }

  await redis.quit?.();
  const reportJson = JSON.stringify(report, null, 2);
  const outDir =
    process.env.N3_BENCH_REPORT_DIR?.trim() ||
    path.join(repoRoot, 'mobile/.e2e_artifacts');
  const outPath = path.join(outDir, 'N3_FIRESTORE_INVESTIGATION_REPORT.json');
  try {
    mkdirSync(outDir, { recursive: true });
    writeFileSync(outPath, reportJson);
  } catch {
    writeFileSync('/tmp/N3_FIRESTORE_INVESTIGATION_REPORT.json', reportJson);
  }
  console.log('INVESTIGATION_REPORT_BEGIN');
  console.log(reportJson);
  console.log('INVESTIGATION_REPORT_END');
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
