#!/usr/bin/env bash
# Poll Firestore ride state (ops). Usage: ./e2e_watch_ride.sh <rideId>
set -euo pipefail
RIDE_ID="${1:-f0187165-96ea-44bd-a3df-638ea4556fc7}"
cd "$(dirname "$0")/../../backend/auth-service"
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$(pwd)/secrets/service-account.json}"
npx tsx -e "
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
if (!getApps().length) initializeApp({ credential: cert(process.env.GOOGLE_APPLICATION_CREDENTIALS!) });
const db = getFirestore();
const id = process.argv[1];
const r = await db.collection('rides').doc(id).get();
const o = await db.collection('rides').doc(id).collection('offers').get();
console.log(JSON.stringify({
  ride: r.exists ? r.data() : null,
  offers: o.docs.map(d=>({id:d.id,...d.data()})),
}, null, 2));
" "$RIDE_ID"
