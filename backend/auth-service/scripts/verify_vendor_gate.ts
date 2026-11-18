/**
 * Local E2E for the vendor-application gate. Emulator-only — fails closed.
 *   npx tsx scripts/verify_vendor_gate.ts
 *
 * Flow: fresh user → register → apply cargo → me shows pending →
 * re-apply idempotent → apply rental (multi-role) → admin approves cargo →
 * me shows cargo=approved, rental=pending → invalid type rejected →
 * suspended user blocked.
 */
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
process.env.FIREBASE_DATABASE_URL ??=
  'https://oraapp-a9be5-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const API = 'http://127.0.0.1:8080/v1';
const AUTH_EMU = 'http://127.0.0.1:9099';
const UID = `vendor-gate-${Date.now()}`;

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown) {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${extra !== undefined ? ' ' + JSON.stringify(extra) : ''}`);
  if (!cond) failures++;
}

async function api(
  token: string,
  method: string,
  path: string,
  body?: unknown,
  idem?: string,
) {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(idem ? { 'Idempotency-Key': idem } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json: unknown = null;
  try { json = await r.json(); } catch { /* empty */ }
  return { status: r.status, json };
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const custom = await getAuth().createCustomToken(UID);
  const signIn = await fetch(
    `${AUTH_EMU}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=test`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  const { idToken } = (await signIn.json()) as { idToken: string };

  // 1. register → baseline profile, no applications
  let r = await api(idToken, 'POST', '/auth/register', {}, `register_${UID}`);
  check('register 200', r.status === 200, r.status);

  // 2. apply cargo with details
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'cargo', details: { businessName: 'Test Cargo Co', vehicleType: 'Truck / Lorry' } },
    'vendor_apply_cargo_t1');
  const apps1 = (r.json as { vendorApplications?: Record<string, { status: string }> })
    ?.vendorApplications;
  check('cargo apply → pending', r.status === 200 && apps1?.cargo?.status === 'pending', apps1);

  // 3. /me shows pending
  r = await api(idToken, 'GET', '/auth/me');
  const apps2 = (r.json as { vendorApplications?: Record<string, { status: string }> })
    ?.vendorApplications;
  check('me → cargo pending', apps2?.cargo?.status === 'pending', apps2);

  // 4. idempotent re-apply
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'cargo' }, 'vendor_apply_cargo_t2');
  const apps3 = (r.json as { vendorApplications?: Record<string, { status: string }> })
    ?.vendorApplications;
  check('re-apply idempotent pending', r.status === 200 && apps3?.cargo?.status === 'pending');

  // 5. second role allowed (multi-role)
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'rental' }, 'vendor_apply_rental_t1');
  const apps4 = (r.json as { vendorApplications?: Record<string, { status: string }> })
    ?.vendorApplications;
  check('rental apply → pending too', apps4?.rental?.status === 'pending', apps4);

  // 6. invalid type rejected
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'pilot' }, 'vendor_apply_bad_t1');
  check('bad type → 400', r.status === 400, r.status);

  // 7. missing idempotency key rejected
  r = await api(idToken, 'POST', '/auth/vendor-application', { type: 'cargo' });
  check('no idem key → 400', r.status === 400, r.status);

  // 8. admin approves cargo (emulator direct write = console/seed path)
  const ref = getFirestore().collection('users').doc(UID);
  const doc = (await ref.get()).data() ?? {};
  const apps = (doc.vendorApplications ?? {}) as Record<string, Record<string, unknown>>;
  apps.cargo = { ...apps.cargo, status: 'approved', reviewedAt: new Date().toISOString() };
  await ref.update({ vendorApplications: apps });

  r = await api(idToken, 'GET', '/auth/me');
  const apps5 = (r.json as { vendorApplications?: Record<string, { status: string }> })
    ?.vendorApplications;
  check('me → cargo approved + rental pending',
    apps5?.cargo?.status === 'approved' && apps5?.rental?.status === 'pending', apps5);

  // 9. suspended blocks new application of that type
  apps.rental = { ...apps.rental, status: 'suspended', reviewedAt: new Date().toISOString() };
  await ref.update({ vendorApplications: apps });
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'rental' }, 'vendor_apply_rental_t2');
  check('suspended → 403 VENDOR_SUSPENDED',
    r.status === 403 &&
      (r.json as { error?: { code?: string } })?.error?.code === 'VENDOR_SUSPENDED',
    r.json);

  // 10. unknown fields rejected
  r = await api(idToken, 'POST', '/auth/vendor-application',
    { type: 'cargo', role: 'admin' }, 'vendor_apply_hack_t1');
  check('extra field → 400', r.status === 400, r.status);

  console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} FAILURES`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
