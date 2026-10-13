/**
 * Staging proof for Phase 5D — passenger offer within bounds.
 * Does not log tokens or secrets.
 *
 * Usage (from backend/auth-service):
 *   GOOGLE_APPLICATION_CREDENTIALS=secrets/service-account.json \
 *   npx tsx scripts/staging_5d_passenger_offer_proof.ts
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');
const PASSENGER_PHONE = '+923012345678';
const DRIVER_PHONE = '+923012345677';

const PICKUP = {
  lat: 31.5204,
  lng: 74.3587,
  address: 'Lahore Fort, Lahore',
};
const DESTINATION = {
  lat: 31.5497,
  lng: 74.3436,
  address: 'Data Darbar, Lahore',
};

function readBaseUrl(): string {
  const fromEnv = process.env.STAGING_API_BASE_URL?.trim();
  if (fromEnv) return fromEnv.replace(/\/$/, '');
  return readFileSync(path.join(repoRoot, 'mobile/.staging_api_url'), 'utf8')
    .trim()
    .replace(/\/$/, '');
}

function readFirebaseWebApiKey(): string {
  const fromEnv = process.env.FIREBASE_WEB_API_KEY?.trim();
  if (fromEnv) return fromEnv;
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

async function apiJson(
  base: string,
  method: string,
  route: string,
  opts: { bearer?: string; body?: unknown; idempotencyKey?: string } = {},
): Promise<{ status: number; json: Record<string, unknown> }> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (opts.bearer) headers.Authorization = `Bearer ${opts.bearer}`;
  if (opts.body != null) headers['Content-Type'] = 'application/json';
  if (opts.idempotencyKey) headers['Idempotency-Key'] = opts.idempotencyKey;
  const res = await fetch(`${base}${route}`, {
    method,
    headers,
    body: opts.body != null ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  let json: Record<string, unknown> = {};
  try {
    json = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    json = { raw: text.slice(0, 200) };
  }
  return { status: res.status, json };
}

async function main(): Promise<void> {
  if (getApps().length === 0) {
    const saPath =
      process.env.GOOGLE_APPLICATION_CREDENTIALS ??
      path.join(here, '../secrets/service-account.json');
    initializeApp({
      credential: cert(JSON.parse(readFileSync(saPath, 'utf8'))),
    });
  }

  const base = readBaseUrl();
  const passengerUid = (await getAuth().getUserByPhoneNumber(PASSENGER_PHONE))
    .uid;
  const driverUid = (await getAuth().getUserByPhoneNumber(DRIVER_PHONE)).uid;
  const passengerToken = await idTokenForUid(passengerUid);
  const driverToken = await idTokenForUid(driverUid);

  const report: Record<string, unknown> = {
    artifact: 'PASSENGER_FARE_OFFER_STAGING_API_PROOF',
    baseUrlHost: new URL(base).host,
    startedAt: new Date().toISOString(),
  };

  const estimate = await apiJson(base, 'POST', '/pricing/estimate', {
    bearer: passengerToken,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      category: 'easy',
      city: 'lahore',
      serviceType: 'ride',
    },
  });
  report.estimateStatus = estimate.status;
  if (estimate.status !== 200) {
    report.verdict = 'FAIL_ESTIMATE';
    report.estimateError = estimate.json['error'] ?? estimate.json;
    writeReport(report);
    process.exit(1);
  }

  const est = estimate.json['data'] as {
    pricingSnapshotId: string;
    recommendedFareMinor: number;
    offerBoundMinMinor: number;
    offerBoundMaxMinor: number;
  };
  if (!est?.pricingSnapshotId) {
    report.verdict = 'FAIL_ESTIMATE_SHAPE';
    report.estimateKeys = Object.keys(estimate.json);
    writeReport(report);
    process.exit(1);
  }
  report.pricingSnapshotIdPrefix = est.pricingSnapshotId.slice(0, 12);
  report.recommendedFareMinor = est.recommendedFareMinor;
  report.offerBoundMinMinor = est.offerBoundMinMinor;
  report.offerBoundMaxMinor = est.offerBoundMaxMinor;

  // Choose a valid amount different from recommended when possible.
  let chosen = est.recommendedFareMinor + 1000;
  if (chosen > est.offerBoundMaxMinor) {
    chosen = est.recommendedFareMinor - 1000;
  }
  if (chosen < est.offerBoundMinMinor || chosen === est.recommendedFareMinor) {
    chosen = est.offerBoundMinMinor;
  }
  report.chosenPassengerOfferMinor = chosen;
  report.chosenDiffersFromRecommended = chosen !== est.recommendedFareMinor;

  const outOfRange = est.offerBoundMaxMinor + 10000;
  const badCreate = await apiJson(base, 'POST', '/rides', {
    bearer: passengerToken,
    idempotencyKey: `5d-bad-${randomUUID()}`,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      category: 'easy',
      serviceType: 'ride',
      city: 'lahore',
      passengerOfferMinor: outOfRange,
      pricingSnapshotId: est.pricingSnapshotId,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
  });
  report.outOfRangeCreateStatus = badCreate.status;
  const badErr = badCreate.json['error'] as { code?: string } | undefined;
  report.outOfRangeErrorCode = badErr?.code ?? null;
  report.outOfRangeBlocked =
    badCreate.status >= 400 &&
    (badErr?.code === 'FARE_OUT_OF_BOUNDS' ||
      badCreate.status === 422 ||
      String(JSON.stringify(badCreate.json)).includes('FARE_OUT_OF_BOUNDS'));

  const goodCreate = await apiJson(base, 'POST', '/rides', {
    bearer: passengerToken,
    idempotencyKey: `5d-ok-${randomUUID()}`,
    body: {
      pickup: PICKUP,
      destination: DESTINATION,
      category: 'easy',
      serviceType: 'ride',
      city: 'lahore',
      passengerOfferMinor: chosen,
      pricingSnapshotId: est.pricingSnapshotId,
      paymentMethod: 'CASH',
      passengerCount: 1,
    },
  });
  report.createStatus = goodCreate.status;
  const createData = (goodCreate.json['data'] ?? goodCreate.json) as {
    rideId?: string;
    passengerOfferMinor?: number;
  };
  const rideId = String(createData.rideId ?? '');
  report.rideIdPrefix = rideId ? rideId.slice(0, 8) : null;
  report.createResponsePassengerOfferMinor =
    createData.passengerOfferMinor ?? null;

  let durableOffer: number | null = null;
  if (rideId && goodCreate.status >= 200 && goodCreate.status < 300) {
    const doc = await getFirestore().collection('rides').doc(rideId).get();
    durableOffer = (doc.data()?.passengerOfferMinor as number | undefined) ?? null;
    report.durablePassengerOfferMinor = durableOffer;
    report.durableMatchesChosen = durableOffer === chosen;
  }

  let openListShowsOffer = false;
  if (rideId) {
    const open = await apiJson(base, 'GET', '/rides/open?limit=20', {
      bearer: driverToken,
    });
    report.openListStatus = open.status;
    const openData = (open.json['data'] ?? open.json) as {
      rides?: Array<Record<string, unknown>>;
    };
    const rides = openData.rides ?? [];
    const hit = rides.find((r) => r['rideId'] === rideId);
    if (hit) {
      openListShowsOffer = hit['passengerOfferMinor'] === chosen;
      report.openListPassengerOfferMinor = hit['passengerOfferMinor'];
    }
    report.openListContainsRide = Boolean(hit);
    report.openListShowsChosenOffer = openListShowsOffer;
  }

  const ok =
    estimate.status === 200 &&
    report.outOfRangeBlocked === true &&
    goodCreate.status >= 200 &&
    goodCreate.status < 300 &&
    durableOffer === chosen &&
    report.chosenDiffersFromRecommended === true;

  report.verdict = ok
    ? 'STAGING_API_PASS'
    : 'STAGING_API_PARTIAL_OR_FAIL';
  report.endedAt = new Date().toISOString();
  writeReport(report);
  console.log(JSON.stringify({ verdict: report.verdict, rideIdPrefix: report.rideIdPrefix, chosen, durableOffer, outOfRangeBlocked: report.outOfRangeBlocked, openListShowsChosenOffer: openListShowsOffer }, null, 2));
  process.exit(ok ? 0 : 1);
}

function writeReport(report: Record<string, unknown>): void {
  const out = path.join(
    repoRoot,
    'mobile/.e2e_artifacts/passenger_fare_offer_staging_api_proof.json',
  );
  writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}

main().catch((err) => {
  console.error(String(err?.message ?? err));
  process.exit(2);
});
