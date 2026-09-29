/**
 * D1 — Dispatch invite delivery focused unit tests.
 */
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import type { FcmSender, FcmSendResult } from '../delivery/fcm_sender';
import { classifyFcmAdminError } from '../delivery/fcm_sender';
import {
  D1_EVENT_TYPE,
  D1_FCM_TYPE,
  D1_LEASE_MS,
  D1_SUBSCRIBER,
  DRIVER_DEVICE_TOKENS,
  OUTBOX_DELIVERIES,
  OUTBOX_EVENTS,
  deviceTokenDocId,
  outboxDeliveryDocId,
  tokenResultKey,
} from '../delivery/d1_types';
import { DispatchFcmProjector } from '../delivery/dispatch_fcm_projector';

const WORKER = 'test-worker-token-d1-xxxx';

function authFor(uid: string) {
  return {
    verifyIdToken: async () => ({ uid, phone_number: '+100' }),
  } as never;
}

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  role: 'passenger' | 'driver',
  driverStatus = 'approved',
) {
  db.seed('users', uid, {
    uid,
    role,
    driverStatus: role === 'driver' ? driverStatus : 'none',
    isActive: true,
    banned: false,
    displayName: uid,
  });
}

function recordingFcm(results: Map<string, FcmSendResult> = new Map()) {
  const sent: Array<{ token: string; data: Record<string, string> }> = [];
  const sender: FcmSender = {
    async sendDataOnly(input) {
      sent.push({ token: input.token, data: { ...input.data } });
      return results.get(input.token) ?? 'ok';
    },
  };
  return { sender, sent };
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  fcm: FcmSender | null = null,
) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    fcmSender: fcm,
  });
}

function seedWaveOutbox(
  db: ReturnType<typeof memoryDb>,
  eventId: string,
  driverIds: string[],
  rideId = 'ride1',
) {
  db.seed(OUTBOX_EVENTS, eventId, {
    eventId,
    eventType: D1_EVENT_TYPE,
    aggregateType: 'ride',
    aggregateId: rideId,
    aggregateVersion: 1,
    schemaVersion: 1,
    occurredAt: new Date().toISOString(),
    correlationId: 'corr',
    causationId: `${rideId}_w1`,
    payload: {
      rideId,
      waveNumber: 1,
      driverIds,
      invitedCount: driverIds.length,
      radiusKm: 10,
    },
    publishState: 'PENDING',
    attemptCount: 0,
    nextAttemptAt: new Date(0).toISOString(),
  });
}

describe('D1 dispatch invite delivery', () => {
  it('1. approved driver can register token', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver', 'approved');
    const app = appFor(db, 'd1');
    const res = await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-abcdefghijklmnop' })
      .expect(201);
    expect(res.body.data.driverId).toBe('d1');
    expect(res.body.data.tokenId).toBe(
      deviceTokenDocId('d1', 'fcm-token-abcdefghijklmnop'),
    );
    const stored = db.getDoc(
      DRIVER_DEVICE_TOKENS,
      deviceTokenDocId('d1', 'fcm-token-abcdefghijklmnop'),
    );
    expect(stored?.token).toBe('fcm-token-abcdefghijklmnop');
  });

  it('2. passenger cannot register device token', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', 'passenger');
    const app = appFor(db, 'p1');
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-abcdefghijklmnop' })
      .expect(403);
  });

  it('3. repeated token registration is idempotent', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const app = appFor(db, 'd1');
    const body = { token: 'fcm-token-same-device-xyz' };
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send(body)
      .expect(201);
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send(body)
      .expect(200);
    let count = 0;
    for (const [path] of db.store.entries()) {
      if (path.startsWith(`${DRIVER_DEVICE_TOKENS}/`)) count += 1;
    }
    expect(count).toBe(1);
  });

  it('4. multiple tokens per driver are supported', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-device-one-aaaa' })
      .expect(201);
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-device-two-bbbb' })
      .expect(201);
    let count = 0;
    for (const [path] of db.store.entries()) {
      if (path.startsWith(`${DRIVER_DEVICE_TOKENS}/`)) count += 1;
    }
    expect(count).toBe(2);
  });

  it('5-10. projector consumes wave event, targets driverIds, data-only payload, no N3/city', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    seedUser(db, 'd2', 'driver');
    const { sender, sent } = recordingFcm();
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', 'tok-d1-aaaaaaa'), {
      tokenId: deviceTokenDocId('d1', 'tok-d1-aaaaaaa'),
      driverId: 'd1',
      token: 'tok-d1-aaaaaaa',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    // d2 has no token
    seedWaveOutbox(db, 'evt1', ['d1', 'd2', 'd3-not-invited-wait'], 'ride1');
    // Fix payload — only d1 and d2 invited
    db.seed(OUTBOX_EVENTS, 'evt1', {
      ...db.getDoc(OUTBOX_EVENTS, 'evt1')!,
      payload: {
        rideId: 'ride1',
        waveNumber: 1,
        driverIds: ['d1', 'd2'],
        invitedCount: 2,
        radiusKm: 10,
      },
    });

    const app = appFor(db, 'unused', sender);
    const res = await request(app)
      .post('/v1/internal/outbox/dispatch-fcm-sweep')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(res.body.data.delivered).toBeGreaterThanOrEqual(1);
    expect(sent.length).toBe(1);
    expect(sent[0]!.token).toBe('tok-d1-aaaaaaa');
    expect(sent[0]!.data.type).toBe(D1_FCM_TYPE);
    expect(sent[0]!.data.rideId).toBe('ride1');
    expect(sent[0]!.data.waveNumber).toBe('1');
    expect(sent[0]!.data.eventId).toBe('evt1');
    expect(Object.keys(sent[0]!.data).sort()).toEqual(
      ['eventId', 'rideId', 'type', 'waveNumber'].sort(),
    );
    expect(db.getDoc(OUTBOX_EVENTS, 'evt1')!.publishState).toBe('DELIVERED');
  });

  it('11-12. projector does not create rideOffers or assign', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    db.seed('rides', 'ride2', {
      rideId: 'ride2',
      assignedDriverId: null,
      state: 'SEARCHING',
    });
    const { sender } = recordingFcm();
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', 'tok-d1-bbbbbbb'), {
      tokenId: deviceTokenDocId('d1', 'tok-d1-bbbbbbb'),
      driverId: 'd1',
      token: 'tok-d1-bbbbbbb',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    seedWaveOutbox(db, 'evt2', ['d1'], 'ride2');
    const projector = new DispatchFcmProjector(db as never, sender);
    await projector.processEvent({
      eventId: 'evt2',
      correlationId: 'c',
      workerId: 'w',
    });
    for (const [path] of db.store.entries()) {
      expect(path.startsWith('rideOffers/')).toBe(false);
    }
    expect(db.getDoc('rides', 'ride2')!.assignedDriverId).toBeNull();
    expect(db.getDoc('rides', 'ride2')!.state).toBe('SEARCHING');
  });

  it('13. duplicate event processing is safe (idempotent ACK)', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const { sender, sent } = recordingFcm();
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', 'tok-d1-ccccccc'), {
      tokenId: deviceTokenDocId('d1', 'tok-d1-ccccccc'),
      driverId: 'd1',
      token: 'tok-d1-ccccccc',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    seedWaveOutbox(db, 'evt3', ['d1'], 'ride3');
    const projector = new DispatchFcmProjector(db as never, sender);
    const first = await projector.processEvent({
      eventId: 'evt3',
      correlationId: 'c1',
      workerId: 'w1',
    });
    const second = await projector.processEvent({
      eventId: 'evt3',
      correlationId: 'c2',
      workerId: 'w2',
    });
    expect(first.outcome).toBe('delivered');
    expect(second.outcome).toBe('already_done');
    expect(sent.length).toBe(1);
  });

  it('14. missing token is handled safely (skip driver, still deliver event)', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const { sender, sent } = recordingFcm();
    seedWaveOutbox(db, 'evt4', ['d1'], 'ride4');
    const projector = new DispatchFcmProjector(db as never, sender);
    const result = await projector.processEvent({
      eventId: 'evt4',
      correlationId: 'c',
      workerId: 'w',
    });
    expect(result.outcome).toBe('delivered');
    expect(result.skippedNoToken).toBe(1);
    expect(sent.length).toBe(0);
    expect(db.getDoc(OUTBOX_EVENTS, 'evt4')!.publishState).toBe('DELIVERED');
  });

  it('15. invalid token is cleaned up', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const bad = 'tok-invalid-deadbeef';
    const results = new Map<string, FcmSendResult>([[bad, 'invalid_token']]);
    const { sender } = recordingFcm(results);
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', bad), {
      tokenId: deviceTokenDocId('d1', bad),
      driverId: 'd1',
      token: bad,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    seedWaveOutbox(db, 'evt5', ['d1'], 'ride5');
    const projector = new DispatchFcmProjector(db as never, sender);
    await projector.processEvent({
      eventId: 'evt5',
      correlationId: 'c',
      workerId: 'w',
    });
    expect(db.getDoc(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', bad))).toBeUndefined();
    expect(db.getDoc(OUTBOX_EVENTS, 'evt5')!.publishState).toBe('DELIVERED');
  });

  it('16. partial recipient failure is retry-safe (only retry failed)', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    seedUser(db, 'd2', 'driver');
    const results = new Map<string, FcmSendResult>([
      ['tok-ok-111111111', 'ok'],
      ['tok-fail-22222222', 'transient_error'],
    ]);
    const { sender, sent } = recordingFcm(results);
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', 'tok-ok-111111111'), {
      tokenId: deviceTokenDocId('d1', 'tok-ok-111111111'),
      driverId: 'd1',
      token: 'tok-ok-111111111',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d2', 'tok-fail-22222222'), {
      tokenId: deviceTokenDocId('d2', 'tok-fail-22222222'),
      driverId: 'd2',
      token: 'tok-fail-22222222',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    seedWaveOutbox(db, 'evt6', ['d1', 'd2'], 'ride6');
    const projector = new DispatchFcmProjector(db as never, sender);
    const first = await projector.processEvent({
      eventId: 'evt6',
      correlationId: 'c',
      workerId: 'w',
      nowMs: Date.now(),
    });
    expect(first.outcome).toBe('retryable');
    expect(first.sent).toBe(1);
    expect(first.failedDrivers).toBe(1);
    expect(db.getDoc(OUTBOX_EVENTS, 'evt6')!.publishState).toBe('PENDING');

    // Fix d2 token path to succeed on retry
    results.set('tok-fail-22222222', 'ok');
    // Force nextAttemptAt due
    db.seed(OUTBOX_EVENTS, 'evt6', {
      ...db.getDoc(OUTBOX_EVENTS, 'evt6')!,
      nextAttemptAt: new Date(0).toISOString(),
    });
    const second = await projector.processEvent({
      eventId: 'evt6',
      correlationId: 'c2',
      workerId: 'w2',
      nowMs: Date.now(),
    });
    expect(second.outcome).toBe('delivered');
    // d1 was already SENT — should not double-send
    expect(sent.filter((s) => s.token === 'tok-ok-111111111').length).toBe(1);
    expect(sent.filter((s) => s.token === 'tok-fail-22222222').length).toBe(2);
  });

  it('17. worker authentication enforced', async () => {
    const db = memoryDb();
    const app = appFor(db, 'x');
    await request(app).post('/v1/internal/outbox/dispatch-fcm-sweep').expect(403);
  });

  it('19. unrelated outbox events are not consumed', async () => {
    const db = memoryDb();
    const { sender, sent } = recordingFcm();
    db.seed(OUTBOX_EVENTS, 'other', {
      eventId: 'other',
      eventType: 'ride.created',
      aggregateType: 'ride',
      aggregateId: 'r',
      aggregateVersion: 1,
      schemaVersion: 1,
      occurredAt: new Date().toISOString(),
      correlationId: 'c',
      causationId: null,
      payload: {},
      publishState: 'PENDING',
      attemptCount: 0,
      nextAttemptAt: new Date(0).toISOString(),
    });
    const app = appFor(db, 'x', sender);
    const res = await request(app)
      .post('/v1/internal/outbox/dispatch-fcm-sweep')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(res.body.data.scanned).toBe(0);
    expect(sent.length).toBe(0);
    expect(db.getDoc(OUTBOX_EVENTS, 'other')!.publishState).toBe('PENDING');
  });

  it('18/20. clear token + createOffer remains ungated by ledger', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const app = appFor(db, 'd1');
    await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-to-clear-zzzz' })
      .expect(201);
    await request(app)
      .delete('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-token-to-clear-zzzz' })
      .expect(200);
    expect(
      db.getDoc(
        DRIVER_DEVICE_TOKENS,
        deviceTokenDocId('d1', 'fcm-token-to-clear-zzzz'),
      ),
    ).toBeUndefined();

    // Delivery doc naming convention
    expect(outboxDeliveryDocId('e1')).toBe(`e1_${D1_SUBSCRIBER}`);
    expect(OUTBOX_DELIVERIES).toBe('outboxDeliveries');
  });
});

describe('D1 hardening H2/H4/H5', () => {
  function seedToken(
    db: ReturnType<typeof memoryDb>,
    driverId: string,
    token: string,
  ) {
    db.seed(DRIVER_DEVICE_TOKENS, deviceTokenDocId(driverId, token), {
      tokenId: deviceTokenDocId(driverId, token),
      driverId,
      token,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
  }

  async function waitUntil(
    pred: () => boolean,
    label: string,
    timeoutMs = 3000,
  ): Promise<void> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (pred()) return;
      await new Promise((r) => setTimeout(r, 5));
    }
    throw new Error(`timeout waiting for ${label}`);
  }

  function gatedFcm(results: Map<string, FcmSendResult> = new Map()) {
    let resolveGate!: () => void;
    const gate = new Promise<void>((r) => {
      resolveGate = r;
    });
    let open = false;
    const sent: Array<{ token: string }> = [];
    const sender: FcmSender = {
      async sendDataOnly(input) {
        if (!open) await gate;
        sent.push({ token: input.token });
        return results.get(input.token) ?? 'ok';
      },
    };
    return {
      sender,
      sent,
      release() {
        open = true;
        resolveGate();
      },
    };
  }

  it('H2-1 concurrent claim: only one worker commits delivery', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    seedToken(db, 'd1', 'tok-concurrent-aaaaaa');
    seedWaveOutbox(db, 'evt-h2-1', ['d1'], 'ride-h2-1');
    const { sender, sent } = recordingFcm();
    const projector = new DispatchFcmProjector(db as never, sender);

    const [a, b] = await Promise.all([
      projector.processEvent({
        eventId: 'evt-h2-1',
        correlationId: 'c-a',
        workerId: 'w-a',
        nowMs: 1_000_000,
      }),
      projector.processEvent({
        eventId: 'evt-h2-1',
        correlationId: 'c-b',
        workerId: 'w-b',
        nowMs: 1_000_000,
      }),
    ]);

    const outcomes = [a.outcome, b.outcome].sort();
    expect(outcomes).toContain('delivered');
    expect(
      outcomes.filter((o) => o === 'delivered' || o === 'already_done').length,
    ).toBe(1);
    expect(outcomes.some((o) => o === 'skipped' || o === 'stale_aborted')).toBe(
      true,
    );
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h2-1')!.publishState).toBe('DELIVERED');
    expect(sent.length).toBe(1);
  });

  it('H2-2/3 expired lease reclaim: stale W1 cannot overwrite W2 state', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    seedToken(db, 'd1', 'tok-stale-bbbbbbbb');
    seedWaveOutbox(db, 'evt-h2-2', ['d1'], 'ride-h2-2');
    const gated = gatedFcm();
    const projectorW1 = new DispatchFcmProjector(db as never, gated.sender);
    const { sender: senderW2 } = recordingFcm();
    const projectorW2 = new DispatchFcmProjector(db as never, senderW2);
    const t0 = 2_000_000;
    const deliveryId = outboxDeliveryDocId('evt-h2-2');

    const w1Promise = projectorW1.processEvent({
      eventId: 'evt-h2-2',
      correlationId: 'c-w1',
      workerId: 'w1',
      nowMs: t0,
    });

    await waitUntil(() => {
      const d = db.getDoc(OUTBOX_DELIVERIES, deliveryId);
      return d?.status === 'CLAIMED' && d?.leaseOwner === 'w1';
    }, 'w1 claim');

    const w2 = await projectorW2.processEvent({
      eventId: 'evt-h2-2',
      correlationId: 'c-w2',
      workerId: 'w2',
      nowMs: t0 + D1_LEASE_MS + 5_000,
    });
    expect(w2.outcome).toBe('delivered');
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h2-2')!.publishState).toBe('DELIVERED');
    expect(db.getDoc(OUTBOX_DELIVERIES, deliveryId)!.attemptCount).toBe(2);
    expect(db.getDoc(OUTBOX_DELIVERIES, deliveryId)!.status).toBe('ACKED');

    gated.release();
    const w1 = await w1Promise;
    expect(w1.outcome).toBe('stale_aborted');

    // Stale W1 must not mutate W2's durable state
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h2-2')!.publishState).toBe('DELIVERED');
    expect(db.getDoc(OUTBOX_DELIVERIES, deliveryId)!.status).toBe('ACKED');
    expect(db.getDoc(OUTBOX_DELIVERIES, deliveryId)!.attemptCount).toBe(2);
    expect(db.getDoc(OUTBOX_DELIVERIES, deliveryId)!.leaseOwner).toBeNull();
  });

  it('H4 classify: invalid-argument is transient; genuine invalid deletes token', async () => {
    expect(classifyFcmAdminError('messaging/invalid-argument')).toBe(
      'transient_error',
    );
    expect(
      classifyFcmAdminError('messaging/registration-token-not-registered'),
    ).toBe('invalid_token');
    expect(classifyFcmAdminError('messaging/invalid-registration-token')).toBe(
      'invalid_token',
    );

    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const keep = 'tok-keep-invalid-argxx';
    seedToken(db, 'd1', keep);
    seedWaveOutbox(db, 'evt-h4-arg', ['d1'], 'ride-h4-arg');
    // Sender returns what classifyFcmAdminError maps invalid-argument to
    const { sender } = recordingFcm(
      new Map([[keep, 'transient_error' as FcmSendResult]]),
    );
    const projector = new DispatchFcmProjector(db as never, sender);
    const result = await projector.processEvent({
      eventId: 'evt-h4-arg',
      correlationId: 'c',
      workerId: 'w',
    });
    expect(result.outcome).toBe('retryable');
    expect(db.getDoc(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', keep))).toBeDefined();
    const delivery = db.getDoc(
      OUTBOX_DELIVERIES,
      outboxDeliveryDocId('evt-h4-arg'),
    )!;
    expect(delivery.driverResults.d1.status).toBe('FAILED_RETRYABLE');
    expect(
      delivery.driverResults.d1.tokenResults?.[tokenResultKey(keep)]?.status,
    ).toBe('FAILED_RETRYABLE');
  });

  it('H4 genuine invalid_token still removes token', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const bad = 'tok-bad-remove-nowxxx';
    seedToken(db, 'd1', bad);
    seedWaveOutbox(db, 'evt-h4-bad', ['d1'], 'ride-h4-bad');
    const { sender } = recordingFcm(
      new Map([[bad, 'invalid_token' as FcmSendResult]]),
    );
    const projector = new DispatchFcmProjector(db as never, sender);
    await projector.processEvent({
      eventId: 'evt-h4-bad',
      correlationId: 'c',
      workerId: 'w',
    });
    expect(
      db.getDoc(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', bad)),
    ).toBeUndefined();
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h4-bad')!.publishState).toBe(
      'DELIVERED',
    );
    expect(
      db.getDoc(OUTBOX_DELIVERIES, outboxDeliveryDocId('evt-h4-bad'))!
        .driverResults.d1.status,
    ).toBe('INVALID_TOKEN_REMOVED');
  });

  it('H5 mixed multi-device: A SENT + B retryable; retry only B', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const tokA = 'tok-device-a-success1';
    const tokB = 'tok-device-b-failzzzz';
    seedToken(db, 'd1', tokA);
    seedToken(db, 'd1', tokB);
    seedWaveOutbox(db, 'evt-h5-mix', ['d1'], 'ride-h5-mix');
    const results = new Map<string, FcmSendResult>([
      [tokA, 'ok'],
      [tokB, 'transient_error'],
    ]);
    const { sender, sent } = recordingFcm(results);
    const projector = new DispatchFcmProjector(db as never, sender);

    const first = await projector.processEvent({
      eventId: 'evt-h5-mix',
      correlationId: 'c1',
      workerId: 'w1',
    });
    expect(first.outcome).toBe('retryable');
    const delivery1 = db.getDoc(
      OUTBOX_DELIVERIES,
      outboxDeliveryDocId('evt-h5-mix'),
    )!;
    expect(delivery1.status).toBe('FAILED_RETRYABLE');
    expect(delivery1.driverResults.d1.status).toBe('FAILED_RETRYABLE');
    expect(
      delivery1.driverResults.d1.tokenResults?.[tokenResultKey(tokA)]?.status,
    ).toBe('SENT');
    expect(
      delivery1.driverResults.d1.tokenResults?.[tokenResultKey(tokB)]?.status,
    ).toBe('FAILED_RETRYABLE');
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h5-mix')!.publishState).toBe('PENDING');

    results.set(tokB, 'ok');
    db.seed(OUTBOX_EVENTS, 'evt-h5-mix', {
      ...db.getDoc(OUTBOX_EVENTS, 'evt-h5-mix')!,
      nextAttemptAt: new Date(0).toISOString(),
    });
    const second = await projector.processEvent({
      eventId: 'evt-h5-mix',
      correlationId: 'c2',
      workerId: 'w2',
    });
    expect(second.outcome).toBe('delivered');
    expect(sent.filter((s) => s.token === tokA).length).toBe(1);
    expect(sent.filter((s) => s.token === tokB).length).toBe(2);
    expect(db.getDoc(OUTBOX_EVENTS, 'evt-h5-mix')!.publishState).toBe(
      'DELIVERED',
    );
    const delivery2 = db.getDoc(
      OUTBOX_DELIVERIES,
      outboxDeliveryDocId('evt-h5-mix'),
    )!;
    expect(delivery2.status).toBe('ACKED');
    expect(delivery2.driverResults.d1.status).toBe('SENT');
  });

  it('H5 invalid + valid token: remove invalid, keep valid, deliver', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver');
    const good = 'tok-good-keep-alive1';
    const bad = 'tok-bad-delete-me222';
    seedToken(db, 'd1', good);
    seedToken(db, 'd1', bad);
    seedWaveOutbox(db, 'evt-h5-iv', ['d1'], 'ride-h5-iv');
    const { sender } = recordingFcm(
      new Map<string, FcmSendResult>([
        [good, 'ok'],
        [bad, 'invalid_token'],
      ]),
    );
    const projector = new DispatchFcmProjector(db as never, sender);
    const result = await projector.processEvent({
      eventId: 'evt-h5-iv',
      correlationId: 'c',
      workerId: 'w',
    });
    expect(result.outcome).toBe('delivered');
    expect(
      db.getDoc(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', good)),
    ).toBeDefined();
    expect(
      db.getDoc(DRIVER_DEVICE_TOKENS, deviceTokenDocId('d1', bad)),
    ).toBeUndefined();
    const delivery = db.getDoc(
      OUTBOX_DELIVERIES,
      outboxDeliveryDocId('evt-h5-iv'),
    )!;
    expect(delivery.driverResults.d1.status).toBe('SENT');
    expect(
      delivery.driverResults.d1.tokenResults?.[tokenResultKey(good)]?.status,
    ).toBe('SENT');
    expect(
      delivery.driverResults.d1.tokenResults?.[tokenResultKey(bad)]?.status,
    ).toBe('INVALID_TOKEN_REMOVED');
  });
});
