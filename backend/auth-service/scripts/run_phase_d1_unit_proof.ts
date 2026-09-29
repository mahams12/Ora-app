/**
 * D1 unit proof (MemoryDb + recording FCM stub).
 * Does NOT claim real FCM delivery.
 *
 * Usage: npm run test:phase-d1-unit-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import type { FcmSender } from '../src/delivery/fcm_sender';
import {
  D1_EVENT_TYPE,
  D1_FCM_TYPE,
  DRIVER_DEVICE_TOKENS,
  OUTBOX_EVENTS,
  deviceTokenDocId,
} from '../src/delivery/d1_types';

const WORKER = 'd1-unit-proof-worker-tok';

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
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
  const db = memoryDb();
  db.seed('users', 'd1', {
    uid: 'd1',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
  });

  const sent: Array<{ token: string; data: Record<string, string> }> = [];
  const fcm: FcmSender = {
    async sendDataOnly(input) {
      sent.push(input);
      return 'ok';
    },
  };

  const app = createApp({
    auth: {
      verifyIdToken: async () => ({ uid: 'd1', phone_number: '+1' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    internalWorkerToken: WORKER,
    fcmSender: fcm,
  });

  await test('worker auth required for projector', async () => {
    const res = await request(app).post('/v1/internal/outbox/dispatch-fcm-sweep');
    assert(res.status === 403, `got ${res.status}`);
  });

  await test('register device token', async () => {
    const res = await request(app)
      .post('/v1/drivers/device-tokens')
      .set('Authorization', 'Bearer t')
      .send({ token: 'proof-fcm-token-12345678' });
    assert(res.status === 201, `got ${res.status}`);
    assert(
      db.getDoc(
        DRIVER_DEVICE_TOKENS,
        deviceTokenDocId('d1', 'proof-fcm-token-12345678'),
      ),
      'token stored',
    );
  });

  await test('projector sends data-only FCM for wave event', async () => {
    db.seed(OUTBOX_EVENTS, 'proof-evt', {
      eventId: 'proof-evt',
      eventType: D1_EVENT_TYPE,
      aggregateType: 'ride',
      aggregateId: 'ride-proof',
      aggregateVersion: 1,
      schemaVersion: 1,
      occurredAt: new Date().toISOString(),
      correlationId: 'c',
      causationId: 'ride-proof_w1',
      payload: {
        rideId: 'ride-proof',
        waveNumber: 1,
        driverIds: ['d1'],
        invitedCount: 1,
        radiusKm: 10,
      },
      publishState: 'PENDING',
      attemptCount: 0,
      nextAttemptAt: new Date(0).toISOString(),
    });

    const res = await request(app)
      .post('/v1/internal/outbox/dispatch-fcm-sweep')
      .set('X-Ora-Worker-Token', WORKER);
    assert(res.status === 200, `got ${res.status}`);
    assert(res.body.data.delivered >= 1, 'delivered');
    assert(sent.length === 1, `sent=${sent.length}`);
    assert(sent[0]!.data.type === D1_FCM_TYPE, 'type');
    assert(sent[0]!.data.rideId === 'ride-proof', 'rideId');
    assert(db.getDoc(OUTBOX_EVENTS, 'proof-evt')!.publishState === 'DELIVERED', 'state');
  });

  await test('no rideOffers created', async () => {
    for (const [path] of db.store.entries()) {
      assert(!path.startsWith('rideOffers/'), path);
    }
  });

  console.log(`\nD1 unit proof: ${passed} passed, ${failed} failed`);
  console.log('NOTE: FCM path used injectable stub — real FCM NOT PROVEN here.');
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
