/**
 * Seed or verify prefixed TTL proof docs (staging only). Never logs secrets.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import {
  IDEMPOTENCY_RECORDS_COLLECTION,
  LOCATION_STREAMS_COLLECTION,
} from '../src/maintenance/expires_at_cleanup_service';
import { PRICING_SNAPSHOTS_COLLECTION } from '../src/pricing/estimate_service';

const PROJECT = 'ora-app-d8112';
const PREFIX = process.env.PREFIX ?? 'ttl-remote-proof-';
const MODE = process.argv[2] ?? 'seed';

function initDb() {
  if (!getApps().length) {
    const saPath = path.join(__dirname, '../secrets/service-account.json');
    const sa = JSON.parse(readFileSync(saPath, 'utf8'));
    initializeApp({ credential: cert(sa), projectId: PROJECT });
  }
  return getFirestore();
}

const ids = {
  idemExpired: `${PREFIX}idem-expired`,
  idemLive: `${PREFIX}idem-live`,
  psExpired: `${PREFIX}ps-expired`,
  psLive: `${PREFIX}ps-live`,
  locExpired: `${PREFIX}loc-expired`,
  locLive: `${PREFIX}loc-live`,
};

async function seed(db: ReturnType<typeof getFirestore>) {
  const nowMs = Date.now();
  const pastIso = new Date(nowMs - 120_000).toISOString();
  const futureIso = new Date(nowMs + 3600_000).toISOString();

  await db.collection(IDEMPOTENCY_RECORDS_COLLECTION).doc(ids.idemExpired).set({
    expiresAt: pastIso,
    status: 'SUCCEEDED',
    requestHash: 'remote-proof',
    actorId: 'proof',
  });
  await db.collection(IDEMPOTENCY_RECORDS_COLLECTION).doc(ids.idemLive).set({
    expiresAt: futureIso,
    status: 'SUCCEEDED',
    requestHash: 'remote-proof',
    actorId: 'proof',
  });
  await db.collection(PRICING_SNAPSHOTS_COLLECTION).doc(ids.psExpired).set({
    snapshotId: ids.psExpired,
    expiresAt: pastIso,
    recommendedFareMinor: 1,
  });
  await db.collection(PRICING_SNAPSHOTS_COLLECTION).doc(ids.psLive).set({
    snapshotId: ids.psLive,
    expiresAt: futureIso,
    recommendedFareMinor: 2,
  });
  await db.collection(LOCATION_STREAMS_COLLECTION).doc(ids.locExpired).set({
    driverId: 'proof',
    streamState: 'ACTIVE',
    expiresAt: pastIso,
    lastAcceptedSeq: 0,
  });
  await db.collection(LOCATION_STREAMS_COLLECTION).doc(ids.locLive).set({
    driverId: 'proof',
    streamState: 'ACTIVE',
    expiresAt: futureIso,
    lastAcceptedSeq: 1,
    activeStreamId: 'proof-stream',
  });
  console.log(JSON.stringify({ mode: 'seed', prefix: PREFIX, ok: true }));
}

async function verify(db: ReturnType<typeof getFirestore>) {
  const checks: Record<string, boolean> = {};
  const expect: Array<[string, string, string]> = [
    ['idemExpired', IDEMPOTENCY_RECORDS_COLLECTION, ids.idemExpired],
    ['idemLive', IDEMPOTENCY_RECORDS_COLLECTION, ids.idemLive],
    ['psExpired', PRICING_SNAPSHOTS_COLLECTION, ids.psExpired],
    ['psLive', PRICING_SNAPSHOTS_COLLECTION, ids.psLive],
    ['locExpired', LOCATION_STREAMS_COLLECTION, ids.locExpired],
    ['locLive', LOCATION_STREAMS_COLLECTION, ids.locLive],
  ];
  for (const [label, col, id] of expect) {
    const snap = await db.collection(col).doc(id).get();
    const shouldExist = label.endsWith('Live');
    checks[label] = snap.exists === shouldExist;
  }
  console.log(JSON.stringify({ mode: 'verify', prefix: PREFIX, checks }, null, 2));
  if (!Object.values(checks).every(Boolean)) process.exit(1);
}

async function main() {
  const db = initDb();
  if (MODE === 'seed') await seed(db);
  else if (MODE === 'verify') await verify(db);
  else throw new Error('usage: seed|verify');
}

main().catch((err) => {
  console.error(String(err));
  process.exit(1);
});
