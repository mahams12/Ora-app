/** One-off staging smoke: POST /v1/pricing/estimate (no secrets logged). */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(here, '../../..');

async function main() {
  const base = readFileSync(
    path.join(repoRoot, 'mobile/.staging_api_url'),
    'utf8',
  )
    .trim()
    .replace(/\/$/, '');
  if (!getApps().length) {
    initializeApp({ credential: cert(process.env.GOOGLE_APPLICATION_CREDENTIALS!) });
  }
  const gs = JSON.parse(
    readFileSync(
      path.join(repoRoot, 'mobile/android/app/google-services.json'),
      'utf8',
    ),
  ) as { client: Array<{ api_key: Array<{ current_key: string }> }> };
  const apiKey = gs.client[0]!.api_key[0]!.current_key;
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
  if (!ex.ok) {
    console.log(JSON.stringify({ ok: false, step: 'custom_token_exchange', status: ex.status }));
    process.exit(1);
  }
  const { idToken } = (await ex.json()) as { idToken: string };
  const res = await fetch(`${base}/pricing/estimate`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${idToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      pickup: { lat: 31.4127578, lng: 74.1725224 },
      destination: { lat: 31.51, lng: 74.34 },
      city: 'lahore',
      category: 'easy',
      serviceType: 'ride',
    }),
  });
  const j = (await res.json()) as {
    data?: { pricingSnapshotId?: string };
    error?: { code?: string };
  };
  const ok =
    res.status === 200 &&
    typeof j.data?.pricingSnapshotId === 'string' &&
    j.data.pricingSnapshotId.length > 0;
  console.log(
    JSON.stringify({
      ok,
      pricingEstimateHttp: res.status,
      hasSnapshot: Boolean(j.data?.pricingSnapshotId),
      errorCode: j.error?.code ?? null,
    }),
  );
  process.exit(ok ? 0 : 1);
}

main().catch((e) => {
  console.log(JSON.stringify({ ok: false, error: String(e) }));
  process.exit(1);
});
