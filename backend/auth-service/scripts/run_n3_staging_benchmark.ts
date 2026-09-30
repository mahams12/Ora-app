/**
 * Real staging N3 benchmark — calls Cloud Run /internal/drivers/nearby and
 * pulls N3_NEARBY metrics from Cloud Logging via X-Request-Id correlation.
 *
 * Requires: .env ORA_INTERNAL_WORKER_TOKEN, REDIS_URL (for seed), gcloud auth.
 */
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const stagingUrlFile = path.join(repoRoot, 'mobile/.staging_api_url');

type Scenario = { name: string; limit: number; runs: number };
const SCENARIOS: Scenario[] = [
  { name: 'candidates_10', limit: 10, runs: 5 },
  { name: 'candidates_30', limit: 30, runs: 5 },
  { name: 'candidates_100', limit: 100, runs: 5 },
];

const PICKUP = {
  lat: process.env.N3_BENCH_LAT ?? '31.4127578',
  lng: process.env.N3_BENCH_LNG ?? '74.1725224',
  radiusKm: process.env.N3_BENCH_RADIUS_KM ?? '10',
};

const PROJECT = process.env.GCP_PROJECT_ID ?? 'ora-app-d8112';
const SERVICE = process.env.CLOUD_RUN_SERVICE ?? 'ora-auth-service-staging';
const REGION = process.env.GCP_REGION ?? 'us-central1';

function loadEnv(): Record<string, string> {
  const envPath = path.join(here, '../.env');
  const out: Record<string, string> = { ...process.env } as Record<string, string>;
  try {
    const raw = readFileSync(envPath, 'utf8');
    for (const line of raw.split('\n')) {
      const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (!m) continue;
      out[m[1]!] = m[2]!.replace(/^['"]|['"]$/g, '');
    }
  } catch {
    /* optional */
  }
  return out;
}

function gcloud(args: string[]): string {
  const r = spawnSync('gcloud', args, { encoding: 'utf8' });
  if (r.status !== 0) {
    throw new Error(`gcloud ${args.join(' ')} failed: ${r.stderr || r.stdout}`);
  }
  return (r.stdout || '').trim();
}

function curlNearby(base: string, token: string, limit: number, requestId: string) {
  const url = `${base.replace(/\/$/, '')}/internal/drivers/nearby`;
  const r = spawnSync(
    'curl',
    [
      '-sS',
      '-w',
      '\n__HTTP_CODE__%{http_code}\n__TIME_TOTAL__%{time_total}\n',
      '-G',
      url,
      '-H',
      `X-Ora-Worker-Token: ${token}`,
      '-H',
      `X-Request-Id: ${requestId}`,
      '--data-urlencode',
      `lat=${PICKUP.lat}`,
      '--data-urlencode',
      `lng=${PICKUP.lng}`,
      '--data-urlencode',
      `radiusKm=${PICKUP.radiusKm}`,
      '--data-urlencode',
      `limit=${limit}`,
    ],
    { encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 },
  );
  const out = r.stdout || '';
  const codeM = out.match(/__HTTP_CODE__(\d+)/);
  const timeM = out.match(/__TIME_TOTAL__([\d.]+)/);
  const body = out.split('\n__HTTP_CODE__')[0] ?? '';
  return {
    httpCode: codeM ? Number(codeM[1]) : 0,
    curlTimeSec: timeM ? Number(timeM[1]) : 0,
    body,
  };
}

function sleepMs(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchN3Log(requestId: string): Promise<Record<string, unknown> | null> {
  const filter = [
    `resource.type="cloud_run_revision"`,
    `resource.labels.service_name="${SERVICE}"`,
    `(jsonPayload.operation="N3_NEARBY" OR jsonPayload.msg="N3_NEARBY")`,
    `jsonPayload.requestId="${requestId}"`,
  ].join(' AND ');
  for (let attempt = 0; attempt < 8; attempt++) {
    const raw = gcloud([
      'logging',
      'read',
      filter,
      `--project=${PROJECT}`,
      '--limit=1',
      '--format=json',
      `--freshness=${attempt === 0 ? '5m' : '15m'}`,
    ]);
    if (raw && raw !== '[]') {
      const rows = JSON.parse(raw) as Array<{ jsonPayload?: Record<string, unknown> }>;
      const payload = rows[0]?.jsonPayload;
      if (payload) return payload;
    }
    await sleepMs(2000);
  }
  return null;
}

async function main() {
  const env = loadEnv();
  const token = env.ORA_INTERNAL_WORKER_TOKEN?.trim();
  if (!token) {
    console.error(JSON.stringify({ ok: false, error: 'ORA_INTERNAL_WORKER_TOKEN missing' }));
    process.exit(2);
  }

  let base = env.STAGING_API_BASE_URL?.trim();
  if (!base) {
    try {
      base = readFileSync(stagingUrlFile, 'utf8').trim();
    } catch {
      console.error(JSON.stringify({ ok: false, error: 'mobile/.staging_api_url missing' }));
      process.exit(2);
    }
  }

  const healthUrl = base.replace(/\/v1\/?$/, '') + '/healthz/';
  const health = spawnSync('curl', ['-sS', '-o', '/dev/null', '-w', '%{http_code}', healthUrl], {
    encoding: 'utf8',
  });
  const revision = gcloud([
    'run',
    'services',
    'describe',
    SERVICE,
    `--project=${PROJECT}`,
    `--region=${REGION}`,
    '--format=value(status.latestReadyRevisionName)',
  ]);

  const report: Record<string, unknown> = {
    ok: true,
    startedAt: new Date().toISOString(),
    cloudRun: { service: SERVICE, revision, healthUrl, healthCode: health.stdout?.trim() },
    pickup: PICKUP,
    scenarios: {} as Record<string, unknown>,
  };

  // Warmup (cold start isolation for scenario runs, not for conclusion)
  const warmId = `n3bench-warm-${Date.now()}`;
  curlNearby(base, token, 10, warmId);

  const seedJob = path.join(here, 'run_n3_staging_seed_job.sh');

  for (const scenario of SCENARIOS) {
    spawnSync('bash', [seedJob, 'refresh', '100'], {
      cwd: here,
      env: process.env,
      stdio: 'inherit',
    });
    const runs: Record<string, unknown>[] = [];
    for (let i = 0; i < scenario.runs; i++) {
      const requestId = `n3bench-${scenario.name}-${Date.now()}-${i}`;
      const started = Date.now();
      const curl = curlNearby(base, token, scenario.limit, requestId);
      const log = await fetchN3Log(requestId);
      void started;
      let resultCount = 0;
      try {
        const parsed = JSON.parse(curl.body) as { data?: { candidates?: unknown[] } };
        resultCount = parsed.data?.candidates?.length ?? 0;
      } catch {
        /* ignore */
      }
      runs.push({
        run: i + 1,
        requestId,
        httpCode: curl.httpCode,
        curlTimeSec: curl.curlTimeSec,
        resultCount,
        log: log ?? { missing: true },
      });
    }
    (report.scenarios as Record<string, unknown>)[scenario.name] = {
      limit: scenario.limit,
      runs,
    };
  }

  const outDir = path.join(repoRoot, 'mobile/.e2e_artifacts');
  mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, 'N3_STAGING_BENCHMARK_REPORT.json');
  writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ok: true, reportPath: outPath, revision }));
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
