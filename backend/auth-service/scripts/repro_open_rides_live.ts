/**
 * Reproduce GET /v1/rides/open against live Firestore (ops).
 * Usage: npx tsx scripts/repro_open_rides_live.ts [driverUid]
 */
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RideService } from '../src/rides/ride_service';

const driverUid =
  process.argv[2] ?? 'SRjL7BJgCKTduhtpjtYMRZMq5fD2';

const here = path.dirname(fileURLToPath(import.meta.url));
const saPath =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ??
  path.join(here, '../secrets/service-account.json');

if (!getApps().length) {
  initializeApp({ credential: cert(saPath) });
}

const db = getFirestore();

async function rawQuery() {
  const EXPIRABLE_STATES = ['SEARCHING', 'OFFERS_AVAILABLE'];
  try {
    const snap = await db
      .collection('rides')
      .where('assignedDriverId', '==', null)
      .where('state', 'in', EXPIRABLE_STATES)
      .orderBy('createdAt', 'desc')
      .orderBy('rideId', 'desc')
      .limit(5)
      .get();
    console.log(
      JSON.stringify({
        op: 'raw_firestore_query',
        ok: true,
        docCount: snap.size,
        rideIds: snap.docs.map((d) => d.id),
      }),
    );
  } catch (e) {
    const err = e as Error & { code?: number; details?: string };
    console.log(
      JSON.stringify({
        op: 'raw_firestore_query',
        ok: false,
        name: err.name,
        message: err.message?.slice(0, 500),
        code: err.code,
        details: typeof err.details === 'string' ? err.details.slice(0, 500) : undefined,
      }),
    );
  }
}

async function serviceOpen() {
  const rides = new RideService(db);
  const started = Date.now();
  try {
    const result = await rides.listOpenRides({
      caller: { uid: driverUid, phoneNumber: '+923012345677' },
      query: {},
    });
    const body = result.body as { data: { rides: unknown[] } };
    console.log(
      JSON.stringify({
        op: 'listOpenRides',
        ok: true,
        httpStatus: result.httpStatus,
        durationMs: Date.now() - started,
        rideCount: body.data.rides.length,
        meta: result.meta,
      }),
    );
  } catch (e) {
    console.log(
      JSON.stringify({
        op: 'listOpenRides',
        ok: false,
        durationMs: Date.now() - started,
        message: (e as Error).message?.slice(0, 300),
      }),
    );
  }
}

async function main() {
  await rawQuery();
  await serviceOpen();
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
