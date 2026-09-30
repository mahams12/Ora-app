/**
 * Production smoke: health, App Check negatives, pricing 200 with debug exchange.
 * Never log tokens, secrets, or Maps keys.
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exchangeAppCheckDebugSecret, readAndroidApiKey } from './app_check_exchange_debug.ts';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');

type PricingData = {
  pricingSnapshotId?: string;
  recommendedFareMinor?: number;
  offerBoundMinMinor?: number;
  offerBoundMaxMinor?: number;
  distanceKm?: number;
  durationMin?: number;
  category?: string;
  city?: string;
  pricingRulesVersion?: string;
  computedAt?: string;
  expiresAt?: string;
  currency?: string;
};

async function firebaseIdToken(): Promise<string> {
  if (getApps().length === 0) {
    initializeApp({ credential: cert(process.env.GOOGLE_APPLICATION_CREDENTIALS!) });
  }
  const apiKey = readAndroidApiKey();
  const uid = (await getAuth().getUserByPhoneNumber('+923012345678')).uid;
  const custom = await getAuth().createCustomToken(uid);
  const ex = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  const { idToken } = (await ex.json()) as { idToken: string };
  return idToken;
}

async function resolveAppCheckJwt(): Promise<string | null> {
  const direct = process.env.PRODUCTION_APP_CHECK_DEBUG_TOKEN?.trim();
  if (direct) return direct;
  const secret = process.env.PRODUCTION_APP_CHECK_DEBUG_SECRET?.trim();
  if (!secret) return null;
  return exchangeAppCheckDebugSecret(secret);
}

async function main() {
  const base = readFileSync(
    path.join(repoRoot, 'mobile/.production_api_url'),
    'utf8',
  )
    .trim()
    .replace(/\/$/, '');

  const health = await fetch(`${base.replace(/\/v1$/, '')}/healthz/`);
  const healthOk = health.status === 200;

  const meNoAuth = await fetch(`${base}/auth/me`);
  const meNoAuthStatus = meNoAuth.status;
  const meNoAuthCode = ((await meNoAuth.json()) as { error?: { code?: string } })
    .error?.code;

  const idToken = await firebaseIdToken();
  const appCheckJwt = await resolveAppCheckJwt();

  const pricingBody = {
    pickup: { lat: 31.4127578, lng: 74.1725224 },
    destination: { lat: 31.51, lng: 74.34 },
    city: 'lahore',
    category: 'easy',
    serviceType: 'ride',
  };

  const prNoAppCheck = await fetch(`${base}/pricing/estimate`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(pricingBody),
  });
  const prNoAppCheckJson = (await prNoAppCheck.json()) as {
    error?: { code?: string };
  };

  const prBadAppCheck = await fetch(`${base}/pricing/estimate`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': 'invalid-app-check-token-for-smoke',
    },
    body: JSON.stringify(pricingBody),
  });
  const prBadAppCheckJson = (await prBadAppCheck.json()) as {
    error?: { code?: string };
  };

  let prOkStatus = 0;
  let data: PricingData | undefined;
  let prOkErrorCode: string | null = null;
  if (appCheckJwt) {
    const prOk = await fetch(`${base}/pricing/estimate`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${idToken}`,
        'Content-Type': 'application/json',
        'X-Firebase-AppCheck': appCheckJwt,
      },
      body: JSON.stringify(pricingBody),
    });
    prOkStatus = prOk.status;
    const pj = (await prOk.json()) as {
      data?: PricingData;
      error?: { code?: string };
    };
    data = pj.data;
    prOkErrorCode = pj.error?.code ?? null;
  }

  const pricingProof = {
    httpStatus: prOkStatus,
    errorCode: prOkErrorCode,
    pricingSnapshotId: data?.pricingSnapshotId ?? null,
    recommendedFareMinor: data?.recommendedFareMinor ?? null,
    offerBoundMinMinor: data?.offerBoundMinMinor ?? null,
    offerBoundMaxMinor: data?.offerBoundMaxMinor ?? null,
    distanceKm: data?.distanceKm ?? null,
    durationMin: data?.durationMin ?? null,
    category: data?.category ?? null,
    pricingRulesVersion: data?.pricingRulesVersion ?? null,
    computedAtPresent: Boolean(data?.computedAt),
    expiresAtPresent: Boolean(data?.expiresAt),
    currency: data?.currency ?? null,
    appCheckExchangeUsed: Boolean(
      process.env.PRODUCTION_APP_CHECK_DEBUG_SECRET?.trim() &&
        !process.env.PRODUCTION_APP_CHECK_DEBUG_TOKEN?.trim(),
    ),
  };

  const negatives = {
    noAppCheckStatus: prNoAppCheck.status,
    noAppCheckCode: prNoAppCheckJson.error?.code ?? null,
    badAppCheckStatus: prBadAppCheck.status,
    badAppCheckCode: prBadAppCheckJson.error?.code ?? null,
  };

  const routesOk =
    typeof data?.distanceKm === 'number' &&
    data.distanceKm > 0 &&
    typeof data.durationMin === 'number' &&
    data.durationMin > 0;

  const snapshotOk =
    typeof data?.pricingSnapshotId === 'string' &&
    data.pricingSnapshotId.length > 0 &&
    typeof data?.recommendedFareMinor === 'number' &&
    data.recommendedFareMinor > 0 &&
    typeof data?.pricingRulesVersion === 'string' &&
    data.pricingSnapshotId.startsWith('ps_');

  const report = {
    healthOk,
    healthStatus: health.status,
    meNoAuthStatus,
    meNoAuthCode,
    negatives,
    pricing: pricingProof,
    routesMetricsOk: routesOk,
    snapshotOk,
  };

  console.log(JSON.stringify(report));

  const ok =
    healthOk &&
    meNoAuthStatus === 401 &&
    meNoAuthCode === 'APP_CHECK_REQUIRED' &&
    negatives.noAppCheckStatus === 401 &&
    negatives.noAppCheckCode === 'APP_CHECK_REQUIRED' &&
    negatives.badAppCheckStatus === 401 &&
    negatives.badAppCheckCode === 'APP_CHECK_INVALID' &&
    prOkStatus === 200 &&
    snapshotOk &&
    routesOk;

  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.log(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
