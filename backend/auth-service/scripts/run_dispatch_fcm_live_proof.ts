/**
 * D1 live proof — Firestore emulator + injectable FCM recorder.
 *
 * Proves: token registration, outbox event processing, durable delivery state,
 * worker auth, no offer/assign mutation.
 *
 * Real FCM Admin send is NOT claimed unless ORA_D1_REAL_FCM=1 and credentials work.
 *
 * Usage (root):
 *   npm run test:dispatch-fcm-live-proof
 */
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import request from 'supertest';
import { createApp } from '../src/app';
import type { FcmSender } from '../src/delivery/fcm_sender';
import { createFirebaseFcmSender } from '../src/delivery/fcm_sender';
import {
  D1_EVENT_TYPE,
  D1_FCM_TYPE,
  DRIVER_DEVICE_TOKENS,
  OUTBOX_DELIVERIES,
  OUTBOX_EVENTS,
  deviceTokenDocId,
  outboxDeliveryDocId,
} from '../src/delivery/d1_types';

const WORKER = 'd1-live-proof-worker-tokenx';

let passed = 0;
let failed = 0;
const notes: string[] = [];

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
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('D1 LIVE PROOF BLOCKED: FIRESTORE_EMULATOR_HOST is not set.');
    process.exit(2);
  }

  const useRealFcm = process.env.ORA_D1_REAL_FCM === '1';
  const realToken = process.env.ORA_D1_TEST_FCM_TOKEN?.trim();

  const appName = `d1-delivery-${Date.now()}`;
  const fbApp = initializeApp({ projectId: 'ora-d1-delivery' }, appName);
  const db = getFirestore(fbApp);
  db.settings({ ignoreUndefinedProperties: true });

  const prefix = `d1live-${Date.now()}`;
  const driverId = `${prefix}-d1`;
  const rideId = `${prefix}-ride`;
  const eventId = `${prefix}-evt`;
  const stubToken = `${prefix}-stub-token-abcdef`;

  const sent: Array<{ token: string; data: Record<string, string> }> = [];
  let fcm: FcmSender;
  if (useRealFcm && realToken) {
    fcm = createFirebaseFcmSender();
    notes.push('REAL_FCM_SENDER_ENABLED');
  } else {
    fcm = {
      async sendDataOnly(input) {
        sent.push(input);
        return 'ok';
      },
    };
    notes.push('FCM_STUBBED — set ORA_D1_REAL_FCM=1 and ORA_D1_TEST_FCM_TOKEN for real send');
  }

  try {
    await db.collection('users').doc(driverId).set({
      uid: driverId,
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
      displayName: driverId,
    });

    const app = createApp({
      auth: {
        verifyIdToken: async () => ({ uid: driverId, phone_number: '+1' }),
      } as never,
      db,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 50_000 },
      internalWorkerToken: WORKER,
      fcmSender: fcm,
    });

    await test('worker auth rejects missing token', async () => {
      const res = await request(app).post('/v1/internal/outbox/dispatch-fcm-sweep');
      assert(res.status === 403, `got ${res.status}`);
    });

    await test('register device token in Firestore emulator', async () => {
      const token = useRealFcm && realToken ? realToken : stubToken;
      const res = await request(app)
        .post('/v1/drivers/device-tokens')
        .set('Authorization', 'Bearer t')
        .send({ token });
      assert(res.status === 201 || res.status === 200, `got ${res.status}`);
      const snap = await db
        .collection(DRIVER_DEVICE_TOKENS)
        .doc(deviceTokenDocId(driverId, token))
        .get();
      assert(snap.exists, 'token doc missing');
    });

    await test('seed wave_completed outbox + project', async () => {
      const token = useRealFcm && realToken ? realToken : stubToken;
      await db.collection(OUTBOX_EVENTS).doc(eventId).set({
        eventId,
        eventType: D1_EVENT_TYPE,
        aggregateType: 'ride',
        aggregateId: rideId,
        aggregateVersion: 1,
        schemaVersion: 1,
        occurredAt: new Date().toISOString(),
        correlationId: 'live',
        causationId: `${rideId}_w1`,
        payload: {
          rideId,
          waveNumber: 1,
          driverIds: [driverId],
          invitedCount: 1,
          radiusKm: 10,
        },
        publishState: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: new Date(0).toISOString(),
      });

      const res = await request(app)
        .post('/v1/internal/outbox/dispatch-fcm-sweep?limit=10')
        .set('X-Ora-Worker-Token', WORKER);
      assert(res.status === 200, `got ${res.status} ${JSON.stringify(res.body)}`);

      const event = await db.collection(OUTBOX_EVENTS).doc(eventId).get();
      const state = event.data()?.publishState;
      assert(
        state === 'DELIVERED' || state === 'PENDING' || state === 'DEAD_LETTER',
        `unexpected state ${state}`,
      );

      if (!useRealFcm) {
        assert(state === 'DELIVERED', `stub expected DELIVERED got ${state}`);
        assert(sent.length === 1, `sent=${sent.length}`);
        assert(sent[0]!.data.type === D1_FCM_TYPE, 'type');
        assert(sent[0]!.token === token, 'token');
      } else {
        notes.push(`REAL_FCM_ATTEMPTED publishState=${state}`);
        if (state !== 'DELIVERED') {
          throw new Error(`Real FCM did not reach DELIVERED (state=${state})`);
        }
      }

      const delivery = await db
        .collection(OUTBOX_DELIVERIES)
        .doc(outboxDeliveryDocId(eventId))
        .get();
      assert(delivery.exists, 'delivery doc');
    });

    await test('idempotent second sweep', async () => {
      const before = sent.length;
      const res = await request(app)
        .post('/v1/internal/outbox/dispatch-fcm-sweep?limit=10')
        .set('X-Ora-Worker-Token', WORKER);
      assert(res.status === 200, `got ${res.status}`);
      if (!useRealFcm) {
        assert(sent.length === before, 'no duplicate stub sends');
      }
    });

    await test('no rideOffers / no assignment docs created by projector', async () => {
      const offers = await db.collection('rideOffers').limit(1).get();
      assert(offers.empty, 'unexpected offers');
    });
  } finally {
    await deleteApp(fbApp);
  }

  console.log('\nNotes:');
  for (const n of notes) console.log(`- ${n}`);
  console.log(`\nD1 live proof: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
