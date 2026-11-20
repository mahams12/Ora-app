/**
 * Event-driven dispatch (inDrive-style matching) — local memory-fake tests.
 *
 * Covers: inline wave-1 on booking, Cloud Tasks deadline wake-ups, early-tick
 * self-heal, all-declined acceleration, OIDC worker auth, task client shape.
 */
import { describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { createMemoryGeoStore } from '../geo/memory_geo_store';
import {
  DRIVER_ONLINE_TTL_SECONDS,
  GEO_DRIVERS_KEY,
  driverOnlineKey,
  type DriverOnlineMarker,
} from '../geo/types';
import {
  N4_WAVE_CADENCE_MS,
  waveDocId,
} from '../rides/dispatch_types';
import {
  CloudTasksDispatchScheduler,
  createDispatchTaskSchedulerFromEnv,
  NoopDispatchTaskScheduler,
  type DispatchTaskScheduler,
} from '../tasks/dispatch_tasks';
import { DispatchWaveService } from '../rides/dispatch_wave_service';
import { NearbyDriversService } from '../drivers/nearby_service';

const WORKER = 'test-worker-token-ed-xxxx';
const PICKUP = { lat: 31.52, lng: 74.35 };

function authFor(uids: Record<string, string>) {
  return {
    verifyIdToken: vi.fn(async (token: string) => ({
      uid: uids[token] ?? token,
      phone_number: '+923001111111',
    })),
  } as never;
}

class FakeScheduler implements DispatchTaskScheduler {
  ticks: { rideId: string; waveNumber: number; runAtMs: number }[] = [];
  expires: { rideId: string; runAtMs: number }[] = [];
  async scheduleDispatchTick(input: {
    rideId: string;
    waveNumber: number;
    runAtMs: number;
    correlationId: string;
  }) {
    this.ticks.push(input);
    return { created: true, taskName: 'fake' };
  }
  async scheduleRideExpire(input: {
    rideId: string;
    runAtMs: number;
    correlationId: string;
  }) {
    this.expires.push(input);
    return { created: true, taskName: 'fake' };
  }
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  uids: Record<string, string>,
  extra: Parameters<typeof createApp>[0] = {},
) {
  return createApp({
    auth: authFor(uids),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    ...extra,
  });
}

function seedApprovedOnline(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  homeCity: string | null = 'lahore',
) {
  db.seed('users', uid, {
    uid,
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    displayName: uid,
  });
  db.seed('drivers', uid, {
    driverId: uid,
    userId: uid,
    availabilityState: 'online',
    ...(homeCity != null ? { homeCity } : {}),
  });
}

function seedPassenger(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    displayName: uid,
  });
}

function seedPricing(db: ReturnType<typeof memoryDb>, id = 'ps1') {
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
    recommendedFareMinor: 50000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 60 * 60_000).toISOString(),
    inputs: { distanceKm: 5.2, durationMin: 18 },
  });
}

async function seedGeo(
  geoStore: ReturnType<typeof createMemoryGeoStore>,
  driverId: string,
  lng: number,
  lat: number,
  nowMs: number,
) {
  await geoStore.geoadd(GEO_DRIVERS_KEY, lng, lat, driverId);
  const marker: DriverOnlineMarker = {
    driverId,
    accuracy: 5,
    city: 'lahore',
    locationStreamId: 's1',
    locationSeq: 1,
    acceptedAt: new Date(nowMs).toISOString(),
    lastLocationTs: nowMs,
  };
  await geoStore.set(
    driverOnlineKey(driverId),
    JSON.stringify(marker),
    DRIVER_ONLINE_TTL_SECONDS,
  );
}

async function seedDrivers(
  db: ReturnType<typeof memoryDb>,
  geoStore: ReturnType<typeof createMemoryGeoStore>,
  count: number,
  nowMs: number,
  prefix = 'd',
) {
  const ids: string[] = [];
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}${i}`;
    ids.push(id);
    seedApprovedOnline(db, id);
    await seedGeo(geoStore, id, PICKUP.lng + i * 0.001, PICKUP.lat, nowMs);
  }
  return ids;
}

function seedSearchingRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  overrides: Record<string, unknown> = {},
) {
  const now = Date.now();
  db.seed('rides', rideId, {
    rideId,
    passengerId: 'p1',
    assignedDriverId: null,
    state: 'SEARCHING',
    version: 1,
    requestVersion: 1,
    category: 'zip',
    serviceType: 'ride',
    pickup: { ...PICKUP, address: 'A' },
    destination: { lat: 31.53, lng: 74.36, address: 'B' },
    routePolyline: null,
    distanceKm: 4.2,
    estimatedDurationMin: 12,
    pricingSnapshotId: 'ps1',
    recommendedFareMinor: 50000,
    passengerOfferMinor: 45000,
    agreedFareMinor: null,
    agreedOfferId: null,
    agreedFareCurrency: null,
    feePolicySnapshot: null,
    paymentMethod: 'CASH',
    paymentIntentId: null,
    passengerCount: 1,
    expiresAt: new Date(now + 15 * 60_000).toISOString(),
    assignedAt: null,
    arrivedAt: null,
    startedAt: null,
    completedAt: null,
    closedAt: null,
    cancelledBy: null,
    cancellationReason: null,
    cancellationFeeMinor: null,
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    ...overrides,
  });
}

async function getDoc(
  db: ReturnType<typeof memoryDb>,
  col: string,
  id: string,
) {
  const snap = await db.collection(col).doc(id).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

async function waitFor(
  fn: () => Promise<boolean>,
  timeoutMs = 3000,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await fn()) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  throw new Error('waitFor timed out');
}

const createBody = {
  pickup: { lat: PICKUP.lat, lng: PICKUP.lng, address: 'A' },
  destination: { lat: 31.53, lng: 74.36, address: 'B' },
  city: 'Lahore',
  category: 'zip',
  serviceType: 'ride',
  passengerOfferMinor: 45000,
  pricingSnapshotId: 'ps1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

describe('event-driven dispatch', () => {
  it('createRide fires wave 1 inline and arms wave-2 + expiry tasks', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const scheduler = new FakeScheduler();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const drivers = await seedDrivers(db, geoStore, 6, Date.now());
    const app = appFor(db, { t: 'p1' }, { geoStore, dispatchTaskScheduler: scheduler });

    const res = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'ed-create-1')
      .send(createBody);
    expect(res.status).toBe(201);
    const rideId = res.body.data.rideId as string;

    // Wave 1 committed inline (kick runs post-response; poll the store).
    await waitFor(async () => {
      const w = await getDoc(db, 'rideDispatchWaves', waveDocId(rideId, 1));
      return !!w;
    });
    const wave1 = (await getDoc(db, 'rideDispatchWaves', waveDocId(rideId, 1)))!;
    expect(wave1.status).toBe('COMPLETED');
    expect((wave1.driverIds as string[]).length).toBeGreaterThan(0);
    for (const id of wave1.driverIds as string[]) {
      expect(drivers).toContain(id);
    }
    expect(wave1.inviteExpiresAt).toBeTruthy();

    const ride = (await getDoc(db, 'rides', rideId))!;
    expect(ride.dispatchWave).toBe(1);
    expect(ride.dispatchStatus).toBe('active');

    // Durable wake-ups armed before the response: w1 kick-backstop (~+1s),
    // w2 deadline task (~cadence), and ride-expiry at expiresAt.
    await waitFor(async () => scheduler.ticks.length > 0);
    const kickTask = scheduler.ticks.find(
      (t) => t.rideId === rideId && t.waveNumber === 1,
    )!;
    expect(kickTask.runAtMs).toBeLessThanOrEqual(Date.now() + 1250);
    const tickTask = scheduler.ticks.find(
      (t) => t.rideId === rideId && t.waveNumber === 2,
    )!;
    expect(tickTask.runAtMs).toBeGreaterThan(Date.now());
    expect(tickTask.runAtMs).toBeLessThanOrEqual(Date.now() + N4_WAVE_CADENCE_MS + 250);

    const expTask = scheduler.expires.find((t) => t.rideId === rideId)!;
    // Expiry task lands exactly on the server-authoritative ride deadline.
    expect(expTask.runAtMs).toBe(Date.parse(ride.expiresAt as string));
  });

  it('booking stays 201 even when inline dispatch throws', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    // geoStore null → nearby lookup fails inside kickDispatch; booking must still succeed.
    const app = appFor(db, { t: 'p1' }, { geoStore: null });
    const res = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'ed-create-fail')
      .send(createBody);
    expect(res.status).toBe(201);
  });

  it('early tick re-arms a task at the real dispatchNextAt (self-heal)', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const scheduler = new FakeScheduler();
    const nextAt = Date.now() + 30_000;
    seedSearchingRide(db, 'r1', {
      dispatchWave: 1,
      dispatchStatus: 'active',
      dispatchNextAt: new Date(nextAt).toISOString(),
    });
    const app = appFor(db, {}, { geoStore, dispatchTaskScheduler: scheduler });

    const res = await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(res.body.data.outcome).toBe('not_due');

    expect(scheduler.ticks.length).toBe(1);
    expect(scheduler.ticks[0].rideId).toBe('r1');
    expect(scheduler.ticks[0].waveNumber).toBe(2);
    expect(Math.abs(scheduler.ticks[0].runAtMs - nextAt)).toBeLessThan(1000);
  });

  it('all-declined latest wave accelerates the next wave', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const scheduler = new FakeScheduler();
    const now = Date.now();
    const drivers = await seedDrivers(db, geoStore, 8, now);

    seedSearchingRide(db, 'r1', {
      dispatchWave: 1,
      dispatchStatus: 'active',
      dispatchNextAt: new Date(now + N4_WAVE_CADENCE_MS).toISOString(),
    });
    const invited = drivers.slice(0, 5);
    db.seed('rideDispatchWaves', waveDocId('r1', 1), {
      waveId: waveDocId('r1', 1),
      rideId: 'r1',
      waveNumber: 1,
      requestVersion: 1,
      driverIds: invited,
      radiusKm: 10,
      status: 'COMPLETED',
      createdAt: new Date(now).toISOString(),
      completedAt: new Date(now).toISOString(),
      inviteExpiresAt: new Date(now + 20_000).toISOString(),
    });

    const tokens = Object.fromEntries(
      invited.map((id, i) => [`d${i}`, id]),
    );
    const app = appFor(db, tokens, {
      geoStore,
      dispatchTaskScheduler: scheduler,
    });

    // Every invited driver declines → last decline should trigger wave 2 now,
    // not at dispatchNextAt.
    for (const [i, id] of invited.entries()) {
      const res = await request(app)
        .post(`/v1/rides/r1/invites/${waveDocId('r1', 1)}/decline`)
        .set('Authorization', `Bearer d${i}`);
      expect(res.status).toBe(200);
      void id;
    }

    const wave2 = await getDoc(db, 'rideDispatchWaves', waveDocId('r1', 2));
    expect(wave2).not.toBeNull();
    expect(wave2!.waveNumber).toBe(2);
    // Wave-2 cohort excludes wave-1 invitees.
    for (const id of wave2!.driverIds as string[]) {
      expect(invited).not.toContain(id);
    }
  });

  it('partial declines do not accelerate (wave stays on cadence)', async () => {
    const db = memoryDb();
    const geoStore = createMemoryGeoStore();
    const scheduler = new FakeScheduler();
    const now = Date.now();
    const drivers = await seedDrivers(db, geoStore, 5, now);
    const invited = drivers.slice(0, 3);
    const nextAt = now + N4_WAVE_CADENCE_MS;
    seedSearchingRide(db, 'r1', {
      dispatchWave: 1,
      dispatchStatus: 'active',
      dispatchNextAt: new Date(nextAt).toISOString(),
    });
    db.seed('rideDispatchWaves', waveDocId('r1', 1), {
      waveId: waveDocId('r1', 1),
      rideId: 'r1',
      waveNumber: 1,
      requestVersion: 1,
      driverIds: invited,
      status: 'COMPLETED',
      createdAt: new Date(now).toISOString(),
      completedAt: new Date(now).toISOString(),
      inviteExpiresAt: new Date(now + 20_000).toISOString(),
    });
    const app = appFor(db, { d0: invited[0] }, {
      geoStore,
      dispatchTaskScheduler: scheduler,
    });

    await request(app)
      .post(`/v1/rides/r1/invites/${waveDocId('r1', 1)}/decline`)
      .set('Authorization', 'Bearer d0')
      .expect(200);

    const wave2 = await getDoc(db, 'rideDispatchWaves', waveDocId('r1', 2));
    expect(wave2).toBeNull();
    const ride = (await getDoc(db, 'rides', 'r1'))!;
    expect(Date.parse(ride.dispatchNextAt as string)).toBeGreaterThanOrEqual(
      nextAt - 100,
    );
  });

  it('Cloud Tasks OIDC auth: allowlisted SA accepted, others rejected', async () => {
    const db = memoryDb();
    seedSearchingRide(db, 'r1', {
      dispatchWave: 1,
      dispatchStatus: 'active',
      dispatchNextAt: new Date(Date.now() + 30_000).toISOString(),
    });
    const verify = vi.fn(async (token: string) => {
      if (token === 'good') {
        return { email: 'tasks-invoker@x.iam.gserviceaccount.com', email_verified: true };
      }
      if (token === 'wrong-sa') {
        return { email: 'evil@x.iam.gserviceaccount.com', email_verified: true };
      }
      throw new Error('bad token');
    });
    const app = appFor(db, {}, {
      internalOidc: {
        audience: 'https://svc.example.run.app',
        allowedEmails: new Set(['tasks-invoker@x.iam.gserviceaccount.com']),
        verifyIdToken: verify,
      },
    });

    await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .set('Authorization', 'Bearer good')
      .expect(200);
    await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .set('Authorization', 'Bearer wrong-sa')
      .expect(403);
    await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .set('Authorization', 'Bearer garbage')
      .expect(403);
    await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .expect(403);
    // worker token path still works alongside OIDC.
    await request(app)
      .post('/v1/internal/rides/r1/dispatch-tick')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
  });

  it('per-ride expire route is idempotent', async () => {
    const db = memoryDb();
    seedSearchingRide(db, 'r1', {
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const app = appFor(db, {}, {});
    const r1 = await request(app)
      .post('/v1/internal/rides/r1/expire')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(r1.body.data.outcome).toBe('expired');
    const r2 = await request(app)
      .post('/v1/internal/rides/r1/expire')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(r2.body.data.outcome).toBe('already_expired');
  });
});

describe('CloudTasksDispatchScheduler', () => {
  function makeScheduler(capture: {
    calls: { url: string; body: Record<string, unknown> }[];
    status?: number;
  }) {
    const fetchFn = async (url: string, init: { body: string }) => {
      capture.calls.push({ url, body: JSON.parse(init.body) });
      return { status: capture.status ?? 200, json: async () => ({}) };
    };
    const scheduler = new CloudTasksDispatchScheduler(
      {
        project: 'p',
        location: 'us-central1',
        queue: 'ora-dispatch',
        targetBaseUrl: 'https://svc.run.app',
        oidcServiceAccount: 'invoker@p.iam.gserviceaccount.com',
      },
      { getAccessToken: async () => 'tok' },
      fetchFn,
    );
    return scheduler;
  }

  it('creates an OIDC-authenticated POST task with scheduleTime', async () => {
    const capture = { calls: [] as { url: string; body: Record<string, unknown> }[] };
    const scheduler = makeScheduler(capture);
    const runAt = Date.now() + 5000;
    const result = await scheduler.scheduleDispatchTick({
      rideId: 'ride1',
      waveNumber: 2,
      runAtMs: runAt,
      correlationId: 'c1',
    });
    expect(result.created).toBe(true);
    expect(capture.calls.length).toBe(1);
    const call = capture.calls[0];
    expect(call.url).toBe(
      'https://cloudtasks.googleapis.com/v2/projects/p/locations/us-central1/queues/ora-dispatch/tasks',
    );
    const task = (call.body as { task: Record<string, unknown> }).task;
    expect(task.name as string).toContain(`tasks/tick-ride1-w2-${Math.floor(runAt / 1000)}`);
    const httpReq = task.httpRequest as Record<string, unknown>;
    expect(httpReq.httpMethod).toBe('POST');
    expect(httpReq.url).toBe(
      'https://svc.run.app/v1/internal/rides/ride1/dispatch-tick',
    );
    const oidc = httpReq.oidcToken as Record<string, unknown>;
    expect(oidc.serviceAccountEmail).toBe('invoker@p.iam.gserviceaccount.com');
    expect(oidc.audience).toBe('https://svc.run.app');
    expect(task.scheduleTime).toBe(new Date(runAt).toISOString());
  });

  it('treats 409 ALREADY_EXISTS as success (dedupe)', async () => {
    const capture = {
      calls: [] as { url: string; body: Record<string, unknown> }[],
      status: 409,
    };
    const scheduler = makeScheduler(capture);
    const result = await scheduler.scheduleDispatchTick({
      rideId: 'ride1',
      waveNumber: 2,
      runAtMs: Date.now(),
      correlationId: 'c1',
    });
    expect(result.created).toBe(false);
  });

  it('throws on unexpected errors', async () => {
    const capture = {
      calls: [] as { url: string; body: Record<string, unknown> }[],
      status: 500,
    };
    const scheduler = makeScheduler(capture);
    await expect(
      scheduler.scheduleDispatchTick({
        rideId: 'ride1',
        waveNumber: 2,
        runAtMs: Date.now(),
        correlationId: 'c1',
      }),
    ).rejects.toThrow('Cloud Tasks create failed');
  });
});

describe('scheduler factory', () => {
  it('disabled env → noop', async () => {
    const env = createDispatchTaskSchedulerFromEnv({
      DISPATCH_TASKS_ENABLED: 'false',
    });
    expect(env.enabled).toBe(false);
    expect(env.scheduler).toBeInstanceOf(NoopDispatchTaskScheduler);
  });

  it('enabled but missing config → noop (logged)', () => {
    const env = createDispatchTaskSchedulerFromEnv({
      DISPATCH_TASKS_ENABLED: 'true',
      TASKS_PROJECT_ID: 'p',
    });
    expect(env.enabled).toBe(false);
  });
});
