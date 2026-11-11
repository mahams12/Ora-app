import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { COURIER_PARCEL_IN_TRANSIT } from '../rides/state_machine';
import type { ParcelOtp, RideDoc } from '../rides/types';

function seedPassenger(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: 'Passenger',
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923002222222',
    displayName: 'Driver',
    role: 'driver',
    driverStatus: 'approved',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function seedPricing(db: ReturnType<typeof memoryDb>, id = 'snap-1') {
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
    recommendedFareMinor: 30000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 90000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt,
    inputs: { distanceKm: 6.1, durationMin: 22 },
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid,
      phone_number: '+923001111111',
    }),
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

const parcel = {
  senderName: 'Ali Sender',
  senderPhone: '+923001111111',
  receiverName: 'Bilal Receiver',
  receiverPhone: '+923009999999',
  parcelCategory: 'documents',
  size: 'SMALL',
  weightKg: 1.5,
  quantity: 1,
  description: 'Office papers in an envelope',
  handlingInstructions: 'Keep dry',
  photoUrl: 'https://example.com/parcel.jpg',
};

const courierCreateBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  city: 'Karachi',
  category: 'courier_bike',
  serviceType: 'courier',
  passengerOfferMinor: 30000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  parcel,
};

async function createCourierRide(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  idem = 'courier-create-001',
) {
  const res = await request(appFor(db, passengerId))
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(courierCreateBody);
  expect(res.status).toBe(201);
  return res.body.data as { rideId: string; version: number; state: string };
}

/** Drive a courier ride to DRIVER_ASSIGNED and return its OTP bundle. */
async function assignCourierRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  passengerId: string,
  driverId: string,
  idemPrefix: string,
): Promise<ParcelOtp> {
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `${idemPrefix}-offer`)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 32000,
      expectedRequestVersion: 1,
    });
  expect(offer.status).toBe(201);
  const sel = await request(appFor(db, passengerId))
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', `${idemPrefix}-select`)
    .send({ expectedVersion: 2 });
  expect(sel.status).toBe(200);
  const doc = db.getDoc('rides', rideId) as RideDoc;
  expect(doc.parcelOtp).toBeDefined();
  return doc.parcelOtp!;
}

function driverPost(
  db: ReturnType<typeof memoryDb>,
  driverId: string,
  rideId: string,
  path: string,
  body: Record<string, unknown>,
  idem: string,
) {
  return request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}${path}`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(body);
}

async function toArrived(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  driverId: string,
  idemPrefix: string,
) {
  const enRoute = await driverPost(
    db,
    driverId,
    rideId,
    '/en-route',
    {},
    `${idemPrefix}-enroute`,
  );
  expect(enRoute.status).toBe(200);
  const arrived = await driverPost(
    db,
    driverId,
    rideId,
    '/arrive',
    {},
    `${idemPrefix}-arrive`,
  );
  expect(arrived.status).toBe(200);
}

describe('courier booking validation', () => {
  it('rejects courier create without a parcel manifest', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'c-no-parcel-key')
      .send({ ...courierCreateBody, parcel: undefined });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it.each([
    { field: 'size', value: 'XL' },
    { field: 'size', value: '' },
    { field: 'weightKg', value: 0 },
    { field: 'weightKg', value: 45 },
    { field: 'weightKg', value: 'heavy' },
    { field: 'quantity', value: 0 },
    { field: 'quantity', value: 60 },
    { field: 'parcelCategory', value: 'explosives' },
    { field: 'senderPhone', value: 'not-a-phone' },
    { field: 'receiverPhone', value: '12' },
    { field: 'description', value: '' },
    { field: 'photoUrl', value: 'http://insecure.example.com/x.jpg' },
  ])('rejects invalid parcel.$field', async ({ field, value }) => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `c-bad-${field}-${String(value).slice(0, 6)}-key`)
      .send({
        ...courierCreateBody,
        parcel: { ...parcel, [field]: value },
      });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects missing sender/receiver names', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'c-no-names-key')
      .send({
        ...courierCreateBody,
        parcel: { ...parcel, receiverName: undefined },
      });
    expect(res.status).toBe(400);
  });

  it('rejects parcel on non-courier service types', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'c-parcel-on-ride-key')
      .send({ ...courierCreateBody, serviceType: 'ride' });
    expect(res.status).toBe(400);
  });

  it('creates a courier booking with the parcel manifest persisted', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    expect(ride.state).toBe('SEARCHING');
    const doc = db.getDoc('rides', ride.rideId)!;
    expect(doc.serviceType).toBe('courier');
    expect((doc.parcel as { receiverPhone: string }).receiverPhone).toBe(
      '+923009999999',
    );
  });
});

describe('courier OTP lifecycle', () => {
  it('issues pickup/delivery/return codes at assignment (passenger-visible only)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'assign-a1');
    expect(otp.pickupCode).toMatch(/^\d{6}$/);
    expect(otp.deliveryCode).toMatch(/^\d{6}$/);
    expect(otp.returnCode).toMatch(/^\d{6}$/);
    expect(new Set([otp.pickupCode, otp.deliveryCode, otp.returnCode]).size)
      .toBeGreaterThanOrEqual(1); // random — just shape-check

    // Passenger projection exposes the codes.
    const pView = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    expect(pView.status).toBe(200);
    expect(pView.body.data.otpCodes.pickup).toBe(otp.pickupCode);
    expect(pView.body.data.otpCodes.delivery).toBe(otp.deliveryCode);
    expect(pView.body.data.otpCodes.return).toBe(otp.returnCode);
    expect(pView.body.data.parcel.receiverName).toBe('Bilal Receiver');

    // Driver projection sees the parcel (needs contacts) but never the codes.
    const dView = await request(appFor(db, 'd1'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    expect(dView.status).toBe(200);
    expect(dView.body.data.parcel.receiverPhone).toBe('+923009999999');
    expect(dView.body.data.otpCodes).toBeUndefined();
  });

  it('confirms parcel pickup only with the correct pickup code', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'assign-a2');
    await toArrived(db, ride.rideId, 'd1', 'assign-a2');

    // Missing code → rejected.
    const missing = await driverPost(db, 'd1', ride.rideId, '/start', {}, 'a2-start-1');
    expect(missing.status).toBe(403);
    expect(missing.body.error.code).toBe('OTP_INVALID');
    // Wrong code → rejected + attempts burned.
    const wrong = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: '000000' },
      'a2-start-2',
    );
    expect(wrong.status).toBe(403);
    expect(wrong.body.error.code).toBe('OTP_INVALID');
    const doc = db.getDoc('rides', ride.rideId)!;
    expect((doc.parcelOtp as ParcelOtp).attempts).toBe(2);

    // Correct code → RIDE_STARTED (parcel picked up).
    const ok = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: otp.pickupCode },
      'a2-start-3',
    );
    expect(ok.status).toBe(200);
    expect(ok.body.data.state).toBe('RIDE_STARTED');
    const after = db.getDoc('rides', ride.rideId)!;
    expect((after.parcelOtp as ParcelOtp).pickupUsedAt).not.toBeNull();
    expect(after.startedAt).not.toBeNull();
  });

  it('confirms delivery only with the delivery code and records completion', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'assign-a3');
    await toArrived(db, ride.rideId, 'd1', 'assign-a3');
    await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: otp.pickupCode },
      'a3-start-key',
    );

    const wrong = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/complete',
      { otp: otp.pickupCode },
      'a3-complete-1',
    );
    expect(wrong.status).toBe(403);

    const done = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/complete',
      { otp: otp.deliveryCode },
      'a3-complete-2',
    );
    expect(done.status).toBe(200);
    expect(done.body.data.state).toBe('RIDE_COMPLETED');
    expect(done.body.data.completedAt).not.toBeNull();
  });

  it('non-assigned drivers cannot burn OTP attempts (authorization first)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedDriver(db, 'd2');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'assign-a4');
    await toArrived(db, ride.rideId, 'd1', 'assign-a4');

    for (let i = 0; i < 3; i += 1) {
      const res = await driverPost(
        db,
        'd2',
        ride.rideId,
        '/start',
        { otp: '999999' },
        `attempts-d2-${i}`,
      );
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('FORBIDDEN');
    }
    const doc = db.getDoc('rides', ride.rideId)!;
    expect((doc.parcelOtp as ParcelOtp).attempts).toBe(0);
  });

  it('locks after repeated invalid codes', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'assign-a5');
    await toArrived(db, ride.rideId, 'd1', 'assign-a5');

    for (let i = 0; i < 10; i += 1) {
      const res = await driverPost(
        db,
        'd1',
        ride.rideId,
        '/start',
        { otp: '000000' },
        `lockout-wrong-${i}`,
      );
      expect(res.status).toBe(403);
    }
    const locked = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: otp.pickupCode },
      'a5-after-lock-key',
    );
    expect(locked.status).toBe(429);
    expect(locked.body.error.code).toBe('OTP_LOCKED');
  });
});

describe('courier cancellation rules', () => {
  it('passenger may cancel before assignment and before pickup', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const cancel = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'cc-preassign-key')
      .send({ reason: 'changed mind' });
    expect(cancel.status).toBe(200);
    expect(cancel.body.data.state).toBe('CANCELLED');
  });

  it('cancel after pickup is rejected — parcel must be delivered or returned', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createCourierRide(db, 'p1');
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', 'courier-cc1');
    await toArrived(db, ride.rideId, 'd1', 'courier-cc1');
    await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: otp.pickupCode },
      'cc1-start-key',
    );

    const passengerCancel = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'cc1-pcancel-key')
      .send({ reason: 'dont want' });
    expect(passengerCancel.status).toBe(409);
    expect(passengerCancel.body.error.code).toBe('STATE_CONFLICT');

    const driverCancel = await driverPost(
      db,
      'd1',
      ride.rideId,
      '/cancel',
      { reason: 'cant deliver' },
      'cc1-dcancel-key',
    );
    expect(driverCancel.status).toBe(409);
    expect(db.getDoc('rides', ride.rideId)!.state).toBe('RIDE_STARTED');
  });

  it('in-transit states are correctly classified', () => {
    expect(COURIER_PARCEL_IN_TRANSIT.has('RIDE_STARTED')).toBe(true);
    expect(COURIER_PARCEL_IN_TRANSIT.has('DELIVERY_FAILED')).toBe(true);
    expect(COURIER_PARCEL_IN_TRANSIT.has('RETURNING')).toBe(true);
    expect(COURIER_PARCEL_IN_TRANSIT.has('DRIVER_ARRIVED')).toBe(false);
  });
});

describe('courier delivery failure + return-to-sender', () => {
  async function toPickedUp(
    db: ReturnType<typeof memoryDb>,
    prefix: string,
  ): Promise<{ rideId: string; otp: ParcelOtp }> {
    const ride = await createCourierRide(db, 'p1', `${prefix}-create`);
    const otp = await assignCourierRide(db, ride.rideId, 'p1', 'd1', prefix);
    await toArrived(db, ride.rideId, 'd1', prefix);
    await driverPost(
      db,
      'd1',
      ride.rideId,
      '/start',
      { otp: otp.pickupCode },
      `${prefix}-start`,
    );
    return { rideId: ride.rideId, otp };
  }

  it('requires a valid failure reason', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const { rideId } = await toPickedUp(db, 'flow-f1');

    const bad = await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'ALIEN_ABDUCTION' },
      'f1-bad-reason',
    );
    expect(bad.status).toBe(400);

    const ok = await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'RECEIVER_UNREACHABLE' },
      'f1-ok-reason',
    );
    expect(ok.status).toBe(200);
    expect(ok.body.data.state).toBe('DELIVERY_FAILED');
    expect(ok.body.data.deliveryFailedReason).toBe('RECEIVER_UNREACHABLE');
    expect(ok.body.data.deliveryFailedAt).not.toBeNull();
  });

  it('supports retry → deliver after a failed attempt', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const { rideId, otp } = await toPickedUp(db, 'flow-f2');

    await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'ADDRESS_INCORRECT' },
      'f2-fail-key',
    );
    const retry = await driverPost(
      db,
      'd1',
      rideId,
      '/retry-delivery',
      {},
      'f2-retry-key',
    );
    expect(retry.status).toBe(200);
    expect(retry.body.data.state).toBe('RIDE_STARTED');

    const done = await driverPost(
      db,
      'd1',
      rideId,
      '/complete',
      { otp: otp.deliveryCode },
      'f2-complete-key',
    );
    expect(done.status).toBe(200);
    expect(done.body.data.state).toBe('RIDE_COMPLETED');
  });

  it('returns to sender: fail → return → confirm with return code', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const { rideId, otp } = await toPickedUp(db, 'flow-f3');

    await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'RECEIVER_REJECTED' },
      'f3-fail-key',
    );
    const ret = await driverPost(
      db,
      'd1',
      rideId,
      '/return-start',
      {},
      'f3-return-key',
    );
    expect(ret.status).toBe(200);
    expect(ret.body.data.state).toBe('RETURNING');
    expect(ret.body.data.returnStartedAt).not.toBeNull();

    // Wrong return code rejected.
    const wrong = await driverPost(
      db,
      'd1',
      rideId,
      '/return-complete',
      { otp: otp.deliveryCode },
      'f3-rc-bad-key',
    );
    expect(wrong.status).toBe(403);

    const done = await driverPost(
      db,
      'd1',
      rideId,
      '/return-complete',
      { otp: otp.returnCode },
      'f3-rc-ok-key',
    );
    expect(done.status).toBe(200);
    expect(done.body.data.state).toBe('RETURNED');
    expect(done.body.data.returnedAt).not.toBeNull();
    expect(done.body.data.completedAt).not.toBeNull();
  });

  it('cannot return before a delivery failure, and cannot fake completion', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const { rideId } = await toPickedUp(db, 'flow-f4');

    // Cannot jump straight to RETURNING while parcel just started.
    const early = await driverPost(
      db,
      'd1',
      rideId,
      '/return-start',
      {},
      'f4-early-key',
    );
    expect(early.status).toBe(409);

    // Cannot mark a RETURNED ride delivered.
    await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'OTHER' },
      'f4-fail-key',
    );
    await driverPost(db, 'd1', rideId, '/return-start', {}, 'f4-ret-key');
    const fake = await driverPost(
      db,
      'd1',
      rideId,
      '/complete',
      { otp: '123456' },
      'f4-fake-key',
    );
    expect(fake.status).toBe(409);
  });

  it('passenger can rate a RETURNED courier job', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const { rideId, otp } = await toPickedUp(db, 'flow-f5');
    await driverPost(
      db,
      'd1',
      rideId,
      '/delivery-failed',
      { reason: 'OTHER' },
      'f5-fail-key',
    );
    await driverPost(db, 'd1', rideId, '/return-start', {}, 'f5-ret-key');
    await driverPost(
      db,
      'd1',
      rideId,
      '/return-complete',
      { otp: otp.returnCode },
      'f5-rc-key',
    );
    const rating = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/ratings`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f5-rate-key')
      .send({ stars: 4 });
    expect(rating.status).toBe(201);
    expect(rating.body.data.ratingType).toBe('passenger_rates_driver');
  });
});

describe('ride serviceType isolation', () => {
  it('passenger rides still start/complete without OTP', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
    db.seed('pricingSnapshots', 'snap-1', {
      snapshotId: 'snap-1',
      recommendedFareMinor: 25000,
      offerBoundMinMinor: 15000,
      offerBoundMaxMinor: 80000,
      currency: 'PKR',
      pricingRulesVersion: 'fixture-v1',
      computedAt: new Date().toISOString(),
      expiresAt,
      inputs: { distanceKm: 5.2, durationMin: 18 },
    });
    const create = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'ride-create-key')
      .send({
        pickup: { lat: 24.86, lng: 67.0 },
        destination: { lat: 24.9, lng: 67.1 },
        city: 'Karachi',
        category: 'economy',
        serviceType: 'ride',
        passengerOfferMinor: 25000,
        pricingSnapshotId: 'snap-1',
        paymentMethod: 'CASH',
        passengerCount: 1,
      });
    expect(create.status).toBe(201);
    const rideId = create.body.data.rideId as string;
    expect(db.getDoc('rides', rideId)!.parcelOtp).toBeUndefined();

    const offer = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'ride-offer-key')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 25000,
        expectedRequestVersion: 1,
      });
    await request(appFor(db, 'p1'))
      .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'ride-select-key')
      .send({ expectedVersion: 2 });
    expect(db.getDoc('rides', rideId)!.parcelOtp).toBeUndefined();

    await driverPost(db, 'd1', rideId, '/en-route', {}, 'ride-enroute-key');
    await driverPost(db, 'd1', rideId, '/arrive', {}, 'ride-arrive-key');
    const start = await driverPost(db, 'd1', rideId, '/start', {}, 'ride-start-key');
    expect(start.status).toBe(200);
    const done = await driverPost(db, 'd1', rideId, '/complete', {}, 'ride-done-key');
    expect(done.status).toBe(200);
    expect(done.body.data.state).toBe('RIDE_COMPLETED');
  });
});
