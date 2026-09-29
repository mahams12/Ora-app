/**
 * Ops-only: mark Firebase user (E.164 phone) as approved driver for E2E.
 * Usage: ORA_E2E_DRIVER_PHONE=+923012345678 npx tsx scripts/seed_e2e_driver_profile.ts
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const phone = process.env.ORA_E2E_DRIVER_PHONE;
if (!phone) {
  console.error('Set ORA_E2E_DRIVER_PHONE');
  process.exit(2);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

if (!getApps().length) {
  initializeApp({ credential: cert(saPath) });
}

const auth = getAuth();
const db = getFirestore();

async function main() {
  const user = await auth.getUserByPhoneNumber(phone);
  const uid = user.uid;
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    console.error('No users doc; device must call POST /v1/auth/register first.');
    process.exit(1);
  }

  const data = snap.data() ?? {};
  await ref.update({
    role: 'driver',
    driverStatus: 'approved',
    profileComplete: true,
    displayName: data.displayName ?? 'E2E Driver',
    updatedAt: new Date().toISOString(),
  });

  console.log(
    JSON.stringify({
      op: 'seed_e2e_driver',
      uid,
      role: 'driver',
      driverStatus: 'approved',
      profileComplete: true,
    }),
  );
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
