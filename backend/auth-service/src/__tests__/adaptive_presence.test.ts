/**
 * Cost-optimization Phases A/B/D — adaptive freshness, merged idle cursor,
 * and coalesced sweeps. All flags verified ON and OFF.
 */
import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { createFirestoreGeoClient } from '../redis/firestore_geo_client';
import { RedisGeoProjectionService } from '../redis/geo_projection';
import { parseAndValidateLocationBody } from '../location/validation';
import { NearbyDriversService } from '../drivers/nearby_service';
import {
  GEO_DRIVERS_KEY,
  N3_FRESHNESS_GRACE_MS,
  driverOnlineKey,
} from '../redis/types';

const pickup = { lat: 31.52, lng: 74.35 };

function seedApprovedOnline(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
  });
}

function locBody(overrides: Record<string, unknown> = {}) {
  return {
    locationSeq: 1,
    locationStreamId: 'stream-a',
    lat: pickup.lat,
    lng: pickup.lng,
    accuracy: 8,
    heading: 0,
    speed: 0,
    timestamp: new Date().toISOString(),
    provider: 'gps',
    ...overrides,
  };
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  opts: {
    adaptiveFreshness?: boolean;
    idleMergedCursor?: boolean;
  } = {},
) {
  const geoClient = createFirestoreGeoClient(db as never);
  const geoProjection = new RedisGeoProjectionService(geoClient, {
    adaptiveFreshness: opts.adaptiveFreshness,
  });
  return createApp({
    auth: {
      verifyIdToken: async () => ({ uid, phone_number: '+923001111111' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
    geoProjection,
    redis: geoClient,
    adaptiveFreshness: opts.adaptiveFreshness,
    idleMergedCursor: opts.idleMergedCursor,
  });
}

describe('validation — adaptive fields', () => {
  it('parses + clamps publishIntervalMs and presenceKeepalive', () => {
    const parsed = parseAndValidateLocationBody(
      locBody({ publishIntervalMs: 30_000, presenceKeepalive: true }),
    );
    expect(parsed.publishIntervalMs).toBe(30_000);
    expect(parsed.presenceKeepalive).toBe(true);
  });

  it('clamps interval into [4s, 60s] and defaults keepalive false', () => {
    const low = parseAndValidateLocationBody(
      locBody({ publishIntervalMs: 1 }),
    );
    const high = parseAndValidateLocationBody(
      locBody({ publishIntervalMs: 600_000 }),
    );
    expect(low.publishIntervalMs).toBe(4_000);
    expect(high.publishIntervalMs).toBe(60_000);
    expect(low.presenceKeepalive).toBe(false);
    expect(parseAndValidateLocationBody(locBody()).publishIntervalMs).toBeNull();
  });
});

describe('adaptive freshness — marker + matching', () => {
  it('flag ON: marker carries freshUntilMs = ts + interval + grace and doc twin', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { adaptiveFreshness: true });
    const before = Date.now();
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody({ publishIntervalMs: 30_000 }));
    expect(res.status).toBe(200);

    const doc = db.getDoc('geoDrivers', 'd1')!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      freshUntilMs?: number;
      publishIntervalMs?: number;
      lastLocationTs: number;
    };
    expect(marker.publishIntervalMs).toBe(30_000);
    expect(marker.freshUntilMs).toBe(
      marker.lastLocationTs + 30_000 + N3_FRESHNESS_GRACE_MS,
    );
    // Queryable twin mirrors the marker value.
    expect(doc.freshUntilMs).toBe(marker.freshUntilMs);
    // Marker TTL extended to cover the wider window.
    expect(Number(doc.markerExpiresAtMs)).toBeGreaterThan(
      before + 30 * 1000,
    );
  });

  it('flag OFF: publishIntervalMs ignored; freshUntilMs twin defaults ts+15s', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { adaptiveFreshness: false });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody({ publishIntervalMs: 30_000 }));
    expect(res.status).toBe(200);

    const doc = db.getDoc('geoDrivers', 'd1')!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      freshUntilMs?: number;
      lastLocationTs: number;
    };
    expect(marker.freshUntilMs).toBeUndefined();
    expect(doc.freshUntilMs).toBe(marker.lastLocationTs + 15_000);
  });

  it('stationary 30s-cadence driver stays eligible at 30s marker age (flag ON)', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { adaptiveFreshness: true });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody({ publishIntervalMs: 30_000 }));
    expect(res.status).toBe(200);

    const svc = new NearbyDriversService(
      db as never,
      createFirestoreGeoClient(db as never),
      true,
    );
    // At +30s the fixed window would reject; the declared window keeps them.
    const at30 = Date.now() + 30_000;
    expect(await svc.isStillEligibleForInvite('d1', { nowMs: at30 })).toBe(
      true,
    );
    // Past interval + grace the same marker correctly expires.
    const at50 = Date.now() + 50_000;
    expect(await svc.isStillEligibleForInvite('d1', { nowMs: at50 })).toBe(
      false,
    );
  });

  it('adaptive georadius excludes expired freshUntilMs docs server-side', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    const marker = JSON.stringify({
      lastLocationTs: Date.now() - 40_000,
      accuracy: 8,
      freshUntilMs: Date.now() - 1_000, // already expired
    });
    await geo.set(driverOnlineKey('d1'), marker, 300);
    await geo.geoadd(GEO_DRIVERS_KEY, pickup.lng, pickup.lat, 'd1');
    const hits = await geo.georadius({
      key: GEO_DRIVERS_KEY,
      longitude: pickup.lng,
      latitude: pickup.lat,
      radiusKm: 5,
      count: 30,
      minFreshUntilMs: Date.now(),
    });
    expect(hits).toHaveLength(0);
  });
});

describe('keepalive honesty — phantom-driver guard', () => {
  it('keepalive with bounded-age fix accepted; same age without flag rejected', async () => {
    const oldTs = new Date(Date.now() - 60_000).toISOString();
    const keepalive = parseAndValidateLocationBody(
      locBody({ timestamp: oldTs, presenceKeepalive: true }),
    );
    expect(keepalive.timestampMs).toBeLessThan(Date.now() - 50_000);
    expect(keepalive.presenceKeepalive).toBe(true);
    // Unflagged old timestamps remain strictly rejected.
    expect(() =>
      parseAndValidateLocationBody(locBody({ timestamp: oldTs })),
    ).toThrowError(/STALE_LOCATION|too old/i);
  });

  it('keepalive older than the bound is rejected', () => {
    const ancient = new Date(Date.now() - 200_000).toISOString();
    expect(() =>
      parseAndValidateLocationBody(
        locBody({ timestamp: ancient, presenceKeepalive: true }),
      ),
    ).toThrowError(/STALE_LOCATION|too old/i);
  });

  it('keepalive preserves original fix ts; presence freshness from acceptedAt', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { adaptiveFreshness: true });
    const fixTs = new Date(Date.now() - 60_000).toISOString();
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(
        locBody({
          timestamp: fixTs,
          publishIntervalMs: 30_000,
          presenceKeepalive: true,
        }),
      );
    expect(res.status).toBe(200);

    const doc = db.getDoc('geoDrivers', 'd1')!;
    const marker = JSON.parse(String(doc.markerValue)) as {
      lastLocationTs: number;
      freshUntilMs?: number;
      keepalive?: boolean;
      acceptedAt: string;
    };
    // Honest fix age — NOT re-dated to now.
    expect(marker.lastLocationTs).toBeLessThan(Date.now() - 50_000);
    expect(marker.keepalive).toBe(true);
    // Presence freshness extends from server acceptance, not the fix age.
    const acceptedMs = Date.parse(marker.acceptedAt);
    expect(marker.freshUntilMs).toBe(
      acceptedMs + 30_000 + N3_FRESHNESS_GRACE_MS,
    );
    expect(marker.freshUntilMs!).toBeGreaterThan(Date.now());
  });

  it('stale-fix keepalive marker is present but NOT invite-eligible', async () => {
    const db = memoryDb();
    const geo = createFirestoreGeoClient(db as never);
    // Presence fresh (freshUntilMs in future) but the underlying fix is
    // beyond the honest-position cap — must not be invitable.
    const marker = JSON.stringify({
      lastLocationTs: Date.now() - 125_000,
      accuracy: 8,
      freshUntilMs: Date.now() + 30_000,
      keepalive: true,
      acceptedAt: new Date().toISOString(),
    });
    await geo.set(driverOnlineKey('d1'), marker, 300);
    const svc = new NearbyDriversService(db as never, geo, true);
    expect(await svc.isStillEligibleForInvite('d1')).toBe(false);
  });

  it('keepalive cannot regress lastLocationTs to an older fix', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { adaptiveFreshness: true });
    const res1 = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody({ publishIntervalMs: 30_000 }));
    expect(res1.status).toBe(200);
    const before = (JSON.parse(
      String(db.getDoc('geoDrivers', 'd1')!.markerValue),
    ) as { lastLocationTs: number }).lastLocationTs;

    // Older fix timestamp — staleTs guard must skip the write entirely.
    const res2 = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(
        locBody({
          locationSeq: 2,
          timestamp: new Date(before - 5_000).toISOString(),
          publishIntervalMs: 30_000,
          presenceKeepalive: true,
        }),
      );
    expect(res2.status).toBe(200);
    const after = JSON.parse(
      String(db.getDoc('geoDrivers', 'd1')!.markerValue),
    ) as { lastLocationTs: number };
    expect(after.lastLocationTs).toBe(before);
  });
});

describe('merged idle cursor (Phase B)', () => {
  it('idle publish writes cursor into geoDrivers; no locationStreams doc', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { idleMergedCursor: true });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody());
    expect(res.status).toBe(200);

    expect(db.getDoc('locationStreams', 'd1')).toBeUndefined();
    const doc = db.getDoc('geoDrivers', 'd1')!;
    expect(doc.lsActiveStreamId).toBe('stream-a');
    expect(doc.lsLastAcceptedSeq).toBe(1);
    expect(doc.markerValue).toBeDefined();
  });

  it('stale seq → 422 SEQUENCE_VIOLATION; stream replacement still works', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { idleMergedCursor: true });
    const auth = () => 'Bearer t';

    for (const seq of [1, 2]) {
      const res = await request(app)
        .post('/v1/location/update')
        .set('Authorization', auth())
        .send(locBody({ locationSeq: seq }));
      expect(res.status).toBe(200);
    }
    // Replay seq 2 → violation.
    const stale = await request(app)
      .post('/v1/location/update')
      .set('Authorization', auth())
      .send(locBody({ locationSeq: 2 }));
    expect(stale.status).toBe(422);
    expect(stale.body.error?.code).toBe('SEQUENCE_VIOLATION');

    // A new streamId replaces the cursor (session restart semantics).
    const restarted = await request(app)
      .post('/v1/location/update')
      .set('Authorization', auth())
      .send(locBody({ locationSeq: 1, locationStreamId: 'stream-b' }));
    expect(restarted.status).toBe(200);

    // The replaced stream can no longer write.
    const ghost = await request(app)
      .post('/v1/location/update')
      .set('Authorization', auth())
      .send(locBody({ locationSeq: 9, locationStreamId: 'stream-a' }));
    expect(ghost.status).toBe(422);
  });

  it('flag OFF preserves the classic two-write path', async () => {
    const db = memoryDb();
    seedApprovedOnline(db, 'd1');
    const app = appFor(db, 'd1', { idleMergedCursor: false });
    const res = await request(app)
      .post('/v1/location/update')
      .set('Authorization', 'Bearer t')
      .send(locBody());
    expect(res.status).toBe(200);
    expect(db.getDoc('locationStreams', 'd1')?.lastAcceptedSeq).toBe(1);
    expect(db.getDoc('geoDrivers', 'd1')?.lsActiveStreamId).toBeUndefined();
  });
});

describe('coalesced sweeps (Phase D)', () => {
  const workerAuth = { 'x-ora-worker-token': 'test-worker-token-16' };

  function sweepApp(db: ReturnType<typeof memoryDb>) {
    const geoClient = createFirestoreGeoClient(db as never);
    return createApp({
      auth: {
        verifyIdToken: async () => ({ uid: 'w', phone_number: 'x' }),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      redis: geoClient,
      internalWorkerToken: 'test-worker-token-16',
    });
  }

  it('guard skips dispatch when no SEARCHING rides; other sweeps still run', async () => {
    const db = memoryDb();
    const res = await request(sweepApp(db))
      .post('/v1/internal/sweeps/all')
      .set(workerAuth)
      .send();
    expect(res.status).toBe(200);
    const data = res.body.data;
    expect(data.searchingActive).toBe(false);
    expect(data.results.dispatch.skipped).toBe('no_searching_rides');
    // Time-driven sweeps always execute.
    for (const step of [
      'expire',
      'offerExpire',
      'noShow',
      'dispatchFcm',
      'rideStateFcm',
      'expiresAtCleanup',
    ]) {
      expect(data.results[step], `step ${step}`).toBeDefined();
      expect(data.results[step].skipped).not.toBe('no_searching_rides');
    }
    expect(data.failures).toEqual([]);
  });

  it('dispatch sweep runs when a SEARCHING ride exists', async () => {
    const db = memoryDb();
    db.seed('rides', 'r1', {
      rideId: 'r1',
      state: 'SEARCHING',
      passengerId: 'p1',
    });
    const res = await request(sweepApp(db))
      .post('/v1/internal/sweeps/all')
      .set(workerAuth)
      .send();
    expect(res.status).toBe(200);
    expect(res.body.data.searchingActive).toBe(true);
    // sweepDispatch result — `skipped` is a numeric count, not the guard marker.
    expect(res.body.data.results.dispatch.skipped).not.toBe(
      'no_searching_rides',
    );
  });

  it('?guards=false disables the SEARCHING probe', async () => {
    const db = memoryDb();
    const res = await request(sweepApp(db))
      .post('/v1/internal/sweeps/all?guards=false')
      .set(workerAuth)
      .send();
    expect(res.status).toBe(200);
    expect(res.body.data.results.dispatch.skipped).not.toBe(
      'no_searching_rides',
    );
  });

  it('step failure → 503, failure isolated, other sweeps still ran', async () => {
    const db = memoryDb();
    const geoClient = createFirestoreGeoClient(db as never);
    const failing = {
      ...geoClient,
      sweepExpired: async () => {
        throw new Error('geo presence backend down');
      },
    };
    const app = createApp({
      auth: {
        verifyIdToken: async () => ({ uid: 'w', phone_number: 'x' }),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      redis: failing,
      internalWorkerToken: 'test-worker-token-16',
    });
    const res = await request(app)
      .post('/v1/internal/sweeps/all')
      .set(workerAuth)
      .send();
    // Never silent-success: non-2xx when any sweep fails.
    expect(res.status).toBe(503);
    expect(res.body.data.failures).toEqual(['geoPresence']);
    expect(res.body.data.results.geoPresence.error).toBe('Error');
    // Isolation: every other step still executed.
    for (const step of [
      'expire',
      'offerExpire',
      'noShow',
      'dispatchFcm',
      'rideStateFcm',
      'expiresAtCleanup',
    ]) {
      expect(res.body.data.results[step], `step ${step}`).toBeDefined();
      expect(res.body.data.results[step].error).toBeUndefined();
    }
  });
});
