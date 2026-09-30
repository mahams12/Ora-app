#!/usr/bin/env bash
# Full N3 staging benchmark: deploy (optional) → seed → measure → cleanup.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEPLOY="${N3_BENCH_DEPLOY:-1}"
BENCH_PREFIX="${BENCH_PREFIX:-n3bench_$(date -u +%Y%m%dT%H%M%SZ)}"
export BENCH_PREFIX

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

echo "== N3 staging benchmark prefix=$BENCH_PREFIX =="

if [[ "$DEPLOY" == "1" ]]; then
  echo "== deploy Cloud Run (current source) =="
  chmod +x scripts/deploy_staging_cloud_run.sh
  ./scripts/deploy_staging_cloud_run.sh
else
  echo "== skip deploy (N3_BENCH_DEPLOY=0) =="
fi

if [[ -z "${ORA_INTERNAL_WORKER_TOKEN:-}" ]]; then
  echo "BLOCKED: ORA_INTERNAL_WORKER_TOKEN not set in .env" >&2
  exit 2
fi

echo "== bundle N3 seed for Cloud Run Job image =="
npx esbuild scripts/seed_n3_staging_benchmark.ts --bundle --platform=node --format=cjs \
  --outfile=scripts/seed_n3_staging_benchmark.bundle.cjs --external:firebase-admin >/dev/null

echo "== wire Memorystore Redis to Cloud Run (idempotent) =="
chmod +x scripts/wire_staging_redis.sh
./scripts/wire_staging_redis.sh

echo "== seed 100 approved/online bench drivers (VPC Cloud Run Job) =="
chmod +x scripts/run_n3_staging_seed_job.sh
./scripts/run_n3_staging_seed_job.sh seed 100

echo "== bundle in-VPC benchmark runner =="
npx esbuild scripts/run_n3_staging_benchmark_vpc.ts --bundle --platform=node --format=cjs \
  --outfile=scripts/run_n3_staging_benchmark_vpc.bundle.cjs --external:firebase-admin >/dev/null

echo "== deploy image with benchmark bundles (preserves Redis wiring) =="
chmod +x scripts/deploy_staging_cloud_run.sh
./scripts/deploy_staging_cloud_run.sh

echo "== run benchmark in VPC (10 / 30 / 100 × 5; same NearbyDriversService) =="
chmod +x scripts/run_n3_staging_benchmark_vpc_job.sh
./scripts/run_n3_staging_benchmark_vpc_job.sh

echo "== cleanup bench drivers (VPC Cloud Run Job) =="
./scripts/run_n3_staging_seed_job.sh cleanup 100

echo "== vitest (N3 diagnostics + full suite) =="
npm run build
npm test

echo "DONE — see mobile/.e2e_artifacts/N3_STAGING_BENCHMARK_REPORT.json"
