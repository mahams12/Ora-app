/**
 * Driver payout snapshot — launch policy (fee NONE) focused tests.
 * Covers pure derivation + select-transaction integration + replay.
 */
import { describe, it, expect, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import {
  FEE_POLICIES_COLLECTION,
  GLOBAL_FEE_POLICY_ID,
  computePlatformFeeMinor,
  derivePayoutSnapshot,
  parseFeePolicyDoc,
} from '../pricing/fee_policy';

const NOW = '2026-10-19T00:00:00.000Z';

describe('fee_policy pure derivation', () => {
  it('1. launch default: no policy doc → fee 0, payout = fare', () => {
    const r = derivePayoutSnapshot({
      fareMinor: 27000,
      currency: 'PKR',
      policy: null,
      capturedAt: NOW,
    });
    expect(r.platformFeeMinor).toBe(0);
    expect(r.driverPayoutMinor).toBe(27000);
    expect(r.payoutCurrency).toBe('PKR');
    expect(r.feePolicySnapshot.resolution).toBe('LAUNCH_DEFAULT');
    expect(r.feePolicySnapshot.platformFeeType).toBe('NONE');
  });

  it('2. explicit NONE policy doc → APPLIED, payout = fare', () => {
    const r = derivePayoutSnapshot({
      fareMinor: 50000,
      currency: 'PKR',
      policy: {
        policyId: 'karachi_economy',
        version: 'v1',
        platformFeeType: 'NONE',
        currency: 'PKR',
      },
      capturedAt: NOW,
    });
    expect(r.feePolicySnapshot.resolution).toBe('APPLIED');
    expect(r.feePolicySnapshot.policyId).toBe('karachi_economy');
    expect(r.driverPayoutMinor).toBe(50000);
  });

  it('3. PERCENT_BPS floors deterministically (future support, inactive)', () => {
    // 100001 × 3333 / 10000 = 33330.33 → floor 33330; payout 66671.
    expect(
      computePlatformFeeMinor(100001, {
        platformFeeType: 'PERCENT_BPS',
        percentBps: 3333,
      }),
    ).toBe(33330);
    const r = derivePayoutSnapshot({
      fareMinor: 100001,
      currency: 'PKR',
      policy: {
        policyId: 'p',
        version: 'v',
        platformFeeType: 'PERCENT_BPS',
        percentBps: 3333,
        currency: 'PKR',
      },
      capturedAt: NOW,
    });
    expect(r.platformFeeMinor).toBe(33330);
    expect(r.driverPayoutMinor).toBe(66671);
  });

  it('4. fee clamps to fare — payout never negative', () => {
    expect(
      computePlatformFeeMinor(1000, {
        platformFeeType: 'FLAT_MINOR',
        flatMinor: 5000,
      }),
    ).toBe(1000);
    const r = derivePayoutSnapshot({
      fareMinor: 1000,
      currency: 'PKR',
      policy: {
        policyId: 'p',
        version: 'v',
        platformFeeType: 'FLAT_MINOR',
        flatMinor: 5000,
        currency: 'PKR',
      },
      capturedAt: NOW,
    });
    expect(r.driverPayoutMinor).toBe(0);
    expect(r.platformFeeMinor).toBe(1000);
    // percentBps > 10000 is an invalid policy → UNAVAILABLE, not clamped
    expect(
      Number.isNaN(
        computePlatformFeeMinor(1000, {
          platformFeeType: 'PERCENT_BPS',
          percentBps: 10001,
        }),
      ),
    ).toBe(true);
  });

  it('5. currency mismatch between policy and offer → UNAVAILABLE, nulls', () => {
    const r = derivePayoutSnapshot({
      fareMinor: 27000,
      currency: 'PKR',
      policy: {
        policyId: 'p',
        version: 'v',
        platformFeeType: 'NONE',
        currency: 'USD',
      },
      capturedAt: NOW,
    });
    expect(r.feePolicySnapshot.resolution).toBe('UNAVAILABLE');
    expect(r.driverPayoutMinor).toBeNull();
    expect(r.platformFeeMinor).toBeNull();
    expect(r.payoutCurrency).toBe('PKR'); // recorded currency kept for audit
  });

  it('6. invalid fare or currency → UNAVAILABLE, nothing fabricated', () => {
    for (const [fare, cur] of [
      [null, 'PKR'],
      [-5, 'PKR'],
      [12.5, 'PKR'],
      [27000, null],
      [27000, 'pkr'],
      [27000, 'XX'],
    ] as Array<[number | null, string | null]>) {
      const r = derivePayoutSnapshot({
        fareMinor: fare,
        currency: cur,
        policy: null,
        capturedAt: NOW,
      });
      expect(r.feePolicySnapshot.resolution).toBe('UNAVAILABLE');
      expect(r.driverPayoutMinor).toBeNull();
      expect(r.platformFeeMinor).toBeNull();
    }
  });

  it('7. malformed policy doc parses to null → launch default applies', () => {
    expect(
      parseFeePolicyDoc('x', { platformFeeType: 'WEIRD', version: '1', currency: 'PKR' }),
    ).toBeNull();
    expect(parseFeePolicyDoc('x', { platformFeeType: 'NONE', currency: 'PKR' })).toBeNull();
    expect(parseFeePolicyDoc('x', null)).toBeNull();
    const ok = parseFeePolicyDoc('x', {
      platformFeeType: 'PERCENT_BPS',
      percentBps: 2500,
      version: 'v2',
      currency: 'PKR',
    });
    expect(ok?.percentBps).toBe(2500);
  });
});

describe('payout snapshot in offer-select transaction', () => {
  function seedPassenger(db: ReturnType<typeof memoryDb>, uid: string) {
    db.seed('users', uid, {
      uid,
      phoneNumber: '+923001111111',
      displayName: 'Passenger',
      role: 'passenger',
      driverStatus: 'none',
      isActive: true,
      banned: false,
    });
  }
  function seedDriver(db: ReturnType<typeof memoryDb>, uid: string) {
    db.seed('users', uid, {
      uid,
      phoneNumber: '+923002222222',
      displayName: 'Driver',
      role: 'driver',
      driverStatus: 'approved',
      isActive: true,
      banned: false,
    });
  }
  function seedPricing(db: ReturnType<typeof memoryDb>) {
    db.seed('pricingSnapshots', 'snap-1', {
      snapshotId: 'snap-1',
      recommendedFareMinor: 25000,
      offerBoundMinMinor: 15000,
      offerBoundMaxMinor: 80000,
      currency: 'PKR',
      pricingRulesVersion: 'fixture-v1',
      computedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 3_600_000).toISOString(),
      inputs: { distanceKm: 5.2, durationMin: 18 },
    });
  }
  function authFor(uid: string) {
    return {
      verifyIdToken: vi.fn().mockResolvedValue({ uid, phone_number: '+92' }),
    } as never;
  }
  function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
    return createApp({
      auth: authFor(uid),
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
  }
  const createBody = {
    pickup: { lat: 24.86, lng: 67.0, address: 'A' },
    destination: { lat: 24.9, lng: 67.1, address: 'B' },
    city: 'Karachi',
    category: 'economy',
    serviceType: 'ride',
    passengerOfferMinor: 25000,
    pricingSnapshotId: 'snap-1',
    paymentMethod: 'CASH',
    passengerCount: 1,
  };
  async function setupRide(db: ReturnType<typeof memoryDb>, idemPrefix = '') {
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const created = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${idemPrefix}create-ride`)
      .send(createBody)
      .expect(201);
    const rideId = created.body.data.rideId as string;
    const offer = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `${idemPrefix}offer-create`)
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 27000,
        expectedRequestVersion: 1,
      })
      .expect(201);
    return { rideId, offerId: offer.body.data.offerId as string };
  }

  it('8. select derives launch-NONE payout atomically; driver-only exposure', async () => {
    const db = memoryDb();
    const { rideId, offerId } = await setupRide(db, 'a-');
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-1')
      .send({ expectedVersion: 2 })
      .expect(200);
    // Select is passenger-facing — payout internals must NOT be present.
    expect(res.body.data.driverPayoutMinor).toBeUndefined();
    expect(res.body.data.platformFeeMinor).toBeUndefined();
    expect(res.body.data.payoutCurrency).toBeUndefined();

    const ride = db.getDoc('rides', rideId) as Record<string, unknown>;
    expect(ride.driverPayoutMinor).toBe(27000);
    expect(ride.platformFeeMinor).toBe(0);
    expect((ride.feePolicySnapshot as { resolution: string }).resolution).toBe(
      'LAUNCH_DEFAULT',
    );

    // Driver GET sees the payout snapshot.
    const get = await request(appFor(db, 'd1'))
      .get(`/v1/rides/${rideId}`)
      .set('Authorization', 'Bearer t')
      .expect(200);
    expect(get.body.data.driverPayoutMinor).toBe(27000);
    expect(get.body.data.platformFeeMinor).toBe(0);
    expect(get.body.data.payoutCurrency).toBe('PKR');
    expect(get.body.data.feePolicyResolution).toBe('LAUNCH_DEFAULT');
  });

  it('8b. payout internals are never exposed to the passenger on GET/list', async () => {
    const db = memoryDb();
    const { rideId, offerId } = await setupRide(db, 'g-');
    await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-g')
      .send({})
      .expect(200);

    const PAYOUT_KEYS = [
      'driverPayoutMinor',
      'platformFeeMinor',
      'payoutCurrency',
      'feePolicyResolution',
    ];
    // Passenger GET — same ride, payout keys absent; agreed fare unchanged.
    const pGet = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${rideId}`)
      .set('Authorization', 'Bearer t')
      .expect(200);
    for (const k of PAYOUT_KEYS) {
      expect(pGet.body.data[k]).toBeUndefined();
    }
    expect(pGet.body.data.agreedFareMinor).toBe(27000);

    // Passenger list — same gating.
    const pList = await request(appFor(db, 'p1'))
      .get('/v1/rides?status=completed')
      .set('Authorization', 'Bearer t')
      .expect(200);
    const pRide = pList.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === rideId,
    );
    for (const k of PAYOUT_KEYS) {
      expect(pRide?.[k]).toBeUndefined();
    }

    // Driver list — payout keys present.
    const dList = await request(appFor(db, 'd1'))
      .get('/v1/rides')
      .set('Authorization', 'Bearer t')
      .expect(200);
    const dRide = dList.body.data.rides.find(
      (r: { rideId: string }) => r.rideId === rideId,
    );
    expect(dRide?.driverPayoutMinor).toBe(27000);
    expect(dRide?.platformFeeMinor).toBe(0);
    expect(dRide?.payoutCurrency).toBe('PKR');
    expect(dRide?.feePolicyResolution).toBe('LAUNCH_DEFAULT');
  });

  it('9. select replay returns identical recorded payout (no recompute)', async () => {
    const db = memoryDb();
    const { rideId, offerId } = await setupRide(db, 'b-');
    const app = appFor(db, 'p1');
    const first = await request(app)
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-r')
      .send({ expectedVersion: 2 })
      .expect(200);
    // Replay same idempotency key — recorded response, not recomputed.
    const replay = await request(app)
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-r')
      .send({ expectedVersion: 2 })
      .expect(200);
    expect(replay.body.data).toEqual(first.body.data);
    // Second key hits the already-assigned idempotent-success path.
    const again = await request(app)
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-r2')
      .send({})
      .expect(200);
    // Passenger-facing select path never carries payout internals.
    expect(again.body.data.driverPayoutMinor).toBeUndefined();
    expect(db.getDoc('rides', rideId)?.driverPayoutMinor).toBe(27000);
  });

  it('10. explicit feePolicies doc (NONE) → APPLIED resolution', async () => {
    const db = memoryDb();
    db.seed(FEE_POLICIES_COLLECTION, 'karachi_economy', {
      platformFeeType: 'NONE',
      version: 'v1',
      currency: 'PKR',
    });
    const { rideId, offerId } = await setupRide(db, 'c-');
    await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-c')
      .send({})
      .expect(200);
    const ride = db.getDoc('rides', rideId) as Record<string, unknown>;
    const snap = ride.feePolicySnapshot as Record<string, unknown>;
    expect(snap.resolution).toBe('APPLIED');
    expect(snap.policyId).toBe('karachi_economy');
    expect(ride.driverPayoutMinor).toBe(27000);
  });

  it('11. completion replay never recomputes payout', async () => {
    const db = memoryDb();
    const { rideId, offerId } = await setupRide(db, 'd-');
    await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-key-d')
      .send({})
      .expect(200);
    // Drive the ride to completion via the dedicated transition endpoints.
    const driverApp = appFor(db, 'd1');
    for (const path of ['en-route', 'arrive', 'start', 'complete']) {
      await request(driverApp)
        .post(`/v1/rides/${rideId}/${path}`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `prog-${path}-key`)
        .send({})
        .expect(200);
    }
    const ride = db.getDoc('rides', rideId) as Record<string, unknown>;
    expect(ride.state).toBe('RIDE_COMPLETED');
    expect(ride.driverPayoutMinor).toBe(27000);
    expect(ride.platformFeeMinor).toBe(0);
    // Replay the complete transition — payout fields unchanged.
    await request(driverApp)
      .post(`/v1/rides/${rideId}/complete`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'prog-again-key')
      .send({})
      .expect(200);
    const after = db.getDoc('rides', rideId) as Record<string, unknown>;
    expect(after.driverPayoutMinor).toBe(27000);
    expect(after.platformFeeMinor).toBe(0);
  });
});
