#!/usr/bin/env bash
# Execute in-VPC N3 benchmark (Memorystore + Firestore); pull report from job logs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="${GCP_PROJECT_ID:-ora-app-d8112}"
REGION="${GCP_REGION:-us-central1}"
JOB="${N3_BENCH_JOB:-ora-n3-staging-benchmark}"
VPC_CONNECTOR="${VPC_CONNECTOR:-ora-staging-vpc}"
SECRET_NAME="${REDIS_SECRET_NAME:-ora-staging-redis-url}"
SA_EMAIL="${CLOUD_RUN_RUNTIME_SA:-firebase-adminsdk-fbsvc@${PROJECT}.iam.gserviceaccount.com}"
ART="${ROOT}/../../mobile/.e2e_artifacts"
LOG_TMP="$(mktemp)"

: "${BENCH_PREFIX:?BENCH_PREFIX required}"
# shellcheck disable=SC1091
[[ -f .env ]] && set -a && source .env && set +a
: "${FIREBASE_PROJECT_ID:?}"

IMAGE="$(gcloud run services describe ora-auth-service-staging --project="$PROJECT" --region="$REGION" --format='value(spec.template.spec.containers[0].image)')"

if ! gcloud run jobs describe "$JOB" --project="$PROJECT" --region="$REGION" >/dev/null 2>&1; then
  gcloud run jobs create "$JOB" \
    --project="$PROJECT" \
    --region="$REGION" \
    --image="$IMAGE" \
    --service-account="$SA_EMAIL" \
    --vpc-connector="$VPC_CONNECTOR" \
    --vpc-egress=private-ranges-only \
    --set-secrets="REDIS_URL=${SECRET_NAME}:latest" \
    --set-env-vars="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},NODE_ENV=staging,ORA_ENV=staging,BENCH_PREFIX=${BENCH_PREFIX}" \
    --memory=512Mi \
    --cpu=1 \
    --max-retries=0 \
    --task-timeout=900 \
    --command=node \
    --args="scripts/run_n3_staging_benchmark_vpc.bundle.cjs"
else
  gcloud run jobs update "$JOB" \
    --project="$PROJECT" \
    --region="$REGION" \
    --image="$IMAGE" \
    --set-env-vars="FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID},NODE_ENV=staging,ORA_ENV=staging,BENCH_PREFIX=${BENCH_PREFIX}" \
    --command=node \
    --args="scripts/run_n3_staging_benchmark_vpc.bundle.cjs" \
    --quiet
fi

EXEC="$(gcloud run jobs execute "$JOB" --project="$PROJECT" --region="$REGION" --format='value(name)' --wait)"
EXEC_ID="${EXEC##*/}"
echo "OK benchmark job execution=$EXEC_ID"

gcloud logging read \
  "resource.type=\"cloud_run_job\" AND labels.\"run.googleapis.com/execution_name\"=\"${EXEC_ID}\"" \
  --project="$PROJECT" \
  --limit=500 \
  --format='value(textPayload)' \
  --freshness=30m >"$LOG_TMP" || true

REPORT_NAME="${N3_BENCH_REPORT_NAME:-N3_STAGING_BENCHMARK_REPORT_GETALL.json}"
python3 - "$EXEC_ID" "$ART/$REPORT_NAME" <<'PY'
import json, subprocess, sys

exec_id, out_path = sys.argv[1], sys.argv[2]
project = "ora-app-d8112"
raw = subprocess.check_output(
    [
        "gcloud",
        "logging",
        "read",
        f'resource.type="cloud_run_job" AND labels."run.googleapis.com/execution_name"="{exec_id}"',
        f"--project={project}",
        "--limit=50",
        "--format=json",
        "--freshness=60m",
    ],
    text=True,
)
entries = json.loads(raw) if raw.strip() else []
report = None
for row in entries:
    jp = row.get("jsonPayload") or {}
    if isinstance(jp, dict) and "scenarios" in jp:
        report = jp
        break
if report is None:
    text = "\n".join(
        (row.get("textPayload") or "") for row in reversed(entries)
    )
    begin = False
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if s == "BENCHMARK_REPORT_BEGIN":
            begin = True
            continue
        if s == "BENCHMARK_REPORT_END":
            break
        if begin:
            lines.append(line)
    if lines:
        report = json.loads("\n".join(lines))
if report is None:
    raise SystemExit("benchmark report not found in job logs")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
print(json.dumps({"ok": True, "reportPath": out_path}))
PY

rm -f "$LOG_TMP"
