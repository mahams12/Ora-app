/**
 * Verify a recent open ride carries EXPECTED_OFFER_MAJOR (PKR → paisas).
 * Uses driver open-list + optional Firestore doc read by rideId (no composite index).
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const DRIVER_PHONE = '+923012345677';

function readBaseUrl(): string {
  return readFileSync(path.join(repoRoot, 'mobile/.staging_api_url'), 'utf8')
    .trim()
    .replace(/\/$/, '');
}

function readFirebaseWebApiKey(): string {
  const gs = path.join(repoRoot, 'mobile/android/app/google-services.json');
  const data = JSON.parse(readFileSync(gs, 'utf8')) as {
    client: Array<{ api_key: Array<{ current_key: string }> }>;
  };
  return data.client[0]!.api_key[0]!.current_key;
}

async function idTokenForUid(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const apiKey = readFirebaseWebApiKey();
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  if (!res.ok) throw new Error(`token_exchange_failed ${res.status}`);
  return ((await res.json()) as { idToken: string }).idToken;
}

async function main(): Promise<void> {
  const major = Number(process.env.EXPECTED_OFFER_MAJOR ?? '');
  if (!Number.isFinite(major) || major <= 0) {
    console.log(JSON.stringify({ ok: false, error: 'EXPECTED_OFFER_MAJOR required' }));
    process.exit(1);
  }
  const expectedMinor = Math.round(major) * 100;

  if (getApps().length === 0) {
    const saPath =
      process.env.GOOGLE_APPLICATION_CREDENTIALS ??
      path.join(here, '../secrets/service-account.json');
    initializeApp({
      credential: cert(JSON.parse(readFileSync(saPath, 'utf8'))),
    });
  }

  const driverUid = (await getAuth().getUserByPhoneNumber(DRIVER_PHONE)).uid;
  const base = readBaseUrl();
  const driverToken = await idTokenForUid(driverUid);

  const openRes = await fetch(`${base}/rides/open?limit=30`, {
    headers: { Authorization: `Bearer ${driverToken}`, Accept: 'application/json' },
  });
  const openJson = (await openRes.json()) as {
    data?: { rides?: Array<Record<string, unknown>> };
  };
  const rides = openJson.data?.rides ?? [];
  const openHit =
    rides.find((r) => r['passengerOfferMinor'] === expectedMinor) ?? null;

  let durable: number | null = null;
  let rideId: string | null = null;
  if (openHit && typeof openHit['rideId'] === 'string') {
    rideId = openHit['rideId'] as string;
    const doc = await getFirestore().collection('rides').doc(rideId).get();
    durable = (doc.data()?.passengerOfferMinor as number | undefined) ?? null;
  }

  const out = {
    ok: durable === expectedMinor && openHit != null,
    expectedMinor,
    rideIdPrefix: rideId ? rideId.slice(0, 8) : null,
    openListStatus: openRes.status,
    openListPassengerOfferMinor: openHit?.['passengerOfferMinor'] ?? null,
    openListShowsChosenOffer: openHit?.['passengerOfferMinor'] === expectedMinor,
    durablePassengerOfferMinor: durable,
    durableMatchesChosen: durable === expectedMinor,
  };
  console.log(JSON.stringify(out));
  process.exit(out.ok ? 0 : 1);
}

main().catch((e) => {
  console.log(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(2);
});
