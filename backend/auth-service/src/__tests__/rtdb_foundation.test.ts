/**
 * L2 Step 2 — RTDB foundation unit tests (no live Firebase required).
 */
import { describe, expect, it } from 'vitest';
import {
  createTripLocationRtdbFromEnv,
  isRtdbConfigured,
  resolveFirebaseAdminAppOptions,
} from '../rtdb/client';
import { MemoryTripLocationRtdb } from '../rtdb/memory_trip_location_rtdb';
import { NullTripLocationRtdb } from '../rtdb/admin_trip_location_rtdb';
import {
  assertSafeRtdbSegment,
  rideAccessUidPath,
  tripLocationLatestPath,
  tripLocationsRidePath,
} from '../rtdb/paths';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

describe('L2 Step 2 — RTDB config / Admin options', () => {
  it('1. resolveFirebaseAdminAppOptions requires FIREBASE_PROJECT_ID', () => {
    expect(() => resolveFirebaseAdminAppOptions({})).toThrow(
      /FIREBASE_PROJECT_ID/,
    );
  });

  it('1b. includes databaseURL only when FIREBASE_DATABASE_URL is set', () => {
    expect(
      resolveFirebaseAdminAppOptions({ FIREBASE_PROJECT_ID: 'ora-app-d8112' }),
    ).toEqual({ projectId: 'ora-app-d8112' });
    expect(
      resolveFirebaseAdminAppOptions({
        FIREBASE_PROJECT_ID: 'ora-app-d8112',
        FIREBASE_DATABASE_URL:
          'https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app',
      }),
    ).toEqual({
      projectId: 'ora-app-d8112',
      databaseURL:
        'https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app',
    });
  });

  it('2. createTripLocationRtdbFromEnv reuses null when URL unset (no second app)', () => {
    expect(isRtdbConfigured({})).toBe(false);
    const rtdb = createTripLocationRtdbFromEnv({}, []);
    expect(rtdb).toBeInstanceOf(NullTripLocationRtdb);
  });

  it('2b. throws if URL set but Admin app missing', () => {
    expect(() =>
      createTripLocationRtdbFromEnv(
        {
          FIREBASE_DATABASE_URL:
            'https://ora-app-d8112-default-rtdb.asia-southeast1.firebasedatabase.app',
        },
        [],
      ),
    ).toThrow(/not initialized/);
  });
});

describe('L2 Step 2 — path safety + backend helper targets', () => {
  it('3. helper writes expected RTDB paths only', async () => {
    const rtdb = new MemoryTripLocationRtdb();
    await rtdb.grantRideAccess('ride-1', 'passenger-1');
    await rtdb.grantRideAccess('ride-1', 'driver-1');
    await rtdb.setTripLocationLatest('ride-1', {
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
    });

    expect(rtdb.get(rideAccessUidPath('ride-1', 'passenger-1'))).toBe(true);
    expect(rtdb.get(rideAccessUidPath('ride-1', 'driver-1'))).toBe(true);
    expect(rtdb.get(tripLocationLatestPath('ride-1'))).toMatchObject({
      lat: 31.52,
      driverId: 'driver-1',
      locationSeq: 1,
    });
    expect(tripLocationsRidePath('ride-1')).toBe('tripLocations/ride-1');
    expect(tripLocationLatestPath('ride-1')).toBe(
      'tripLocations/ride-1/latest',
    );

    await rtdb.revokeRideAccess('ride-1');
    await rtdb.clearTripLocations('ride-1');
    expect(rtdb.get(rideAccessUidPath('ride-1', 'passenger-1'))).toBeUndefined();
    expect(rtdb.get(tripLocationLatestPath('ride-1'))).toBeUndefined();
  });

  it('rejects path-injection rideId/uid', () => {
    expect(() => assertSafeRtdbSegment('../x', 'rideId')).toThrow(/path/);
    expect(() => assertSafeRtdbSegment('a/b', 'rideId')).toThrow(/path/);
    expect(() => assertSafeRtdbSegment('a.b', 'uid')).toThrow(/path/);
    expect(() => assertSafeRtdbSegment('a#b', 'uid')).toThrow(/path/);
    expect(tripLocationLatestPath('ok-ride')).toBe(
      'tripLocations/ok-ride/latest',
    );
  });
});

describe('L2 Step 2 — database.rules.json fail-closed contract', () => {
  const rulesPath = resolve(__dirname, '../../../../database.rules.json');
  const rules = readFileSync(rulesPath, 'utf8');
  const parsed = JSON.parse(rules) as {
    rules: Record<string, unknown>;
  };

  it('11. root deny + only rideAccess/tripLocations trees', () => {
    expect(parsed.rules['.read']).toBe(false);
    expect(parsed.rules['.write']).toBe(false);
    expect(parsed.rules).toHaveProperty('rideAccess');
    expect(parsed.rules).toHaveProperty('tripLocations');
    expect(parsed.rules).not.toHaveProperty('driverPresence');
    expect(parsed.rules).not.toHaveProperty('rideSignals');
    expect(parsed.rules).not.toHaveProperty('rideRequests');
  });

  it('rideAccess client read/write denied', () => {
    const rideAccess = parsed.rules.rideAccess as {
      $rideId: { '.read': boolean; '.write': boolean };
    };
    expect(rideAccess.$rideId['.read']).toBe(false);
    expect(rideAccess.$rideId['.write']).toBe(false);
  });

  it('tripLocations client write denied; read via rideAccess only', () => {
    const trip = parsed.rules.tripLocations as {
      $rideId: { '.read': string; '.write': boolean };
    };
    expect(trip.$rideId['.write']).toBe(false);
    expect(trip.$rideId['.read']).toContain('auth != null');
    expect(trip.$rideId['.read']).toContain("root.child('rideAccess')");
    expect(trip.$rideId['.read']).toContain('auth.uid');
    expect(trip.$rideId['.read']).not.toContain('driverId');
  });
});

describe('L2 Step 2 — Firestore rules unchanged for Step 2', () => {
  it('11. firestore.rules still denies locationStreams clients', () => {
    const rules = readFileSync(
      resolve(__dirname, '../../../../firestore.rules'),
      'utf8',
    );
    const idx = rules.indexOf('match /locationStreams/{');
    expect(idx).toBeGreaterThan(-1);
    expect(rules.slice(idx, idx + 180)).toMatch(
      /allow read,\s*write:\s*if false/,
    );
  });
});
