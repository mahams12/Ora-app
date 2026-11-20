import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import { normalizeCitySlug } from '../redis/types';

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  db.seed('users', uid, {
    uid,
    role: 'passenger',
    isActive: true,
    banned: false,
    displayName: uid,
  });
  db.seed('pricingSnapshots', 'snap-1', {
    snapshotId: 'snap-1',
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 10000,
    offerBoundMaxMinor: 100000,
    currency: 'PKR',
    pricingRulesVersion: 'v1',
    computedAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  });
  return createApp({
    auth: {
      verifyIdToken: async () => ({ uid, phone_number: '+100' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
  });
}

const baseBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

describe('rides.city create contract', () => {
  it('1. valid city accepted and normalized', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-valid-1')
      .send({ ...baseBody, city: '  Lahore ' });
    expect(res.status).toBe(201);
    expect(res.body.data.city).toBe('lahore');
    expect(normalizeCitySlug('  Lahore ')).toBe('lahore');
  });

  it('2. stored ride contains normalized city', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-store-1')
      .send({ ...baseBody, city: 'Karachi' });
    expect(res.status).toBe(201);
    const stored = db.getDoc('rides', res.body.data.rideId);
    expect(stored?.city).toBe('karachi');
  });

  it('3. empty city rejected', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-empty-1')
      .send({ ...baseBody, city: '   ' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('4. missing city rejected', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-missing-1')
      .send(baseBody);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('5. non-string city rejected', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-bad-1')
      .send({ ...baseBody, city: 123 });
    expect(res.status).toBe(400);
  });

  it('6. GET ride returns city; historical missing city tolerated', async () => {
    const db = memoryDb();
    const created = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-get-1')
      .send({ ...baseBody, city: 'Islamabad' });
    expect(created.status).toBe(201);
    const get = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${created.body.data.rideId}`)
      .set('Authorization', 'Bearer t');
    expect(get.status).toBe(200);
    expect(get.body.data.city).toBe('islamabad');

    db.seed('rides', 'legacy-1', {
      rideId: 'legacy-1',
      passengerId: 'p1',
      assignedDriverId: null,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category: 'economy',
      serviceType: 'ride',
      pickup: { lat: 24.86, lng: 67.0 },
      destination: { lat: 24.9, lng: 67.1 },
      pricingSnapshotId: 'snap-1',
      recommendedFareMinor: 25000,
      passengerOfferMinor: 25000,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: null,
      paymentMethod: 'CASH',
      paymentIntentId: null,
      passengerCount: 1,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      assignedAt: null,
      arrivedAt: null,
      startedAt: null,
      completedAt: null,
      closedAt: null,
      cancelledBy: null,
      cancellationReason: null,
      cancellationFeeMinor: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    const legacy = await request(appFor(db, 'p1'))
      .get('/v1/rides/legacy-1')
      .set('Authorization', 'Bearer t');
    expect(legacy.status).toBe(200);
    expect(legacy.body.data.city).toBeUndefined();
  });

  it('7. N3-compatible slug (normalizeCitySlug)', () => {
    expect(normalizeCitySlug('Lahore')).toBe('lahore');
    expect(normalizeCitySlug('  KARACHI')).toBe('karachi');
  });

  it('8. unrelated create fields unchanged (state SEARCHING)', async () => {
    const db = memoryDb();
    const res = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'city-state-1')
      .send({ ...baseBody, city: 'lahore' });
    expect(res.status).toBe(201);
    expect(res.body.data.state).toBe('SEARCHING');
    expect(res.body.data.requestVersion).toBe(1);
    expect(res.body.data.assignedDriverId).toBeNull();
  });
});
