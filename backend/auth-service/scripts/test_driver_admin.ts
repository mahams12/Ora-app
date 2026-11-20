/**
 * Verify POST /v1/internal/drivers/:uid/status — the admin approval path
 * that backs DRIVER_AUTO_APPROVE=false (pending → approved/rejected/
 * suspended). Run against the local emulator stack (dev_local_stack.sh).
 */
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const RUN = `adm-${Date.now()}`;
const uid = `${RUN}-drv`;
const TOKEN = process.env.ORA_INTERNAL_WORKER_TOKEN ?? 'local-dev-worker-token-xx';
const API = 'http://127.0.0.1:8080/v1/internal';
let failures = 0;
const check = (n: string, c: boolean, x?: unknown) => {
  console.log(
    `${c ? 'PASS' : 'FAIL'} ${n}${x !== undefined ? ' ' + JSON.stringify(x) : ''}`,
  );
  if (!c) failures++;
};

async function post(u: string, body: unknown, token?: string) {
  return fetch(`${API}/drivers/${u}/status`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { 'x-ora-worker-token': token } : {}),
    },
    body: JSON.stringify(body),
  });
}

async function main() {
  const db = getFirestore(
    getApps().length
      ? getApps()[0]
      : initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID }),
  );
  await db.doc(`users/${uid}`).set({
    uid,
    phoneNumber: '+923001234567',
    displayName: 'T',
    role: 'passenger',
    driverStatus: 'pending',
    isActive: true,
    banned: false,
  });
  await db.doc(`drivers/${uid}`).set({
    uid,
    vehicle: { category: 'go' },
    homeCity: 'lahore',
    availabilityState: 'offline',
  });

  let r = await post(uid, { status: 'bogus' }, TOKEN);
  check('invalid status → 400', r.status === 400, r.status);
  r = await post(uid, { status: 'approved' });
  check('no token → 401/403', r.status === 401 || r.status === 403, r.status);
  r = await post(uid, { status: 'approved' }, TOKEN);
  check('approve → 200', r.status === 200, r.status);
  const u = (await db.doc(`users/${uid}`).get()).data() ?? {};
  check(
    'users doc approved + role=driver',
    u.driverStatus === 'approved' && u.role === 'driver',
    { s: u.driverStatus, role: u.role },
  );
  const d = (await db.doc(`drivers/${uid}`).get()).data() ?? {};
  check('approvedAt stamped', typeof d.approvedAt === 'string');
  r = await post(uid, { status: 'suspended' }, TOKEN);
  check('suspend → 200', r.status === 200, r.status);
  const d2 = (await db.doc(`drivers/${uid}`).get()).data() ?? {};
  const u2 = (await db.doc(`users/${uid}`).get()).data() ?? {};
  check(
    'suspended: status + forced offline',
    u2.driverStatus === 'suspended' && d2.availabilityState === 'offline',
    { s: u2.driverStatus, av: d2.availabilityState },
  );
  const r404 = await post(`${RUN}-missing`, { status: 'approved' }, TOKEN);
  check('missing application → 404', r404.status === 404, r404.status);
  console.log(failures === 0 ? 'ALL CHECKS PASSED' : `${failures} FAILURES`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('crashed:', e);
  process.exit(1);
});
