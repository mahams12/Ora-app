/**
 * NOTIF-RS-PUSH — ride-state FCM projector focused tests.
 * Mirrors delivery_d1.test.ts mechanics for the identifiers-only
 * RIDE_UPDATE nudge path.
 */
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import type { FcmSender, FcmSendResult } from '../delivery/fcm_sender';
import {
  D1_EVENT_TYPE,
  DRIVER_DEVICE_TOKENS,
  OUTBOX_DELIVERIES,
  OUTBOX_EVENTS,
  deviceTokenDocId,
} from '../delivery/d1_types';
import {
  PASSENGER_DEVICE_TOKENS,
  RS_MAX_ATTEMPTS,
  RS_SUBSCRIBER,
  passengerTokenDocId,
  rsDeliveryDocId,
} from '../delivery/ride_state_types';
import { RideStateFcmProjector } from '../delivery/ride_state_fcm_projector';

const WORKER = 'test-worker-token-rs-xxxx';

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

function seedRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  opts: { passengerId?: string | null; assignedDriverId?: string | null } = {},
) {
  db.seed('rides', rideId, {
    rideId,
    passengerId: opts.passengerId ?? 'p1',
    assignedDriverId: opts.assignedDriverId ?? null,
    state: 'DRIVER_ASSIGNED',
  });
}

function seedEvent(
  db: ReturnType<typeof memoryDb>,
  eventId: string,
  eventType: string,
  rideId = 'ride1',
  payload: Record<string, unknown> = {},
  overrides: Record<string, unknown> = {},
) {
  db.seed(OUTBOX_EVENTS, eventId, {
    eventId,
    eventType,
    aggregateType: 'ride',
    aggregateId: rideId,
    aggregateVersion: 1,
    schemaVersion: 1,
    occurredAt: new Date().toISOString(),
    correlationId: 'corr',
    causationId: `${rideId}_${eventId}`,
    payload: { rideId, ...payload },
    publishState: 'PENDING',
    attemptCount: 0,
    nextAttemptAt: new Date(0).toISOString(),
    ...overrides,
  });
}

function seedDriverToken(
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

function seedPassengerToken(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  token: string,
) {
  db.seed(PASSENGER_DEVICE_TOKENS, passengerTokenDocId(uid, token), {
    tokenId: passengerTokenDocId(uid, token),
    uid,
    token,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });
}

function projectorFor(db: ReturnType<typeof memoryDb>, fcm: FcmSender) {
  return new RideStateFcmProjector(db as never, fcm);
}

const PROCESS_INPUT = {
  correlationId: 'corr-test',
  workerId: 'w1',
};

describe('RS-PUSH passenger token registration', () => {
  it('1. passenger can register and clear a token on /v1/device-tokens', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', 'passenger');
    const app = appFor(db, 'p1');
    const res = await request(app)
      .post('/v1/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-passenger-token-aaaa' })
      .expect(201);
    expect(res.body.data.uid).toBe('p1');
    const stored = db.getDoc(
      PASSENGER_DEVICE_TOKENS,
      passengerTokenDocId('p1', 'fcm-passenger-token-aaaa'),
    );
    expect(stored?.token).toBe('fcm-passenger-token-aaaa');

    const del = await request(app)
      .delete('/v1/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-passenger-token-aaaa' })
      .expect(200);
    expect(del.body.data.cleared).toBe(true);
    expect(
      db.getDoc(
        PASSENGER_DEVICE_TOKENS,
        passengerTokenDocId('p1', 'fcm-passenger-token-aaaa'),
      ),
    ).toBeUndefined();
  });

  it('2. driver is rejected on the passenger token route; passenger rejected on driver route', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', 'driver', 'approved');
    seedUser(db, 'p1', 'passenger');
    const driverApp = appFor(db, 'd1');
    await request(driverApp)
      .post('/v1/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-driver-on-passenger-rt' })
      .expect(403);

    const passengerApp = appFor(db, 'p1');
    await request(passengerApp)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-passenger-on-driver-rt' })
      .expect(403);
  });

  it('3. passenger cannot spoof another uid — doc is scoped to the caller', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', 'passenger');
    const app = appFor(db, 'p1');
    await request(app)
      .post('/v1/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-spoof-token-xxxxxx' })
      .expect(201);
    // Extra uid field would be rejected by strict body parsing.
    await request(app)
      .post('/v1/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'fcm-spoof-token-xxxxxx', uid: 'victim' })
      .expect(400);
    expect(
      db.getDoc(
        PASSENGER_DEVICE_TOKENS,
        passengerTokenDocId('victim', 'fcm-spoof-token-xxxxxx'),
      ),
    ).toBeUndefined();
  });
});

describe('RS-PUSH projector delivery', () => {
  it('4. ride.assigned sends identifiers-only nudge to passenger + driver', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: 'd1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedDriverToken(db, 'd1', 'tok-d1-abcdefghij');
    seedEvent(db, 'ev-assign', 'ride.assigned');
    const { sender, sent } = recordingFcm();
    const p = projectorFor(db, sender);

    const res = await p.processEvent({ eventId: 'ev-assign', ...PROCESS_INPUT });
    expect(res.outcome).toBe('delivered');
    expect(res.sent).toBe(2);
    expect(sent).toHaveLength(2);
    const tokens = sent.map((s) => s.token).sort();
    expect(tokens).toEqual(['tok-d1-abcdefghij', 'tok-p1-abcdefghij']);
    for (const m of sent) {
      expect(m.data).toEqual({
        type: 'RIDE_UPDATE',
        rideId: 'ride1',
        eventId: 'ev-assign',
      });
    }
    const ev = db.getDoc(OUTBOX_EVENTS, 'ev-assign');
    expect(ev?.publishState).toBe('DELIVERED');
    const del = db.getDoc(OUTBOX_DELIVERIES, rsDeliveryDocId('ev-assign'));
    expect(del?.subscriber).toBe(RS_SUBSCRIBER);
    expect(del?.status).toBe('ACKED');
  });

  it('5. ride.driver.arrived nudges passenger only', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: 'd1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedDriverToken(db, 'd1', 'tok-d1-abcdefghij');
    seedEvent(db, 'ev-arrived', 'ride.driver.arrived');
    const { sender, sent } = recordingFcm();
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-arrived',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('delivered');
    expect(sent.map((s) => s.token)).toEqual(['tok-p1-abcdefghij']);
  });

  it('6. ride.completed and ride.cancelled nudge both parties', async () => {
    for (const type of ['ride.completed', 'ride.cancelled']) {
      const db = memoryDb();
      seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: 'd1' });
      seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
      seedDriverToken(db, 'd1', 'tok-d1-abcdefghij');
      seedEvent(db, `ev-${type}`, type);
      const { sender, sent } = recordingFcm();
      const res = await projectorFor(db, sender).processEvent({
        eventId: `ev-${type}`,
        ...PROCESS_INPUT,
      });
      expect(res.outcome).toBe('delivered');
      expect(sent.map((s) => s.token).sort()).toEqual([
        'tok-d1-abcdefghij',
        'tok-p1-abcdefghij',
      ]);
    }
  });

  it('7. ride.offer.selected resolves the driver via rideOffers doc fallback', async () => {
    const db = memoryDb();
    // Ride has no assignedDriverId yet — selection is in-flight.
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: null });
    db.seed('rideOffers', 'offer9', {
      offerId: 'offer9',
      rideId: 'ride1',
      driverId: 'd9',
      amountMinor: 50000,
      state: 'PENDING',
    });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedDriverToken(db, 'd9', 'tok-d9-abcdefghij');
    // Payload deliberately omits driverId — resolution must come from the offer doc.
    seedEvent(db, 'ev-sel', 'ride.offer.selected', 'ride1', {
      offerId: 'offer9',
    });
    const { sender, sent } = recordingFcm();
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-sel',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('delivered');
    expect(sent.map((s) => s.token)).toEqual(['tok-d9-abcdefghij']);
  });

  it('8. non-allowlisted events (created, rating, dispatch wave) are skipped', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: 'd1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedDriverToken(db, 'd1', 'tok-d1-abcdefghij');
    seedEvent(db, 'ev-created', 'ride.created');
    seedEvent(db, 'ev-rating', 'ride.rating.submitted');
    seedEvent(db, 'ev-wave', D1_EVENT_TYPE, 'ride1', {
      driverIds: ['d1'],
      waveNumber: 1,
    });
    const { sender, sent } = recordingFcm();
    const p = projectorFor(db, sender);
    for (const id of ['ev-created', 'ev-rating', 'ev-wave']) {
      const res = await p.processEvent({ eventId: id, ...PROCESS_INPUT });
      expect(res.outcome).toBe('skipped');
    }
    expect(sent).toHaveLength(0);
    // A sweep also must not pick them up.
    const sweep = await p.sweep({ correlationId: 'c' });
    expect(sent).toHaveLength(0);
    expect(sweep.delivered).toBe(0);
  });

  it('9. recipient with no registered token is SKIPPED_NO_TOKEN; event still completes', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: 'd1' });
    // Only driver has a token.
    seedDriverToken(db, 'd1', 'tok-d1-abcdefghij');
    seedEvent(db, 'ev-1', 'ride.assigned');
    const { sender, sent } = recordingFcm();
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-1',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('delivered');
    expect(res.skippedNoToken).toBe(1);
    expect(sent).toHaveLength(1);
    const del = db.getDoc(OUTBOX_DELIVERIES, rsDeliveryDocId('ev-1'));
    expect(del?.driverResults?.p1?.status).toBe('SKIPPED_NO_TOKEN');
    expect(del?.driverResults?.d1?.status).toBe('SENT');
  });

  it('10. duplicate processing is a no-op — no resend', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedEvent(db, 'ev-dup', 'ride.expired');
    const { sender, sent } = recordingFcm();
    const p = projectorFor(db, sender);
    await p.processEvent({ eventId: 'ev-dup', ...PROCESS_INPUT });
    const second = await p.processEvent({ eventId: 'ev-dup', ...PROCESS_INPUT });
    expect(second.outcome).toBe('already_done');
    expect(sent).toHaveLength(1);
  });

  it('11. no push ever goes to a non-recipient uid', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1', assignedDriverId: null });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    // An unrelated user with a registered token must never receive this nudge.
    seedPassengerToken(db, 'intruder', 'tok-intruder-xxx');
    seedDriverToken(db, 'intruder', 'tok-intruder-drv');
    seedEvent(db, 'ev-exp', 'ride.expired');
    const { sender, sent } = recordingFcm();
    await projectorFor(db, sender).processEvent({
      eventId: 'ev-exp',
      ...PROCESS_INPUT,
    });
    expect(sent.map((s) => s.token)).toEqual(['tok-p1-abcdefghij']);
  });

  it('12. invalid_token removes the stored token and still completes', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-bad-aaaaaaaaaaaa');
    seedEvent(db, 'ev-inv', 'ride.expired');
    const { sender } = recordingFcm(
      new Map([['tok-bad-aaaaaaaaaaaa', 'invalid_token']]),
    );
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-inv',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('delivered');
    expect(res.invalidTokens).toBe(1);
    expect(
      db.getDoc(
        PASSENGER_DEVICE_TOKENS,
        passengerTokenDocId('p1', 'tok-bad-aaaaaaaaaaaa'),
      ),
    ).toBeUndefined();
    const del = db.getDoc(OUTBOX_DELIVERIES, rsDeliveryDocId('ev-inv'));
    expect(del?.driverResults?.p1?.status).toBe('INVALID_TOKEN_REMOVED');
  });

  it('13. transient failure retries and only resends the failed token', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-good-aaaaaaaaaa');
    seedPassengerToken(db, 'p1', 'tok-flaky-aaaaaaaaa');
    seedEvent(db, 'ev-ret', 'ride.expired');
    const results = new Map<string, FcmSendResult>([
      ['tok-flaky-aaaaaaaaa', 'transient_error'],
    ]);
    const { sender, sent } = recordingFcm(results);
    const p = projectorFor(db, sender);

    const first = await p.processEvent({ eventId: 'ev-ret', ...PROCESS_INPUT });
    expect(first.outcome).toBe('retryable');
    const ev = db.getDoc(OUTBOX_EVENTS, 'ev-ret');
    expect(ev?.publishState).toBe('PENDING');

    // Flaky token recovers; reprocess — the good token must not be resent.
    results.set('tok-flaky-aaaaaaaaa', 'ok');
    const second = await p.processEvent({ eventId: 'ev-ret', ...PROCESS_INPUT });
    expect(second.outcome).toBe('delivered');
    const goodSends = sent.filter((s) => s.token === 'tok-good-aaaaaaaaaa');
    const flakySends = sent.filter((s) => s.token === 'tok-flaky-aaaaaaaaa');
    expect(goodSends).toHaveLength(1);
    expect(flakySends).toHaveLength(2);
  });

  it('14. exceeding max attempts dead-letters event + delivery', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-dead-aaaaaaaaaa');
    seedEvent(db, 'ev-dl', 'ride.expired', 'ride1', {}, {
      attemptCount: RS_MAX_ATTEMPTS - 1,
    });
    db.seed(OUTBOX_DELIVERIES, rsDeliveryDocId('ev-dl'), {
      deliveryId: rsDeliveryDocId('ev-dl'),
      eventId: 'ev-dl',
      subscriber: RS_SUBSCRIBER,
      status: 'FAILED_RETRYABLE',
      attemptCount: RS_MAX_ATTEMPTS - 1,
      leaseOwner: null,
      leaseExpiresAt: null,
      driverResults: {
        p1: {
          status: 'FAILED_RETRYABLE',
          lastError: 'fcm_transient',
          updatedAt: new Date().toISOString(),
          tokenResults: {},
        },
      },
      lastError: 'partial_or_transient_fcm_failure',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    const { sender } = recordingFcm(
      new Map([['tok-dead-aaaaaaaaaa', 'transient_error']]),
    );
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-dl',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('dead_letter');
    const ev = db.getDoc(OUTBOX_EVENTS, 'ev-dl');
    expect(ev?.publishState).toBe('DEAD_LETTER');
    const del = db.getDoc(OUTBOX_DELIVERIES, rsDeliveryDocId('ev-dl'));
    expect(del?.status).toBe('DEAD_LETTER');
  });

  it('15. active lease held by another worker → skipped, no send', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedEvent(db, 'ev-lease', 'ride.expired', 'ride1', {}, {
      publishState: 'CLAIMED',
      leaseOwner: 'other-worker',
      leaseExpiresAt: new Date(Date.now() + 60_000).toISOString(),
      attemptCount: 1,
    });
    const { sender, sent } = recordingFcm();
    const res = await projectorFor(db, sender).processEvent({
      eventId: 'ev-lease',
      ...PROCESS_INPUT,
    });
    expect(res.outcome).toBe('skipped');
    expect(sent).toHaveLength(0);
  });

  it('16. sweep prefers PENDING over CLAIMED and skips active leases', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    // A CLAIMED event with an active lease — must not be processed.
    seedEvent(db, 'ev-active', 'ride.assigned', 'ride1', {}, {
      publishState: 'CLAIMED',
      leaseOwner: 'other-worker',
      leaseExpiresAt: new Date(Date.now() + 60_000).toISOString(),
      attemptCount: 1,
    });
    seedEvent(db, 'ev-pending', 'ride.expired');
    const { sender, sent } = recordingFcm();
    const sweep = await projectorFor(db, sender).sweep({ correlationId: 'c' });
    expect(sweep.delivered).toBe(1);
    expect(sent).toHaveLength(1);
    expect(db.getDoc(OUTBOX_EVENTS, 'ev-active')?.publishState).toBe('CLAIMED');
  });
});

describe('RS-PUSH sweep endpoint', () => {
  it('17. worker token required; valid token sweeps and returns counts', async () => {
    const db = memoryDb();
    seedRide(db, 'ride1', { passengerId: 'p1' });
    seedPassengerToken(db, 'p1', 'tok-p1-abcdefghij');
    seedEvent(db, 'ev-ep', 'ride.expired');
    const { sender, sent } = recordingFcm();
    const app = appFor(db, 'p1', sender);

    await request(app)
      .post('/v1/internal/outbox/ride-state-fcm-sweep')
      .expect(403);

    const res = await request(app)
      .post('/v1/internal/outbox/ride-state-fcm-sweep')
      .set('X-Ora-Worker-Token', WORKER)
      .expect(200);
    expect(res.body.data.delivered).toBe(1);
    expect(sent).toHaveLength(1);
    expect(sent[0].data.type).toBe('RIDE_UPDATE');
  });
});
