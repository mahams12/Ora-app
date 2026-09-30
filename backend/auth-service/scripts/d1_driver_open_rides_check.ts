/**
 * Staging revalidation: GET /v1/rides/open for D1 driver (+923012345677).
 * Usage: npx tsx scripts/d1_driver_open_rides_check.ts [optionalRideId]
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const targetRideId = process.argv[2]?.trim();
const driverUid = 'SRjL7BJgCKTduhtpjtYMRZMq5fD2';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

async function idTokenForUid(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  const apiKey = JSON.parse(readFileSync(gs, 'utf8')).client[0].api_key[0]
    .current_key as string;
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!res.ok) {
    throw new Error(`token_exchange status=${res.status}`);
  }
  const body = (await res.json()) as { idToken: string };
  return body.idToken;
}

async function main(): Promise<void> {
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }
  const base = readFileSync(path.join(repoRoot, 'mobile/.staging_api_url'), 'utf8')
    .trim()
    .replace(/\/$/, '');
  const idToken = await idTokenForUid(driverUid);
  const res = await fetch(`${base}/rides/open`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const body = (await res.json()) as {
    data?: { rides?: Array<{ rideId: string }> };
  };
  const rides = body.data?.rides ?? [];
  const hit = targetRideId
    ? rides.some((r) => r.rideId === targetRideId)
    : undefined;
  console.log(
    JSON.stringify({
      httpStatus: res.status,
      rideCount: rides.length,
      targetRideId: targetRideId ?? null,
      targetPresent: hit,
      rideIds: rides.map((r) => r.rideId).slice(0, 10),
    }),
  );
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
