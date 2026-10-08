/**
 * L2 Step 2 — Realtime Database security rules (emulator).
 *
 * Run:
 *   npm run test:database-rules
 *   (firebase emulators:exec --only database …)
 *
 * Fail-closed: clients cannot write tripLocations/rideAccess;
 * read tripLocations only with rideAccess ACL.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { get, ref, set, remove, update } from 'firebase/database';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectId = 'ora-app-d8112';
const rules = readFileSync(resolve(__dirname, '../database.rules.json'), 'utf8');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    database: {
      rules,
      host: '127.0.0.1',
      port: 9000,
    },
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearDatabase();
});

const latestPayload = {
  lat: 31.52,
  lng: 74.35,
  accuracy: 8,
  heading: 90,
  speed: 20,
  ts: 1_700_000_000_000,
  acceptedAt: '2026-10-06T00:00:00.000Z',
  driverId: 'driver-1',
  locationSeq: 1,
  locationStreamId: 'stream-a',
};

describe('L2 Step 2 RTDB rules', () => {
  it('4. client writes to tripLocations are denied', async () => {
    const db = testEnv.authenticatedContext('driver-1').database();
    await assertFails(set(ref(db, 'tripLocations/ride-1/latest'), latestPayload));
    await assertFails(set(ref(db, 'tripLocations/ride-1'), { latest: latestPayload }));
  });

  it('5. unauthenticated reads are denied', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/passenger-1'), true);
      await set(ref(ctx.database(), 'tripLocations/ride-1/latest'), latestPayload);
    });
    const db = testEnv.unauthenticatedContext().database();
    await assertFails(get(ref(db, 'tripLocations/ride-1/latest')));
    await assertFails(get(ref(db, 'tripLocations/ride-1')));
  });

  it('6. authenticated user without rideAccess cannot read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/passenger-1'), true);
      await set(ref(ctx.database(), 'tripLocations/ride-1/latest'), latestPayload);
    });
    const db = testEnv.authenticatedContext('stranger').database();
    await assertFails(get(ref(db, 'tripLocations/ride-1/latest')));
  });

  it('7. authorized passenger with rideAccess can read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/passenger-1'), true);
      await set(ref(ctx.database(), 'tripLocations/ride-1/latest'), latestPayload);
    });
    const db = testEnv.authenticatedContext('passenger-1').database();
    await assertSucceeds(get(ref(db, 'tripLocations/ride-1/latest')));
    await assertSucceeds(get(ref(db, 'tripLocations/ride-1')));
  });

  it('8. authorized assigned driver with rideAccess can read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/driver-1'), true);
      await set(ref(ctx.database(), 'tripLocations/ride-1/latest'), latestPayload);
    });
    const db = testEnv.authenticatedContext('driver-1').database();
    await assertSucceeds(get(ref(db, 'tripLocations/ride-1/latest')));
  });

  it('9. rideAccess cannot be client-mutated', async () => {
    const db = testEnv.authenticatedContext('passenger-1').database();
    await assertFails(set(ref(db, 'rideAccess/ride-1/passenger-1'), true));
    await assertFails(update(ref(db, 'rideAccess/ride-1'), { 'passenger-1': true }));
    await assertFails(remove(ref(db, 'rideAccess/ride-1')));
  });

  it('10. tripLocations cannot be client-mutated (even with rideAccess)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/driver-1'), true);
      await set(ref(ctx.database(), 'tripLocations/ride-1/latest'), latestPayload);
    });
    const db = testEnv.authenticatedContext('driver-1').database();
    await assertFails(
      set(ref(db, 'tripLocations/ride-1/latest'), {
        ...latestPayload,
        lat: 99,
      }),
    );
    await assertFails(remove(ref(db, 'tripLocations/ride-1')));
  });

  it('rideAccess itself is not client-readable', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await set(ref(ctx.database(), 'rideAccess/ride-1/passenger-1'), true);
    });
    const db = testEnv.authenticatedContext('passenger-1').database();
    await assertFails(get(ref(db, 'rideAccess/ride-1/passenger-1')));
    await assertFails(get(ref(db, 'rideAccess/ride-1')));
  });

  it('unrelated root paths remain denied', async () => {
    const db = testEnv.authenticatedContext('u1').database();
    await assertFails(set(ref(db, 'driverPresence/u1'), { online: true }));
    await assertFails(get(ref(db, 'driverPresence/u1')));
    await assertFails(set(ref(db, 'secrets/x'), { a: 1 }));
  });
});
