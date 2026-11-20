#!/usr/bin/env bash
# Staging HTTPS cleanup proof — never prints worker token.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PROJECT=ora-app-d8112
REGION=us-central1
SERVICE=ora-auth-service-staging
BASE_URL="https://ora-auth-service-staging-2zmxvrrs7a-uc.a.run.app"
PREFIX="ttl-remote-proof-$$-"

WORKER_TOKEN="$(
  gcloud run services describe "$SERVICE" \
    --project="$PROJECT" \
    --region="$REGION" \
    --format=json \
    | python3 -c "import json,sys; d=json.load(sys.stdin); env=d['spec']['template']['spec']['containers'][0]['env']; print(next(e['value'] for e in env if e.get('name')=='ORA_INTERNAL_WORKER_TOKEN'), end='')"
)"

if [[ -z "$WORKER_TOKEN" || ${#WORKER_TOKEN} -lt 16 ]]; then
  echo "ERROR: ORA_INTERNAL_WORKER_TOKEN not configured on Cloud Run" >&2
  exit 2
fi

npx --yes esbuild scripts/seed_remote_ttl_proof.ts --bundle --platform=node --format=cjs --outfile=.tmp/seed_remote_ttl_proof.cjs >/dev/null 2>&1
PREFIX="$PREFIX" node .tmp/seed_remote_ttl_proof.cjs

HTTP_CODE="$(
  curl -sS -o /tmp/cleanup_remote.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/internal/storage/expires-at-cleanup?limit=50" \
    -H "X-Ora-Worker-Token: ${WORKER_TOKEN}" \
    -H "Content-Type: application/json"
)"

echo "CLEANUP_HTTP=${HTTP_CODE}"
python3 -c "import json; print(json.dumps(json.load(open('/tmp/cleanup_remote.json')), indent=2))" | head -40

PREFIX="$PREFIX" node .tmp/seed_remote_ttl_proof.cjs verify
