import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rideId = process.argv[2];
if (!rideId) {
  console.error('usage: e2e_ride_snapshot.ts <rideId>');
  process.exit(2);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

async function main() {
  if (!getApps().length) {
    initializeApp({ credential: cert(saPath) });
  }
  const db = getFirestore();
  const ride = await db.collection('rides').doc(rideId).get();
  const offers = await db.collection('rides').doc(rideId).collection('offers').get();
  console.log(
    JSON.stringify(
      {
        rideId,
        ride: ride.exists ? ride.data() : null,
        offers: offers.docs.map((d) => ({ offerId: d.id, ...d.data() })),
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
