import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

async function main(): Promise<void> {
  initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
  const db = getFirestore();
  const snap = await db
    .collection('rides')
    .where('state', '==', 'SEARCHING')
    .limit(10)
    .get();
  const rows = snap.docs.map((d) => ({
    rideId: d.id,
    state: d.get('state'),
    createdAt: d.get('createdAt'),
    passengerId: d.get('passengerId'),
  }));
  console.log(JSON.stringify({ count: rows.length, rides: rows }, null, 2));
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
