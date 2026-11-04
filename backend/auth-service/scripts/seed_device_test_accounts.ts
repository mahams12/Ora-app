/**
 * Seed phone-auth test accounts on LOCAL Firebase emulators for physical-device
 * testing. Fails closed if emulator env vars are not set — cannot touch cloud.
 *
 * Usage:
 *   npx tsx scripts/seed_device_test_accounts.ts
 *   SEED_ACTION=approve-phone PHONE=+923004445555 npx tsx scripts/seed_device_test_accounts.ts
 *
 * Prints the uid + phone for each account so OTP login (emulator
 * verificationCodes endpoint) resolves to the same canonical users/{uid}.
 */
if (
  !process.env.FIRESTORE_EMULATOR_HOST ||
  !process.env.FIREBASE_AUTH_EMULATOR_HOST
) {
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
  process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
}
process.env.FIREBASE_PROJECT_ID ??= 'ora-app-d8112';
process.env.FIREBASE_DATABASE_URL ??=
  'https://ora-app-d8112-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';

const APPROVED_DRIVER_PHONE = '+923001112233';
const FRESH_SWITCH_PHONE = '+923004445555';

async function ensureUser(phone: string) {
  const auth = getAuth();
  try {
    return await auth.getUserByPhoneNumber(phone);
  } catch {
    return auth.createUser({ phoneNumber: phone });
  }
}

async function seedApprovedDriver(phone: string) {
  const user = await ensureUser(phone);
  const db = getFirestore();
  await db.collection('users').doc(user.uid).set(
    {
      uid: user.uid,
      phoneNumber: phone,
      displayName: 'Device Driver',
      role: 'driver',
      driverStatus: 'approved',
      activeMode: 'driver',
      isActive: true,
      banned: false,
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
  await db.collection('drivers').doc(user.uid).set(
    {
      uid: user.uid,
      vehicle: { type: 'car', model: 'Seed Sedan', plate: 'LEA-1001' },
      homeCity: 'lahore',
      availabilityState: 'offline',
      updatedAt: new Date().toISOString(),
    },
    { merge: true },
  );
  console.log(`approved driver  ${phone}  uid=${user.uid}`);
}

async function seedPricing() {
  const db = getFirestore();
  for (const [category, seed] of [
    [
      'go',
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'go',
        version: 'local-device-1',
        baseFare: 100,
        ratePerKm: 60,
        ratePerMin: 5,
        minFare: 120,
        maxFare: 5000,
      }),
    ],
    [
      'courier',
      buildPricingRuleSeed({
        city: 'lahore',
        category: 'courier',
        version: 'local-device-1',
        baseFare: 150,
        ratePerKm: 70,
        ratePerMin: 5,
        minFare: 150,
        maxFare: 8000,
      }),
    ],
  ] as const) {
    await db.collection('pricingRules').doc(`lahore_${category}`).set(seed);
  }
  console.log('pricing rules: lahore_go + lahore_courier');
}

async function approvePhone(phone: string) {
  const auth = getAuth();
  const user = await auth.getUserByPhoneNumber(phone);
  const db = getFirestore();
  await db.collection('users').doc(user.uid).update({
    role: 'driver',
    driverStatus: 'approved',
    updatedAt: new Date().toISOString(),
  });
  console.log(`approved ${phone} uid=${user.uid}`);
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  if (process.env.SEED_ACTION === 'approve-phone') {
    await approvePhone(process.env.PHONE ?? FRESH_SWITCH_PHONE);
    return;
  }
  await seedPricing();
  await seedApprovedDriver(APPROVED_DRIVER_PHONE);
  await ensureUser(FRESH_SWITCH_PHONE);
  const fresh = await getAuth().getUserByPhoneNumber(FRESH_SWITCH_PHONE);
  console.log(`fresh passenger   ${FRESH_SWITCH_PHONE}  uid=${fresh.uid} (no users doc — registers via app)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
