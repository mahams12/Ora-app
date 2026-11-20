#!/usr/bin/env bash
# Deploy Firestore rules + RTDB rules + composite indexes to the Firebase/GCP
# project using the active gcloud session (no `firebase` CLI required).
#
# Why this exists: `firebase` CLI may be logged into a different account than
# the gcloud session; the gcloud token is already authorized for the project.
#
# Usage:  PROJECT=oraapp-a9be5 ./scripts/deploy_firebase_infra.sh
# Run from the REPO ROOT (reads firestore.rules, database.rules.json,
# firestore.indexes.json).
#
# Idempotent: existing rulesets are replaced (new release), existing indexes
# are skipped (ALREADY_EXISTS tolerated).
set -euo pipefail

PROJECT="${PROJECT:-oraapp-a9be5}"
RTDB_URL="${RTDB_URL:-https://${PROJECT}-default-rtdb.asia-southeast1.firebasedatabase.app}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

TOKEN="$(gcloud auth application-default print-access-token 2>/dev/null || gcloud auth print-access-token)"
AUTH=(-H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: $PROJECT" -H "Content-Type: application/json")

echo "== Firestore rules -> $PROJECT =="
RULESET=$(jq -n --arg content "$(cat "$ROOT/firestore.rules")" \
  '{source:{files:[{name:"firestore.rules",content:$content}]}}')
RULESET_NAME=$(curl -sf "${AUTH[@]}" -d "$RULESET" \
  "https://firebaserules.googleapis.com/v1/projects/$PROJECT/rulesets" | jq -r .name)
[ -n "$RULESET_NAME" ] || { echo "ruleset create failed"; exit 1; }
curl -sf "${AUTH[@]}" -X PATCH \
  -d "{\"release\":{\"name\":\"projects/$PROJECT/releases/cloud.firestore\",\"rulesetName\":\"$RULESET_NAME\"}}" \
  "https://firebaserules.googleapis.com/v1/projects/$PROJECT/releases/cloud.firestore" >/dev/null
echo "  firestore rules live (ruleset $RULESET_NAME)"

echo "== RTDB rules -> $RTDB_URL =="
curl -sf -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d @"$ROOT/database.rules.json" "$RTDB_URL/.settings/rules.json" >/dev/null
echo "  rtdb rules live"

echo "== Composite indexes -> $PROJECT =="
WANT=$(jq -c '.indexes[]' "$ROOT/firestore.indexes.json")
TOTAL=$(jq '.indexes | length' "$ROOT/firestore.indexes.json")
i=0
echo "$WANT" | while read -r idx; do
  i=$((i + 1))
  CG=$(echo "$idx" | jq -r .collectionGroup)
  SCOPE=$(echo "$idx" | jq -r .queryScope)
  FIELDCONFIG=$(echo "$idx" | jq -c '{fields: [.fields[] | (if .order then {fieldPath, order} elif .arrayConfig then {fieldPath, arrayConfig} else {fieldPath: .fieldPath, vectorConfig: .vectorConfig} end)]}')
  if ! gcloud firestore indexes composite create --project="$PROJECT" \
      --collection-group="$CG" --query-scope="$SCOPE" \
      --field-config="$FIELDCONFIG" --quiet >/dev/null 2>&1; then
    echo "  [$i/$TOTAL] $CG (exists or accepted)"
  else
    echo "  [$i/$TOTAL] $CG created"
  fi
done

echo "== Index readiness =="
NOTREADY=$(gcloud firestore indexes composite list --project="$PROJECT" \
  --format="value(collectionGroup,state)" 2>/dev/null | grep -cv READY || true)
[ "$NOTREADY" = "0" ] && echo "  all indexes READY" || echo "  $NOTREADY index(es) still building — rerun later or check console"
echo "done."
