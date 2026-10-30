import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { assertScriptFirebaseTarget } from './lib/script_env';

async function main(): Promise<void> {
  const uid = process.argv[2];
  if (!uid) {
    console.error('usage: check_driver_online.ts <driverUid>');
    process.exit(2);
  }
  assertScriptFirebaseTarget(process.env);
  initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
  const d = await getFirestore().collection('drivers').doc(uid).get();
  console.log(JSON.stringify({ exists: d.exists, availabilityState: d.get('availabilityState') }));
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
