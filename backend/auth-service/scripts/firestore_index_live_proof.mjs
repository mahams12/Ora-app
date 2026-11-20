/**
 * Live Firestore composite-index proof (Admin SDK).
 * Exits non-zero on FAILED_PRECONDITION (code 9).
 * Does not print secrets.
 */
import { readFileSync } from 'node:fs';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const SA_PATH = new URL('../secrets/service-account.json', import.meta.url);
const PROJECT = 'ora-app-d8112';

if (!getApps().length) {
  const sa = JSON.parse(readFileSync(SA_PATH, 'utf8'));
  initializeApp({ credential: cert(sa), projectId: PROJECT });
}

const db = getFirestore();

async function prove(name, fn) {
  try {
    await fn();
    console.log(`PASS ${name}`);
    return true;
  } catch (e) {
    const code = e?.code ?? e?.details;
    console.log(`FAIL ${name} code=${code} msg=${String(e?.message ?? e).slice(0, 200)}`);
    return false;
  }
}

const nowIso = new Date().toISOString();
const cutoffIso = new Date(Date.now() - 60_000).toISOString();
const dummyUid = '000000000000000000000000';
const dummyRide = '00000000-0000-0000-0000-000000000001';

const results = [];

results.push(
  await prove('ride_list_passenger_all', () =>
    db
      .collection('rides')
      .where('passengerId', '==', dummyUid)
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('ride_list_driver_all', () =>
    db
      .collection('rides')
      .where('assignedDriverId', '==', dummyUid)
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('ride_list_passenger_completed', () =>
    db
      .collection('rides')
      .where('passengerId', '==', dummyUid)
      .where('state', 'in', ['RIDE_COMPLETED', 'RIDE_CLOSED'])
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('ride_list_passenger_serviceType', () =>
    db
      .collection('rides')
      .where('passengerId', '==', dummyUid)
      .where('serviceType', '==', 'ride')
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('ride_list_passenger_serviceType_cancelled', () =>
    db
      .collection('rides')
      .where('passengerId', '==', dummyUid)
      .where('serviceType', '==', 'ride')
      .where('state', '==', 'CANCELLED')
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('open_ride_discovery', () =>
    db
      .collection('rides')
      .where('assignedDriverId', '==', null)
      .where('state', 'in', ['SEARCHING', 'OFFERS_AVAILABLE'])
      .limit(5)
      .get(),
  ),
);

results.push(
  await prove('offers_rideId_status', () =>
    db
      .collection('rideOffers')
      .where('rideId', '==', dummyRide)
      .where('status', '==', 'PENDING')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('offers_rideId_createdAt', () =>
    db
      .collection('rideOffers')
      .where('rideId', '==', dummyRide)
      .orderBy('createdAt', 'asc')
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('offer_expire_sweep', () =>
    db
      .collection('rideOffers')
      .where('status', '==', 'PENDING')
      .where('expiresAt', '<=', nowIso)
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('ride_expire_sweep', () =>
    db
      .collection('rides')
      .where('state', 'in', ['SEARCHING', 'OFFERS_AVAILABLE'])
      .where('expiresAt', '<=', nowIso)
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('no_show_sweep', () =>
    db
      .collection('rides')
      .where('state', '==', 'DRIVER_ARRIVED')
      .where('arrivedAt', '<=', cutoffIso)
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('n3_driver_busy_check', () =>
    db
      .collection('rides')
      .where('assignedDriverId', '==', dummyUid)
      .where('state', 'in', ['DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'RIDE_STARTED'])
      .limit(1)
      .get(),
  ),
);

results.push(
  await prove('driver_active_assigned_ride', () =>
    db
      .collection('rides')
      .where('assignedDriverId', '==', dummyUid)
      .where('state', '==', 'DRIVER_ASSIGNED')
      .limit(1)
      .get(),
  ),
);

const failed = results.filter((r) => !r).length;
console.log(`SUMMARY passed=${results.length - failed} failed=${failed}`);
process.exit(failed ? 1 : 0);
