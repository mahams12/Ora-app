/**
 * Staging-safe TTL cleanup proof — uses prefixed test doc ids only.
 * Requires GOOGLE_APPLICATION_CREDENTIALS or secrets/service-account.json.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { ExpiresAtCleanupService } from '../src/maintenance/expires_at_cleanup_service';
import {
  IDEMPOTENCY_RECORDS_COLLECTION,
  LOCATION_STREAMS_COLLECTION,
} from '../src/maintenance/expires_at_cleanup_service';
import { PRICING_SNAPSHOTS_COLLECTION } from '../src/pricing/estimate_service';

const PROJECT = 'ora-app-d8112';
const PREFIX = 'ttl-proof-20260929-';

async function main() {
  if (!getApps().length) {
    const saPath = path.join(
      __dirname,
      '../secrets/service-account.json',
    );
    const sa = JSON.parse(readFileSync(saPath, 'utf8'));
    initializeApp({ credential: cert(sa), projectId: PROJECT });
  }
  const db = getFirestore();
  const nowMs = Date.now();
  const pastIso = new Date(nowMs - 60_000).toISOString();
  const futureIso = new Date(nowMs + 3600_000).toISOString();

  const ids = {
    idemExpired: `${PREFIX}idem-expired`,
    idemLive: `${PREFIX}idem-live`,
    psExpired: `${PREFIX}ps-expired`,
    psLive: `${PREFIX}ps-live`,
    locExpired: `${PREFIX}loc-expired`,
    locLive: `${PREFIX}loc-live`,
  };

  await db.collection(IDEMPOTENCY_RECORDS_COLLECTION).doc(ids.idemExpired).set({
    expiresAt: pastIso,
    status: 'SUCCEEDED',
    requestHash: 'proof',
    actorId: 'proof',
  });
  await db.collection(IDEMPOTENCY_RECORDS_COLLECTION).doc(ids.idemLive).set({
    expiresAt: futureIso,
    status: 'SUCCEEDED',
    requestHash: 'proof',
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

  const svc = new ExpiresAtCleanupService(db);
  const summary = await svc.runCleanup({ limit: 50, nowMs });

  const checks: Array<[string, string, boolean]> = [];
  for (const [label, id] of [
    ['idemExpired', ids.idemExpired],
    ['idemLive', ids.idemLive],
    ['psExpired', ids.psExpired],
    ['psLive', ids.psLive],
    ['locExpired', ids.locExpired],
    ['locLive', ids.locLive],
  ] as const) {
    const col =
      label.startsWith('idem')
        ? IDEMPOTENCY_RECORDS_COLLECTION
        : label.startsWith('ps')
          ? PRICING_SNAPSHOTS_COLLECTION
          : LOCATION_STREAMS_COLLECTION;
    const snap = await db.collection(col).doc(id).get();
    const shouldExist = label.endsWith('Live');
    checks.push([label, shouldExist ? 'exists' : 'deleted', snap.exists === shouldExist]);
  }

  console.log(JSON.stringify({ summary, checks }, null, 2));
  const ok = checks.every((c) => c[2]);
  if (!ok) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
