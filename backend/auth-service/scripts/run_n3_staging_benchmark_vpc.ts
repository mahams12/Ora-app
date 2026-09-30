/**
 * N3 staging benchmark inside VPC (same process as marker refresh — avoids 30s TTL gap).
 * Uses real Firestore (ADC) + Memorystore (REDIS_URL secret). No HTTP; same NearbyDriversService.
 */
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NearbyDriversService } from '../src/drivers/nearby_service';
import {
  computeN3FirestoreRpcTotal,
  type N3NearbyDiagnostics,
} from '../src/drivers/nearby_service';
import { createRedisGeoClientFromEnv } from '../src/redis/client';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../src/redis/types';

const here = path.dirname(
  typeof __dirname !== 'undefined' ? __filename : fileURLToPath(import.meta.url),
);
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

async function listBenchDriverIds(
  db: ReturnType<typeof getFirestore>,
): Promise<string[]> {
  if (!PREFIX) return [];
  const snap = await db.collection('drivers').where('_n3BenchPrefix', '==', PREFIX).get();
  return snap.docs.map((d) => d.id).sort();
}

async function refreshMarkers(
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
    await redis.set(driverOnlineKey(id), JSON.stringify(marker), DRIVER_ONLINE_TTL_SECONDS);
  }
}

function summarizeRuns(runs: Array<{ log: N3NearbyDiagnostics & { durationMs: number; resultCount: number } }>) {
  const d = runs.map((r) => r.log.durationMs).sort((a, b) => a - b);
  const p95 = d[Math.min(d.length - 1, Math.floor(d.length * 0.95))] ?? 0;
  const med = d[Math.floor(d.length / 2)] ?? 0;
  const last = runs[runs.length - 1]!.log;
  return { p95DurationMs: p95, medianDurationMs: med, lastRun: last, runs: runs.length };
}

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: applicationDefault() });
  }
  const db = getFirestore();
  const redis = await createRedisGeoClientFromEnv(process.env);
  if (!redis) {
    console.error(JSON.stringify({ ok: false, error: 'REDIS_URL missing' }));
    process.exit(2);
  }
  if (!PREFIX) {
    console.error(JSON.stringify({ ok: false, error: 'BENCH_PREFIX missing' }));
    process.exit(2);
  }

  const benchIds = await listBenchDriverIds(db);
  if (benchIds.length < 100) {
    console.error(
      JSON.stringify({
        ok: false,
        error: `expected >=100 bench drivers, got ${benchIds.length}`,
      }),
    );
    process.exit(2);
  }

  const svc = new NearbyDriversService(db, redis);
  const report: Record<string, unknown> = {
    ok: true,
    mode: 'vpc_in_process',
    startedAt: new Date().toISOString(),
    benchPrefix: PREFIX,
    benchDriverCount: benchIds.length,
    pickup: PICKUP,
    cloudRunRevision: process.env.K_REVISION ?? null,
    scenarios: {} as Record<string, unknown>,
  };

  for (const scenario of SCENARIOS) {
    const runLogs: Array<{
      run: number;
      log: N3NearbyDiagnostics & { durationMs: number; resultCount: number };
    }> = [];
    for (let i = 0; i < scenario.runs; i++) {
      await refreshMarkers(redis, benchIds);
      let diagnostics: N3NearbyDiagnostics | undefined;
      const t0 = Date.now();
      const result = await svc.findNearby({
        query: {
          lat: PICKUP.lat,
          lng: PICKUP.lng,
          radiusKm: PICKUP.radiusKm,
          limit: scenario.limit,
        },
        requestId: `n3bench-vpc-${scenario.name}-${i}`,
        collectDiagnostics: (d) => {
          diagnostics = d;
        },
      });
      const durationMs = Date.now() - t0;
      const baseDiag = diagnostics ?? {
        geoHits: 0,
        redisGetCount: 0,
        firestoreUsersReads: 0,
        firestoreDriversReads: 0,
        firestoreUsersBatchRpcs: 0,
        firestoreDriversBatchRpcs: 0,
        firestoreBusyRideQueries: 0,
        firestoreRpcTotal: 0,
        eligibleCount: 0,
        rejected: {},
      };
      const log = {
        ...baseDiag,
        firestoreRpcTotal:
          baseDiag.firestoreRpcTotal || computeN3FirestoreRpcTotal(baseDiag),
        durationMs,
        resultCount: result.candidates.length,
      } as N3NearbyDiagnostics & { durationMs: number; resultCount: number };
      runLogs.push({ run: i + 1, log });
    }
    (report.scenarios as Record<string, unknown>)[scenario.name] = {
      limit: scenario.limit,
      summary: summarizeRuns(runLogs),
      runs: runLogs,
    };
  }

  await redis.quit?.();
  const reportJson = JSON.stringify(report, null, 2);
  const outDir =
    process.env.N3_BENCH_REPORT_DIR?.trim() ||
    path.join(repoRoot, 'mobile/.e2e_artifacts');
  const reportName =
    process.env.N3_BENCH_REPORT_NAME?.trim() ||
    'N3_STAGING_BENCHMARK_REPORT_GETALL.json';
  const outPath = path.join(outDir, reportName);
  try {
    mkdirSync(outDir, { recursive: true });
    writeFileSync(outPath, reportJson);
  } catch {
    // Cloud Run Job has no workspace mount; report is pulled from logs.
    writeFileSync('/tmp/N3_STAGING_BENCHMARK_REPORT.json', reportJson);
  }
  console.log('BENCHMARK_REPORT_BEGIN');
  console.log(JSON.stringify(report));
  console.log('BENCHMARK_REPORT_END');
  console.log(JSON.stringify({ ok: true, reportPath: outPath }));
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
