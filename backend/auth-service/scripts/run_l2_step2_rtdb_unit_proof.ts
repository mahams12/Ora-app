/**
 * L2 Step 2 — RTDB foundation unit proof (no live Firebase / emulator required).
 * Usage: npm run test:l2-step2-rtdb-unit-proof
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  createTripLocationRtdbFromEnv,
  isRtdbConfigured,
  resolveFirebaseAdminAppOptions,
} from '../src/rtdb/client';
import { NullTripLocationRtdb } from '../src/rtdb/admin_trip_location_rtdb';
import { MemoryTripLocationRtdb } from '../src/rtdb/memory_trip_location_rtdb';
import {
  rideAccessUidPath,
  tripLocationLatestPath,
} from '../src/rtdb/paths';

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void> | void): Promise<void> {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(err);
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

async function main(): Promise<void> {
  await test('1. RTDB config resolves projectId + optional databaseURL', () => {
    const base = resolveFirebaseAdminAppOptions({
      FIREBASE_PROJECT_ID: 'ora-app-d8112',
    });
    assert(base.projectId === 'ora-app-d8112', 'projectId');
    assert(base.databaseURL === undefined, 'no url');
    const withUrl = resolveFirebaseAdminAppOptions({
      FIREBASE_PROJECT_ID: 'ora-app-d8112',
      FIREBASE_DATABASE_URL:
        'https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app',
    });
    assert(typeof withUrl.databaseURL === 'string', 'url present');
    assert(isRtdbConfigured({}) === false, 'not configured');
  });

  await test('2. without URL → NullTripLocationRtdb (no second Admin app)', () => {
    const rtdb = createTripLocationRtdbFromEnv({}, []);
    assert(rtdb instanceof NullTripLocationRtdb, 'null rtdb');
  });

  await test('3. backend helper targets expected paths', async () => {
    const rtdb = new MemoryTripLocationRtdb();
    await rtdb.grantRideAccess('ride-1', 'p1');
    await rtdb.setTripLocationLatest('ride-1', {
      lat: 31.5,
      lng: 74.3,
      accuracy: 5,
      heading: 10,
      speed: 12,
      ts: 1000,
      acceptedAt: '2026-10-06T00:00:00.000Z',
      driverId: 'd1',
      locationSeq: 2,
      locationStreamId: 's1',
    });
    assert(rtdb.get(rideAccessUidPath('ride-1', 'p1')) === true, 'acl');
    assert(
      (rtdb.get(tripLocationLatestPath('ride-1')) as { locationSeq: number })
        .locationSeq === 2,
      'latest',
    );
    await rtdb.revokeRideAccess('ride-1');
    await rtdb.clearTripLocations('ride-1');
    assert(rtdb.get(rideAccessUidPath('ride-1', 'p1')) === undefined, 'acl gone');
    assert(
      rtdb.get(tripLocationLatestPath('ride-1')) === undefined,
      'latest gone',
    );
  });

  await test('4-10. database.rules.json fail-closed contract', () => {
    const raw = readFileSync(
      resolve(process.cwd(), '../../database.rules.json'),
      'utf8',
    );
    const rules = JSON.parse(raw).rules;
    assert(rules['.read'] === false, 'root read deny');
    assert(rules['.write'] === false, 'root write deny');
    assert(rules.rideAccess.$rideId['.read'] === false, 'acl read deny');
    assert(rules.rideAccess.$rideId['.write'] === false, 'acl write deny');
    assert(rules.tripLocations.$rideId['.write'] === false, 'trip write deny');
    const readExpr = rules.tripLocations.$rideId['.read'] as string;
    assert(readExpr.includes('auth != null'), 'auth required');
    assert(readExpr.includes("root.child('rideAccess')"), 'rideAccess gate');
    assert(!raw.includes('driverPresence'), 'no driverPresence');
    assert(!('recent' in (rules.tripLocations.$rideId ?? {})), 'no recent node');
  });

  await test('11. firestore.rules locationStreams deny unchanged', () => {
    const rules = readFileSync(
      resolve(process.cwd(), '../../firestore.rules'),
      'utf8',
    );
    const idx = rules.indexOf('match /locationStreams/{');
    assert(idx >= 0, 'match present');
    assert(
      /allow read,\s*write:\s*if false/.test(rules.slice(idx, idx + 180)),
      'deny',
    );
  });

  await test('12. firebase.json registers database rules + emulator', () => {
    const cfg = JSON.parse(
      readFileSync(resolve(process.cwd(), '../../firebase.json'), 'utf8'),
    );
    assert(cfg.database?.rules === 'database.rules.json', 'rules path');
    assert(cfg.emulators?.database?.port === 9000, 'emulator port');
  });

  console.log(`\nL2 Step 2 RTDB unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
