#!/usr/bin/env bash
set -euo pipefail
cd "/Users/jazimsaeed/Desktop/Ora App/backend/auth-service"
export PORT=8080
export FIREBASE_PROJECT_ID=ora-app-d8112
export GOOGLE_APPLICATION_CREDENTIALS="/Users/jazimsaeed/Desktop/Ora App/backend/auth-service/secrets/service-account.json"
export REQUIRE_APP_CHECK=false
export NODE_OPTIONS="${NODE_OPTIONS:-}"
echo "starting $(date)" >> /tmp/ora_auth.log
exec ./node_modules/.bin/tsx src/index.ts >> /tmp/ora_auth.log 2>&1
