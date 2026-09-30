/** Ops: verify driver device tokens exist (no raw token in stdout). */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

async function main(): Promise<void> {
  const phone = process.argv[2] ?? '+923012345677';
  const app = initializeApp({
    credential: applicationDefault(),
    projectId: process.env.FIREBASE_PROJECT_ID,
  });
  const user = await getAuth(app).getUserByPhoneNumber(phone);
  const snap = await getFirestore(app)
    .collection('driverDeviceTokens')
    .where('driverId', '==', user.uid)
    .limit(5)
    .get();
  const docs = snap.docs.map((d) => ({
    tokenId: d.id,
    driverId: d.get('driverId'),
    hasToken:
      typeof d.get('token') === 'string' &&
      (d.get('token') as string).length > 16,
  }));
  console.log(
    JSON.stringify({
      driverUid: user.uid,
      tokenDocCount: docs.length,
      docs,
    }),
  );
}

main().catch((err) => {
  console.error(String(err));
  process.exit(1);
});
