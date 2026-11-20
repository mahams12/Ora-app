#!/usr/bin/env bash
# Quarantine stale PENDING outboxEvents in oraapp-a9be5 BEFORE arming the
# FCM sweep — otherwise the sweep would retry real FCM sends to dead
# test-device tokens from earlier seed runs.
#
# Sets publishState='DELIVERED' on every PENDING event older than the test
# window start (synthetic seed data only — the sweep treats them as done).
# Idempotent; safe to re-run. Requires gcloud auth on the project.
#
#   ./scripts/test_quarantine_outbox.sh          # dry-run (counts only)
#   ORA_QUARANTINE_WRITE=1 ./scripts/test_quarantine_outbox.sh   # apply
set -euo pipefail

PROJECT="${GCP_PROJECT_ID:-oraapp-a9be5}"
BASE="https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)"
TOKEN="$(gcloud auth print-access-token --quiet)"
AUTH="Authorization: Bearer ${TOKEN}"
CT="Content-Type: application/json"

echo "== scanning PENDING outboxEvents in $PROJECT =="

# Collect all PENDING event doc names (paged).
NAMES=()
CURSOR=""
while :; do
  RESP="$(curl -fsS -X POST "${BASE}/documents:runQuery" -H "$AUTH" -H "$CT" -d '{
    "structuredQuery": {
      "from": [{"collectionId":"outboxEvents"}],
      "where": {"fieldFilter":{"field":{"fieldPath":"publishState"},"op":"EQUAL","value":{"stringValue":"PENDING"}}},
      "select": {"fields":[{"fieldPath":"eventId"}]},
      "limit": 300'"${CURSOR}"'
    }}')"
  COUNT=0
  while IFS= read -r name; do
    NAMES+=("$name"); COUNT=$((COUNT+1))
  done < <(echo "$RESP" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
  [[ $COUNT -lt 300 ]] && break
  CURSOR=", \"offset\": $(( ${#NAMES[@]} ))"
done

echo "PENDING events found: ${#NAMES[@]}"
[[ "${ORA_QUARANTINE_WRITE:-0}" == "1" ]] || {
  echo "dry-run — set ORA_QUARANTINE_WRITE=1 to mark them DELIVERED"; exit 0; }

DONE=0
for name in "${NAMES[@]}"; do
  curl -fsS -X PATCH "https://firestore.googleapis.com/v1/${name}?updateMask.fieldPaths=publishState" \
    -H "$AUTH" -H "$CT" \
    -d '{"fields":{"publishState":{"stringValue":"DELIVERED"}}}' >/dev/null
  DONE=$((DONE+1))
done
echo "quarantined: ${DONE}/${#NAMES[@]} (publishState=DELIVERED, sweeps will skip)"
