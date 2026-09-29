/** Ops: fetch latest ride for passenger uid after marker time. */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const passengerUid = process.env.ORA_E2E_PASSENGER_UID ?? 'AQLQjCfBw3W17kfgzziM6po1Nh33';
const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

if (!getApps().length) {
  initializeApp({ credential: cert(saPath) });
}

const db = getFirestore();
async function main() {
  const snap = await db.collection('rides').orderBy('createdAt', 'desc').limit(8).get();

  const rides = snap.docs
    .map((d) => {
      const data = d.data();
      return {
        rideId: data.rideId ?? d.id,
        passengerId: data.passengerId,
        state: data.state,
        createdAt: data.createdAt,
        category: data.category,
        assignedDriverId: data.assignedDriverId ?? null,
      };
    })
    .filter((r) => r.passengerId === passengerUid);

  console.log(JSON.stringify({ passengerUid, rides }, null, 2));
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
