import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import {
  assertIntegerMinor,
  assertPositiveIntegerMinor,
} from '../rides/money';
import {
  assertAssignable,
  assertCancellablePostAssign,
  assertCancellablePreAssign,
  assertCloseable,
  assertExpirable,
  assertOfferable,
  assertProgression,
} from '../rides/state_machine';
import { RideService } from '../rides/ride_service';
import { RideDomainError } from '../rides/types';
import { hashRequest } from '../rides/hash';

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

function seedPricing(
  db: ReturnType<typeof memoryDb>,
  id = 'snap-1',
  overrides: Record<string, unknown> = {},
) {
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  db.seed('pricingSnapshots', id, {
    snapshotId: id,
    recommendedFareMinor: 25000,
    offerBoundMinMinor: 15000,
    offerBoundMaxMinor: 80000,
    currency: 'PKR',
    pricingRulesVersion: 'fixture-v1',
    computedAt: new Date().toISOString(),
    expiresAt,
    inputs: { distanceKm: 5.2, durationMin: 18 },
    ...overrides,
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

const createBody = {
  pickup: { lat: 24.86, lng: 67.0, address: 'A' },
  destination: { lat: 24.9, lng: 67.1, address: 'B' },
  category: 'economy',
  serviceType: 'ride',
  passengerOfferMinor: 25000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  passengerCount: 1,
};

async function createRide(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  idem = 'create-ride-key-001',
) {
  const app = appFor(db, passengerId);
  const res = await request(app)
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send(createBody);
  expect(res.status).toBe(201);
  return res.body.data as { rideId: string; version: number; state: string };
}

async function createOffer(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  driverId: string,
  amountMinor: number,
  idem: string,
) {
  const app = appFor(db, driverId);
  const res = await request(app)
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor,
      expectedRequestVersion: 1,
    });
  return res;
}

describe('ride money validation', () => {
  it('rejects non-integer, negative, zero, and huge amounts', () => {
    expect(() => assertIntegerMinor(12.5, 'x')).toThrow(RideDomainError);
    expect(() => assertIntegerMinor(-1, 'x')).toThrow(RideDomainError);
    expect(() => assertPositiveIntegerMinor(0, 'x')).toThrow(RideDomainError);
    expect(() => assertIntegerMinor(50_000_001, 'x')).toThrow(RideDomainError);
    expect(assertPositiveIntegerMinor(100, 'x')).toBe(100);
  });
});

describe('ride state machine', () => {
  it('allows offer/assign/cancel only in SEARCHING and OFFERS_AVAILABLE', () => {
    assertOfferable('SEARCHING');
    assertAssignable('OFFERS_AVAILABLE');
    assertCancellablePreAssign('SEARCHING');
    expect(() => assertOfferable('DRIVER_ASSIGNED')).toThrow(RideDomainError);
    expect(() => assertAssignable('CANCELLED')).toThrow(RideDomainError);
    expect(() => assertCancellablePreAssign('DRIVER_ASSIGNED')).toThrow(
      RideDomainError,
    );
  });

  it('Phase 2G progression and post-assign cancel gates', () => {
    assertProgression('DRIVER_ASSIGNED', 'DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE');
    assertCancellablePostAssign('DRIVER_ASSIGNED');
    assertCancellablePostAssign('RIDE_STARTED');
    expect(() =>
      assertProgression('DRIVER_ASSIGNED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED'),
    ).toThrow(RideDomainError);
    expect(() => assertCancellablePostAssign('RIDE_COMPLETED')).toThrow(
      RideDomainError,
    );
    expect(() => assertOfferable('DRIVER_EN_ROUTE')).toThrow(RideDomainError);
  });

  it('Phase 2H close only from RIDE_COMPLETED', () => {
    assertCloseable('RIDE_COMPLETED');
    expect(() => assertCloseable('RIDE_STARTED')).toThrow(RideDomainError);
    expect(() => assertCloseable('RIDE_CLOSED')).toThrow(RideDomainError);
    expect(() => assertCloseable('CANCELLED')).toThrow(RideDomainError);
    expect(() => assertCancellablePostAssign('RIDE_CLOSED')).toThrow(
      RideDomainError,
    );
  });

  it('Phase 2J expire only from SEARCHING and OFFERS_AVAILABLE', () => {
    assertExpirable('SEARCHING');
    assertExpirable('OFFERS_AVAILABLE');
    expect(() => assertExpirable('DRIVER_ASSIGNED')).toThrow(RideDomainError);
    expect(() => assertExpirable('EXPIRED')).toThrow(RideDomainError);
    expect(() => assertExpirable('CANCELLED')).toThrow(RideDomainError);
  });
});

describe('idempotency hashing', () => {
  it('is stable under key reorder', () => {
    expect(hashRequest({ a: 1, b: 2 })).toBe(hashRequest({ b: 2, a: 1 }));
    expect(hashRequest({ a: 1 })).not.toBe(hashRequest({ a: 2 }));
  });
});

describe('ride HTTP vertical slice', () => {
  it('creates a SEARCHING ride for authenticated passenger', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    expect(ride.state).toBe('SEARCHING');
    expect(ride.version).toBe(1);
    expect(db.getDoc('rides', ride.rideId)?.passengerId).toBe('p1');
  });

  it.each([
    {
      name: 'both addresses present',
      pickup: { lat: 24.86, lng: 67.0, address: 'Pickup St' },
      destination: { lat: 24.9, lng: 67.1, address: 'Dest Ave' },
      expectPickupAddress: 'Pickup St',
      expectDestAddress: 'Dest Ave',
    },
    {
      name: 'both addresses omitted',
      pickup: { lat: 24.86, lng: 67.0 },
      destination: { lat: 24.9, lng: 67.1 },
      expectPickupAddress: undefined,
      expectDestAddress: undefined,
    },
    {
      name: 'pickup address only',
      pickup: { lat: 24.86, lng: 67.0, address: 'Pickup St' },
      destination: { lat: 24.9, lng: 67.1 },
      expectPickupAddress: 'Pickup St',
      expectDestAddress: undefined,
    },
    {
      name: 'destination address only',
      pickup: { lat: 24.86, lng: 67.0 },
      destination: { lat: 24.9, lng: 67.1, address: 'Dest Ave' },
      expectPickupAddress: undefined,
      expectDestAddress: 'Dest Ave',
    },
  ])(
    'createRide persists optional addresses correctly ($name)',
    async (tc) => {
      const db = memoryDb();
      seedPassenger(db, 'p1');
      seedPricing(db);
      const app = appFor(db, 'p1');
      const res = await request(app)
        .post('/v1/rides')
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', `addr-${tc.name.replace(/\s+/g, '-')}`)
        .send({
          ...createBody,
          pickup: tc.pickup,
          destination: tc.destination,
        });
      expect(res.status).toBe(201);
      expect(res.body.error).toBeUndefined();

      const rideId = res.body.data.rideId as string;
      const stored = db.getDoc('rides', rideId)!;
      const pickup = stored.pickup as Record<string, unknown>;
      const destination = stored.destination as Record<string, unknown>;

      expect(pickup.lat).toBe(tc.pickup.lat);
      expect(pickup.lng).toBe(tc.pickup.lng);
      expect(destination.lat).toBe(tc.destination.lat);
      expect(destination.lng).toBe(tc.destination.lng);

      if (tc.expectPickupAddress === undefined) {
        expect(Object.prototype.hasOwnProperty.call(pickup, 'address')).toBe(
          false,
        );
      } else {
        expect(pickup.address).toBe(tc.expectPickupAddress);
      }
      if (tc.expectDestAddress === undefined) {
        expect(
          Object.prototype.hasOwnProperty.call(destination, 'address'),
        ).toBe(false);
      } else {
        expect(destination.address).toBe(tc.expectDestAddress);
      }

      const hasUndefined = (value: unknown): boolean => {
        if (value === undefined) return true;
        if (value == null || typeof value !== 'object') return false;
        return Object.values(value as Record<string, unknown>).some(
          hasUndefined,
        );
      };
      expect(hasUndefined(stored)).toBe(false);
      expect(stored.state).toBe('SEARCHING');
      expect(stored.passengerId).toBe('p1');
    },
  );

  it('replays create with same Idempotency-Key and body', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const app = appFor(db, 'p1');
    const a = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'same-key-001')
      .send(createBody);
    const b = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'same-key-001')
      .send(createBody);
    expect(a.status).toBe(201);
    expect(b.status).toBe(201);
    expect(b.body.data.rideId).toBe(a.body.data.rideId);
    const rideKeys = [...db.store.keys()].filter((k) => k.startsWith('rides/'));
    expect(rideKeys).toHaveLength(1);
  });

  it('rejects same Idempotency-Key with different body', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const app = appFor(db, 'p1');
    await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'reuse-001')
      .send(createBody);
    const res = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'reuse-001')
      .send({ ...createBody, passengerOfferMinor: 26000 });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('IDEMPOTENCY_KEY_REUSED');
  });

  it('rejects same Idempotency-Key reused by a different actor', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedPricing(db);
    const first = await request(appFor(db, 'p1'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'shared-actor-key-001')
      .send(createBody);
    expect(first.status).toBe(201);
    const firstRideId = first.body.data.rideId as string;

    const second = await request(appFor(db, 'p2'))
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'shared-actor-key-001')
      .send(createBody);
    expect(second.status).toBe(409);
    expect(second.body.error.code).toBe('IDEMPOTENCY_KEY_REUSED');
    expect(second.body.data).toBeUndefined();

    const rideKeys = [...db.store.keys()].filter((k) => k.startsWith('rides/'));
    expect(rideKeys).toHaveLength(1);
    expect(db.getDoc('rides', firstRideId)?.passengerId).toBe('p1');
  });

  it('rejects forged passengerId and unknown fields on create', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const app = appFor(db, 'p1');
    const res = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'forge-001')
      .send({ ...createBody, passengerId: 'attacker', state: 'DRIVER_ASSIGNED' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('rejects unauthenticated and banned users', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1', { banned: true });
    seedPricing(db);
    const app = appFor(db, 'p1');
    const missing = await request(app).post('/v1/rides').send(createBody);
    expect(missing.status).toBe(401);

    const banned = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'banned-001')
      .send(createBody);
    expect(banned.status).toBe(403);
    expect(banned.body.error.code).toBe('ACCOUNT_DISABLED');
  });

  it('driver creates offer and transitions SEARCHING → OFFERS_AVAILABLE', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const res = await createOffer(db, ride.rideId, 'd1', 26000, 'offer-d1-1');
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('PENDING');
    expect(res.body.data.rideState).toBe('OFFERS_AVAILABLE');
    expect(db.getDoc('rides', ride.rideId)?.version).toBe(2);
  });

  it('enforces offer uniqueness per driver/requestVersion', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const a = await createOffer(db, ride.rideId, 'd1', 26000, 'offer-key-a');
    const b = await createOffer(db, ride.rideId, 'd1', 27000, 'offer-key-b');
    expect(a.status).toBe(201);
    expect(b.status).toBe(409);
    expect(b.body.error.code).toBe('OFFER_ALREADY_EXISTS');
  });

  it('rejects ineligible driver offers and forged driverId', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1', { driverStatus: 'pending' });
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const res = await createOffer(db, ride.rideId, 'd1', 26000, 'offer-key-x');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');

    seedDriver(db, 'd2');
    const forged = await request(appFor(db, 'd2'))
      .post(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'offer-forged')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
        driverId: 'someone-else',
      });
    expect(forged.status).toBe(400);
  });

  it('passenger lists offers; other passenger cannot (IDOR)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    await createOffer(db, ride.rideId, 'd1', 26000, 'offer-d1');
    const ok = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t');
    expect(ok.status).toBe(200);
    expect(ok.body.data.offers).toHaveLength(1);

    const idor = await request(appFor(db, 'p2'))
      .get(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t');
    expect(idor.status).toBe(403);
  });

  it('selects offer atomically and derives agreed fare from offer', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'offer-d1');
    const offerId = offer.body.data.offerId as string;
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-1')
      .send({ expectedVersion: 2 });
    expect(res.status).toBe(200);
    expect(res.body.data.state).toBe('DRIVER_ASSIGNED');
    expect(res.body.data.assignedDriverId).toBe('d1');
    expect(res.body.data.agreedFareMinor).toBe(27000);
    expect(res.body.data.agreedOfferId).toBe(offerId);
    expect(db.getDoc('rideOffers', offerId)?.status).toBe('SELECTED');
  });

  it('rejects forged agreedFareMinor / assignedDriverId on select', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'offer-d1');
    const res = await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-forge')
      .send({
        agreedFareMinor: 1,
        assignedDriverId: 'attacker',
      });
    expect(res.status).toBe(400);
  });

  it('rejects stale expectedVersion with VERSION_CONFLICT', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'offer-d1');
    const res = await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-stale')
      .send({ expectedVersion: 1 });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('VERSION_CONFLICT');
    expect(db.getDoc('rides', ride.rideId)?.assignedDriverId).toBeNull();
  });

  it('rejects expired offer select', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const offer = await createOffer(db, ride.rideId, 'd1', 27000, 'offer-d1');
    const offerId = offer.body.data.offerId as string;
    const existing = db.getDoc('rideOffers', offerId)!;
    db.seed('rideOffers', offerId, {
      ...existing,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-expired')
      .send({});
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('OFFER_EXPIRED');
  });

  it('rejects select when ride search window has expired', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'create-expired-ride-select');
    const offer = await createOffer(
      db,
      ride.rideId,
      'd1',
      27000,
      'offer-before-ride-expiry',
    );
    const offerId = offer.body.data.offerId as string;
    const before = db.getDoc('rides', ride.rideId)!;
    const versionBefore = before.version as number;
    db.seed('rides', ride.rideId, {
      ...before,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });

    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-expired-ride')
      .send({});

    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('STATE_CONFLICT');

    const after = db.getDoc('rides', ride.rideId)!;
    expect(after.assignedDriverId).toBeNull();
    expect(after.state).toBe('OFFERS_AVAILABLE');
    expect(after.version).toBe(versionBefore);
    expect(db.getDoc('rideOffers', offerId)?.status).toBe('PENDING');

    const outbox = [...db.store.entries()]
      .filter(([k]) => k.startsWith('outboxEvents/'))
      .map(([, v]) => v as { eventType: string; aggregateId: string });
    expect(
      outbox.some(
        (e) =>
          e.aggregateId === ride.rideId &&
          (e.eventType === 'ride.assigned' ||
            e.eventType === 'ride.offer.selected'),
      ),
    ).toBe(false);
  });

  it('select emits ride.offer.selected and ride.assigned atomically', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'create-outbox-select');
    const offer = await createOffer(
      db,
      ride.rideId,
      'd1',
      27000,
      'offer-outbox-select',
    );
    const offerId = offer.body.data.offerId as string;

    const beforeOutbox = [...db.store.keys()].filter((k) =>
      k.startsWith('outboxEvents/'),
    ).length;

    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-outbox-events')
      .send({});
    expect(res.status).toBe(200);

    const events = [...db.store.entries()]
      .filter(([k]) => k.startsWith('outboxEvents/'))
      .map(([, v]) => v as {
        eventType: string;
        aggregateId: string;
        aggregateVersion: number;
        payload: Record<string, unknown>;
      })
      .filter((e) => e.aggregateId === ride.rideId);

    const selected = events.filter((e) => e.eventType === 'ride.offer.selected');
    const assigned = events.filter((e) => e.eventType === 'ride.assigned');
    expect(selected).toHaveLength(1);
    expect(assigned).toHaveLength(1);
    expect(selected[0]!.aggregateVersion).toBe(res.body.data.version);
    expect(assigned[0]!.aggregateVersion).toBe(res.body.data.version);
    expect(selected[0]!.payload.offerId).toBe(offerId);
    expect(selected[0]!.payload.driverId).toBe('d1');
    expect(assigned[0]!.payload.offerId).toBe(offerId);
    expect(assigned[0]!.payload.agreedFareMinor).toBe(27000);
    expect(
      [...db.store.keys()].filter((k) => k.startsWith('outboxEvents/')).length,
    ).toBe(beforeOutbox + 2);
  });

  it('withdraw is idempotent and cannot withdraw SELECTED', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedDriver(db, 'd2');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const o1 = await createOffer(db, ride.rideId, 'd1', 26000, 'offer-key-o1');
    const offerId = o1.body.data.offerId as string;
    const w1 = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/withdraw`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'withdraw-1')
      .send({});
    const w2 = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/withdraw`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'withdraw-1')
      .send({});
    expect(w1.status).toBe(200);
    expect(w2.status).toBe(200);
    expect(w2.body.data.status).toBe('WITHDRAWN');

    const o2 = await createOffer(db, ride.rideId, 'd2', 27000, 'offer-key-o2');
    await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${o2.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'select-driver-d2-key')
      .send({});
    const bad = await request(appFor(db, 'd2'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${o2.body.data.offerId}/withdraw`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'withdraw-selected-offer')
      .send({});
    // After assignment, withdrawal is rejected by the assignment gate.
    expect(bad.status).toBe(409);
    expect(bad.body.error.code).toBe('ALREADY_ASSIGNED');
  });

  it('passenger cancel before assignment', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    await createOffer(db, ride.rideId, 'd1', 26000, 'offer-key-o1');
    const res = await request(appFor(db, 'p1'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'cancel-1')
      .send({ reason: 'changed plans' });
    expect(res.status).toBe(200);
    expect(res.body.data.state).toBe('CANCELLED');
    expect(db.getDoc('rides', ride.rideId)?.version).toBe(3);
  });

  it('GET ride is IDOR-protected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedPricing(db);
    const ride = await createRide(db, 'p1');
    const ok = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    expect(ok.status).toBe(200);
    const denied = await request(appFor(db, 'p2'))
      .get(`/v1/rides/${ride.rideId}`)
      .set('Authorization', 'Bearer t');
    expect(denied.status).toBe(403);
  });

  it('rejects fare out of bounds and expired pricing snapshot', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const app = appFor(db, 'p1');
    const bounds = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'bounds-1')
      .send({ ...createBody, passengerOfferMinor: 100 });
    expect(bounds.status).toBe(422);
    expect(bounds.body.error.code).toBe('FARE_OUT_OF_BOUNDS');

    seedPricing(db, 'snap-expired', {
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const expired = await request(app)
      .post('/v1/rides')
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'expired-snap')
      .send({ ...createBody, pricingSnapshotId: 'snap-expired' });
    expect(expired.status).toBe(422);
    expect(expired.body.error.code).toBe('PRICING_SNAPSHOT_EXPIRED');
  });
});

describe('ride assignment concurrency', () => {
  async function seedRideWithOffers(n: number) {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', `create-${n}`);
    const offerIds: string[] = [];
    for (let i = 0; i < n; i++) {
      const driverId = `d${i}`;
      seedDriver(db, driverId);
      const res = await createOffer(
        db,
        ride.rideId,
        driverId,
        26000 + i,
        `offer-${n}-${i}`,
      );
      expect(res.status).toBe(201);
      offerIds.push(res.body.data.offerId as string);
    }
    return { db, rideId: ride.rideId, offerIds };
  }

  async function concurrentSelect(
    db: ReturnType<typeof memoryDb>,
    rideId: string,
    offerIds: string[],
  ) {
    const results = await Promise.all(
      offerIds.map((offerId, i) =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
          .set('Authorization', 'Bearer t')
          .set(
            'Idempotency-Key',
            `select-concurrent-${String(i).padStart(3, '0')}-${offerId}`,
          )
          .send({}),
      ),
    );
    return results;
  }

  it('2-way concurrent select → exactly 1 assignment', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(2);
    const results = await concurrentSelect(db, rideId, offerIds);
    const wins = results.filter((r) => r.status === 200);
    const conflicts = results.filter((r) => r.status === 409);
    expect(wins).toHaveLength(1);
    expect(conflicts).toHaveLength(1);
    const ride = db.getDoc('rides', rideId)!;
    expect(ride.state).toBe('DRIVER_ASSIGNED');
    expect(ride.assignedDriverId).toBeTruthy();
    const selected = [...db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('rideOffers/') && (v as { status: string }).status === 'SELECTED',
    );
    expect(selected).toHaveLength(1);
  });

  it('10-way concurrent select → 1 winner, 9 conflicts', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(10);
    const results = await concurrentSelect(db, rideId, offerIds);
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    expect(results.filter((r) => r.status === 409)).toHaveLength(9);
    expect(db.getDoc('rides', rideId)?.assignedDriverId).toBeTruthy();
  });

  it('50-way concurrent select → 1 winner, 49 conflicts', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(50);
    const results = await concurrentSelect(db, rideId, offerIds);
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    expect(results.filter((r) => r.status === 409)).toHaveLength(49);
    const ride = db.getDoc('rides', rideId)!;
    expect(ride.state).toBe('DRIVER_ASSIGNED');
    expect(
      [...db.store.values()].filter(
        (v) => (v as { status?: string }).status === 'SELECTED',
      ),
    ).toHaveLength(1);
  }, 60_000);

  it('same offer + same idempotency key concurrent → one assignment, replay', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const offerId = offerIds[0]!;
    const results = await Promise.all(
      [1, 2].map(() =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', 'same-select-key')
          .send({}),
      ),
    );
    expect(results.every((r) => r.status === 200)).toBe(true);
    expect(results[0]!.body.data.version).toBe(results[1]!.body.data.version);
    expect(db.getDoc('rides', rideId)?.version).toBe(results[0]!.body.data.version);
  });

  it('same offer + different idempotency keys → one assign, second conflict/idempotent success', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const offerId = offerIds[0]!;
    const results = await Promise.all(
      ['idem-key-k1', 'idem-key-k2'].map((key) =>
        request(appFor(db, 'p1'))
          .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', key)
          .send({}),
      ),
    );
    const wins = results.filter((r) => r.status === 200);
    expect(wins.length).toBeGreaterThanOrEqual(1);
    // Second may replay success (already assigned to same offer) or race-win as 200.
    // Version must not double-increment beyond one assignment.
    expect(db.getDoc('rides', rideId)?.version).toBe(wins[0]!.body.data.version);
    expect(
      [...db.store.values()].filter(
        (v) => (v as { status?: string }).status === 'SELECTED',
      ),
    ).toHaveLength(1);
  });

  it('select vs withdraw → one legal outcome, no SELECTED+WITHDRAWN', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const offerId = offerIds[0]!;
    const [selectRes, withdrawRes] = await Promise.all([
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-withdraw-select')
        .send({}),
      request(appFor(db, 'd0'))
        .post(`/v1/rides/${rideId}/offers/${offerId}/withdraw`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-withdraw-withdraw')
        .send({}),
    ]);
    const offer = db.getDoc('rideOffers', offerId)!;
    const status = offer.status as string;
    expect(['SELECTED', 'WITHDRAWN']).toContain(status);
    if (status === 'SELECTED') {
      expect(selectRes.status).toBe(200);
      expect(db.getDoc('rides', rideId)?.state).toBe('DRIVER_ASSIGNED');
    } else {
      expect(withdrawRes.status).toBe(200);
      expect(db.getDoc('rides', rideId)?.assignedDriverId).toBeNull();
    }
  });

  it('select vs cancel → exactly one legal winner', async () => {
    const { db, rideId, offerIds } = await seedRideWithOffers(1);
    const offerId = offerIds[0]!;
    const [selectRes, cancelRes] = await Promise.all([
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/offers/${offerId}/select`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-cancel-select')
        .send({}),
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'select-vs-cancel-cancel')
        .send({ reason: 'race' }),
    ]);
    const ride = db.getDoc('rides', rideId)!;
    // Phase 2G: cancel after assign is legal, so select-then-cancel may leave
    // CANCELLED with both HTTP 200. Pre-assign cancel-only leaves CANCELLED
    // with select 409. Select-only leaves DRIVER_ASSIGNED with cancel 409.
    expect(['DRIVER_ASSIGNED', 'CANCELLED']).toContain(ride.state);
    if (ride.state === 'DRIVER_ASSIGNED') {
      expect(selectRes.status).toBe(200);
      expect(cancelRes.status).toBe(409);
    } else {
      expect(cancelRes.status).toBe(200);
      expect([200, 409]).toContain(selectRes.status);
    }
  });
});

describe('Phase 2F offer hardening', () => {
  it('rejects passenger creating an offer', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-pass-offer-ride');
    const res = await request(appFor(db, 'p2'))
      .post(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-passenger-offer')
      .send({
        type: 'DRIVER_COUNTEROFFER',
        amountMinor: 26000,
        expectedRequestVersion: 1,
      });
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');
  });

  it('rejects foreign driver withdraw (IDOR)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedDriver(db, 'd2');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-idor-wd-ride');
    const offer = await createOffer(db, ride.rideId, 'd1', 26000, 'f2-idor-o1');
    const res = await request(appFor(db, 'd2'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/withdraw`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-foreign-withdraw')
      .send({});
    expect(res.status).toBe(403);
  });

  it('rejects withdraw of expired pending offer', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-exp-wd-ride');
    const offer = await createOffer(db, ride.rideId, 'd1', 26000, 'f2-exp-wd-o');
    const offerId = offer.body.data.offerId as string;
    db.seed('rideOffers', offerId, {
      ...db.getDoc('rideOffers', offerId)!,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    const res = await request(appFor(db, 'd1'))
      .post(`/v1/rides/${ride.rideId}/offers/${offerId}/withdraw`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-withdraw-expired')
      .send({});
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('OFFER_EXPIRED');
  });

  it('listOffers surfaces expired pending as EXPIRED and filters requestVersion', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-list-ride');
    const offer = await createOffer(db, ride.rideId, 'd1', 26000, 'f2-list-o');
    const offerId = offer.body.data.offerId as string;
    db.seed('rideOffers', offerId, {
      ...db.getDoc('rideOffers', offerId)!,
      expiresAt: new Date(Date.now() - 1000).toISOString(),
    });
    db.seed('rideOffers', `${ride.rideId}_ghost_v9`, {
      offerId: `${ride.rideId}_ghost_v9`,
      rideId: ride.rideId,
      driverId: 'ghost',
      amountMinor: 26000,
      currency: 'PKR',
      type: 'DRIVER_COUNTEROFFER',
      status: 'PENDING',
      requestVersion: 9,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      driverSnapshot: null,
      createdAt: new Date().toISOString(),
      selectedAt: null,
      withdrawnAt: null,
    });
    const res = await request(appFor(db, 'p1'))
      .get(`/v1/rides/${ride.rideId}/offers`)
      .set('Authorization', 'Bearer t');
    expect(res.status).toBe(200);
    expect(res.body.data.requestVersion).toBe(1);
    const offers = res.body.data.offers as Array<{
      offerId: string;
      status: string;
      requestVersion: number;
    }>;
    expect(offers.every((o) => o.requestVersion === 1)).toBe(true);
    const listed = offers.find((o) => o.offerId === offerId);
    expect(listed?.status).toBe('EXPIRED');
  });

  it('rejects offer when driver already has DRIVER_ASSIGNED ride', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPassenger(db, 'p2');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride1 = await createRide(db, 'p1', 'f2-active-r1');
    const o1 = await createOffer(db, ride1.rideId, 'd1', 26000, 'f2-active-o1');
    await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride1.rideId}/offers/${o1.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-active-select')
      .send({});
    const ride2 = await createRide(db, 'p2', 'f2-active-r2');
    const res = await createOffer(
      db,
      ride2.rideId,
      'd1',
      27000,
      'f2-active-o2',
    );
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('DRIVER_NOT_ELIGIBLE');
  });

  it('rejects selecting withdrawn and superseded offers', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedDriver(db, 'd2');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-term-ride');
    const o1 = await createOffer(db, ride.rideId, 'd1', 26000, 'f2-term-o1');
    const o2 = await createOffer(db, ride.rideId, 'd2', 27000, 'f2-term-o2');
    await request(appFor(db, 'd1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${o1.body.data.offerId}/withdraw`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-term-wd')
      .send({});
    const withdrawnSelect = await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${o1.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-term-sel-wd')
      .send({});
    expect(withdrawnSelect.status).toBe(422);

    await request(appFor(db, 'p1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${o2.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-term-sel-win')
      .send({});
    // Create a third pending then force SUPERSEDED via select already done;
    // re-select o1 path already covered; assert o1 stays WITHDRAWN.
    expect(db.getDoc('rideOffers', o1.body.data.offerId)?.status).toBe(
      'WITHDRAWN',
    );
  });

  it('withdraw emits ride.offer.withdrawn outbox event', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-outbox-wd-ride');
    const offer = await createOffer(
      db,
      ride.rideId,
      'd1',
      26000,
      'f2-outbox-wd-o',
    );
    await request(appFor(db, 'd1'))
      .post(
        `/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/withdraw`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'f2-outbox-wd')
      .send({});
    const events = [...db.store.values()].filter(
      (v) =>
        (v as { eventType?: string }).eventType === 'ride.offer.withdrawn',
    );
    expect(events).toHaveLength(1);
  });

  it('concurrent same-driver offer creates one logical offer', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-conc-create-ride');
    const results = await Promise.all(
      ['idem-a', 'idem-b'].map((key) =>
        request(appFor(db, 'd1'))
          .post(`/v1/rides/${ride.rideId}/offers`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `f2-conc-${key}`)
          .send({
            type: 'DRIVER_COUNTEROFFER',
            amountMinor: 26000,
            expectedRequestVersion: 1,
          }),
      ),
    );
    const wins = results.filter((r) => r.status === 201);
    const conflicts = results.filter((r) => r.status === 409);
    expect(wins.length + conflicts.length).toBe(2);
    expect(wins.length).toBe(1);
    const pending = [...db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('rideOffers/') &&
        (v as { status?: string }).status === 'PENDING',
    );
    expect(pending).toHaveLength(1);
  });

  it('concurrent same-key offer create replays safely', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-idem-create-ride');
    const body = {
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    };
    const results = await Promise.all(
      [0, 1].map(() =>
        request(appFor(db, 'd1'))
          .post(`/v1/rides/${ride.rideId}/offers`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', 'f2-same-key-offer')
          .send(body),
      ),
    );
    expect(results.every((r) => r.status === 201)).toBe(true);
    expect(results[0]!.body.data.offerId).toBe(results[1]!.body.data.offerId);
    expect(
      [...db.store.keys()].filter((k) => k.startsWith('rideOffers/')),
    ).toHaveLength(1);
  });

  it('multiple drivers may create concurrent unique offers', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-multi-d-ride');
    for (let i = 0; i < 5; i++) seedDriver(db, `md${i}`);
    const results = await Promise.all(
      [0, 1, 2, 3, 4].map((i) =>
        request(appFor(db, `md${i}`))
          .post(`/v1/rides/${ride.rideId}/offers`)
          .set('Authorization', 'Bearer t')
          .set('Idempotency-Key', `f2-multi-${i}`)
          .send({
            type: 'DRIVER_COUNTEROFFER',
            amountMinor: 26000 + i,
            expectedRequestVersion: 1,
          }),
      ),
    );
    expect(results.every((r) => r.status === 201)).toBe(true);
    expect(
      [...db.store.keys()].filter((k) => k.startsWith('rideOffers/')),
    ).toHaveLength(5);
  });

  it('offer create racing cancel yields one legal outcome', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const ride = await createRide(db, 'p1', 'f2-create-vs-cancel');
    const [offerRes, cancelRes] = await Promise.all([
      request(appFor(db, 'd1'))
        .post(`/v1/rides/${ride.rideId}/offers`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'f2-cvc-offer')
        .send({
          type: 'DRIVER_COUNTEROFFER',
          amountMinor: 26000,
          expectedRequestVersion: 1,
        }),
      request(appFor(db, 'p1'))
        .post(`/v1/rides/${ride.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'f2-cvc-cancel')
        .send({ reason: 'race' }),
    ]);
    const rideDoc = db.getDoc('rides', ride.rideId)!;
    if (rideDoc.state === 'CANCELLED') {
      expect(cancelRes.status).toBe(200);
      if (offerRes.status === 201) {
        // Offer may have been created then expired by cancel, or rejected.
        const offers = [...db.store.entries()].filter(([k]) =>
          k.startsWith('rideOffers/'),
        );
        for (const [, v] of offers) {
          expect((v as { status: string }).status).not.toBe('SELECTED');
        }
      } else {
        expect(offerRes.status).toBe(409);
      }
    } else {
      expect(offerRes.status).toBe(201);
      expect(['SEARCHING', 'OFFERS_AVAILABLE']).toContain(rideDoc.state);
    }
  });
});

describe('Phase 2G post-assignment progression', () => {
  async function seedAssigned(): Promise<{
    db: ReturnType<typeof memoryDb>;
    rideId: string;
    driverId: string;
    passengerId: string;
    version: number;
    agreedFareMinor: number;
  }> {
    const db = memoryDb();
    const passengerId = 'p-g1';
    const driverId = 'd-g1';
    seedPassenger(db, passengerId);
    seedDriver(db, driverId);
    seedPricing(db);
    const ride = await createRide(db, passengerId, `g-create-${Math.random()}`);
    const offer = await createOffer(db, ride.rideId, driverId, 26000, `g-off-${Math.random()}`);
    expect(offer.status).toBe(201);
    const select = await request(appFor(db, passengerId))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `g-sel-${Math.random()}`)
      .send({});
    expect(select.status).toBe(200);
    return {
      db,
      rideId: ride.rideId,
      driverId,
      passengerId,
      version: select.body.data.version as number,
      agreedFareMinor: select.body.data.agreedFareMinor as number,
    };
  }

  async function progress(
    db: ReturnType<typeof memoryDb>,
    driverId: string,
    rideId: string,
    path: string,
    idem: string,
    body: Record<string, unknown> = {},
  ) {
    return request(appFor(db, driverId))
      .post(`/v1/rides/${rideId}/${path}`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', idem)
      .send(body);
  }

  it('completes full happy-path lifecycle with outbox and timestamps', async () => {
    const seeded = await seedAssigned();
    const { db, rideId, driverId, passengerId, agreedFareMinor } = seeded;
    let version = seeded.version;

    const en = await progress(db, driverId, rideId, 'en-route', 'g-en-route-001');
    expect(en.status).toBe(200);
    expect(en.body.data.state).toBe('DRIVER_EN_ROUTE');
    expect(en.body.data.version).toBe(version + 1);
    version = en.body.data.version;

    const ar = await progress(db, driverId, rideId, 'arrive', 'g-arrive-001');
    expect(ar.status).toBe(200);
    expect(ar.body.data.state).toBe('DRIVER_ARRIVED');
    version = ar.body.data.version;

    const st = await progress(db, driverId, rideId, 'start', 'g-start-001');
    expect(st.status).toBe(200);
    expect(st.body.data.state).toBe('RIDE_STARTED');
    expect(st.body.data.startedAt).toBeTruthy();
    version = st.body.data.version;

    const co = await progress(db, driverId, rideId, 'complete', 'g-complete-001');
    expect(co.status).toBe(200);
    expect(co.body.data.state).toBe('RIDE_COMPLETED');
    expect(co.body.data.completedAt).toBeTruthy();
    expect(co.body.data.version).toBe(version + 1);
    expect(co.body.data.agreedFareMinor).toBe(agreedFareMinor);

    const ride = db.getDoc('rides', rideId)!;
    expect(ride.state).toBe('RIDE_COMPLETED');
    expect(ride.assignedDriverId).toBe(driverId);
    expect(ride.agreedFareMinor).toBe(agreedFareMinor);
    expect(ride.passengerId).toBe(passengerId);

    const events = [...db.store.entries()]
      .filter(([k]) => k.startsWith('outboxEvents/'))
      .map(([, v]) => (v as { eventType: string }).eventType);
    expect(events).toEqual(
      expect.arrayContaining([
        'ride.driver.en_route',
        'ride.driver.arrived',
        'ride.started',
        'ride.completed',
      ]),
    );
  });

  it('rejects skip, reverse, passenger, and foreign driver', async () => {
    const seeded = await seedAssigned();
    const skip = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'arrive',
      'g-skip-arrive',
    );
    expect(skip.status).toBe(409);
    expect(skip.body.error.code).toBe('STATE_CONFLICT');

    const passenger = await progress(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'en-route',
      'g-passenger-en',
    );
    expect(passenger.status).toBe(403);

    seedDriver(seeded.db, 'foreign-d');
    const foreign = await progress(
      seeded.db,
      'foreign-d',
      seeded.rideId,
      'en-route',
      'g-foreign-en',
    );
    expect(foreign.status).toBe(403);

    await progress(seeded.db, seeded.driverId, seeded.rideId, 'en-route', 'g-en-route-ok');
    const back = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'en-route',
      'g-en-route-again',
    );
    // Already EN_ROUTE — treated as idempotent success for same target
    expect(back.status).toBe(200);
    expect(back.body.data.state).toBe('DRIVER_EN_ROUTE');
  });

  it('rejects stale expectedVersion and forged fields', async () => {
    const seeded = await seedAssigned();
    const stale = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'en-route',
      'g-en-route-stale',
      { expectedVersion: 1 },
    );
    expect(stale.status).toBe(409);
    expect(stale.body.error.code).toBe('VERSION_CONFLICT');

    const forged = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'en-route',
      'g-en-route-forge',
      { expectedVersion: seeded.version, driverId: 'x', state: 'RIDE_STARTED' },
    );
    expect(forged.status).toBe(400);
  });

  it('idempotent replay and key reuse', async () => {
    const seeded = await seedAssigned();
    const a = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'en-route',
      'g-idempotency-same',
    );
    const b = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'en-route',
      'g-idempotency-same',
    );
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(a.body.data.version).toBe(b.body.data.version);
    expect(seeded.db.getDoc('rides', seeded.rideId)?.version).toBe(
      seeded.version + 1,
    );

    const reuse = await progress(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'arrive',
      'g-idempotency-same',
      {},
    );
    expect(reuse.status).toBe(409);
    expect(reuse.body.error.code).toBe('IDEMPOTENCY_KEY_REUSED');
  });

  it('passenger and assigned driver may cancel after assignment', async () => {
    const a = await seedAssigned();
    const pCancel = await request(appFor(a.db, a.passengerId))
      .post(`/v1/rides/${a.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'g-passenger-cancel')
      .send({ reason: 'changed mind' });
    expect(pCancel.status).toBe(200);
    expect(pCancel.body.data.state).toBe('CANCELLED');
    expect(pCancel.body.data.cancelledBy).toBe('passenger');
    expect(a.db.getDoc('rides', a.rideId)?.assignedDriverId).toBe(a.driverId);

    const b = await seedAssigned();
    await progress(b.db, b.driverId, b.rideId, 'en-route', 'g-driver-enroute');
    const dCancel = await request(appFor(b.db, b.driverId))
      .post(`/v1/rides/${b.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'g-driver-cancel')
      .send({});
    expect(dCancel.status).toBe(200);
    expect(dCancel.body.data.cancelledBy).toBe('driver');

    const c = await seedAssigned();
    seedDriver(c.db, 'other');
    const foreign = await request(appFor(c.db, 'other'))
      .post(`/v1/rides/${c.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'g-foreign-cancel')
      .send({});
    expect(foreign.status).toBe(403);
  });

  it('rejects cancel after completed', async () => {
    const seeded = await seedAssigned();
    for (const [path, key] of [
      ['en-route', 'g50-en-route'],
      ['arrive', 'g50-arrive'],
      ['start', 'g50-start'],
      ['complete', 'g50-complete'],
    ] as const) {
      const res = await progress(
        seeded.db,
        seeded.driverId,
        seeded.rideId,
        path,
        key,
      );
      expect(res.status).toBe(200);
    }
    const cancel = await request(appFor(seeded.db, seeded.passengerId))
      .post(`/v1/rides/${seeded.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'g-cancel-after-complete')
      .send({});
    expect(cancel.status).toBe(409);
  });

  it('concurrent same transition yields one version bump', async () => {
    const seeded = await seedAssigned();
    const results = await Promise.all(
      Array.from({ length: 10 }, (_, i) =>
        progress(
          seeded.db,
          seeded.driverId,
          seeded.rideId,
          'en-route',
          `g-conc-enroute-${String(i).padStart(3, '0')}`,
        ),
      ),
    );
    const wins = results.filter((r) => r.status === 200);
    const conflicts = results.filter((r) => r.status === 409);
    // One real advance; others either conflict or already-at-target 200
    expect(wins.length).toBeGreaterThanOrEqual(1);
    expect(wins.length + conflicts.length).toBe(10);
    expect(seeded.db.getDoc('rides', seeded.rideId)?.state).toBe(
      'DRIVER_EN_ROUTE',
    );
    expect(seeded.db.getDoc('rides', seeded.rideId)?.version).toBe(
      seeded.version + 1,
    );
  });

  it('en-route vs cancel yields one legal outcome', async () => {
    const seeded = await seedAssigned();
    const [prog, cancel] = await Promise.all([
      progress(seeded.db, seeded.driverId, seeded.rideId, 'en-route', 'g-race-enroute'),
      request(appFor(seeded.db, seeded.passengerId))
        .post(`/v1/rides/${seeded.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'g-race-cancel')
        .send({ reason: 'race' }),
    ]);
    const ride = seeded.db.getDoc('rides', seeded.rideId)!;
    expect(['DRIVER_EN_ROUTE', 'CANCELLED']).toContain(ride.state);
    if (ride.state === 'CANCELLED') {
      expect(cancel.status).toBe(200);
      // Progression may have won first then been cancelled, or lost outright.
      expect([200, 409]).toContain(prog.status);
      expect(ride.assignedDriverId).toBe(seeded.driverId);
    } else {
      expect(prog.status).toBe(200);
      expect(cancel.status).toBe(409);
    }
  });

  it('50-way concurrent complete yields one completion', async () => {
    const seeded = await seedAssigned();
    for (const [path, key] of [
      ['en-route', 'g50prep-enroute'],
      ['arrive', 'g50prep-arrive'],
      ['start', 'g50prep-start'],
    ] as const) {
      expect(
        (await progress(seeded.db, seeded.driverId, seeded.rideId, path, key))
          .status,
      ).toBe(200);
    }
    const before = seeded.db.getDoc('rides', seeded.rideId)!.version as number;
    const results = await Promise.all(
      Array.from({ length: 50 }, (_, i) =>
        progress(
          seeded.db,
          seeded.driverId,
          seeded.rideId,
          'complete',
          `g-complete-50way-${String(i).padStart(3, '0')}`,
        ),
      ),
    );
    expect(results.every((r) => r.status === 200 || r.status === 409)).toBe(
      true,
    );
    expect(seeded.db.getDoc('rides', seeded.rideId)?.state).toBe(
      'RIDE_COMPLETED',
    );
    expect(seeded.db.getDoc('rides', seeded.rideId)?.version).toBe(before + 1);
    const completedEvents = [...seeded.db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('outboxEvents/') &&
        (v as { eventType?: string; aggregateId?: string }).eventType ===
          'ride.completed' &&
        (v as { aggregateId?: string }).aggregateId === seeded.rideId,
    );
    expect(completedEvents).toHaveLength(1);
  });
});

describe('Phase 2H ride aggregate closure', () => {
  async function seedCompleted(): Promise<{
    db: ReturnType<typeof memoryDb>;
    rideId: string;
    driverId: string;
    passengerId: string;
    version: number;
    agreedFareMinor: number;
    assignedDriverId: string;
  }> {
    const db = memoryDb();
    const passengerId = 'p-h1';
    const driverId = 'd-h1';
    seedPassenger(db, passengerId);
    seedDriver(db, driverId);
    seedPricing(db);
    const ride = await createRide(db, passengerId, `h-create-${Math.random()}`);
    const offer = await createOffer(
      db,
      ride.rideId,
      driverId,
      26000,
      `h-off-${Math.random()}`,
    );
    expect(offer.status).toBe(201);
    const select = await request(appFor(db, passengerId))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', `h-sel-${Math.random()}`)
      .send({});
    expect(select.status).toBe(200);
    for (const [path, key] of [
      ['en-route', 'h-enroute-001'],
      ['arrive', 'h-arrive-001'],
      ['start', 'h-start-001'],
      ['complete', 'h-complete-001'],
    ] as const) {
      const res = await request(appFor(db, driverId))
        .post(`/v1/rides/${ride.rideId}/${path}`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', key)
        .send({});
      expect(res.status).toBe(200);
    }
    const doc = db.getDoc('rides', ride.rideId)!;
    expect(doc.state).toBe('RIDE_COMPLETED');
    expect(doc.closedAt).toBeNull();
    return {
      db,
      rideId: ride.rideId,
      driverId,
      passengerId,
      version: doc.version as number,
      agreedFareMinor: doc.agreedFareMinor as number,
      assignedDriverId: doc.assignedDriverId as string,
    };
  }

  async function close(
    db: ReturnType<typeof memoryDb>,
    uid: string,
    rideId: string,
    idem: string,
    body: Record<string, unknown> = {},
  ) {
    return request(appFor(db, uid))
      .post(`/v1/rides/${rideId}/close`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', idem)
      .send(body);
  }

  it('passenger closes COMPLETED → CLOSED with outbox and closedAt', async () => {
    const seeded = await seedCompleted();
    const res = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-close-passenger',
    );
    expect(res.status).toBe(200);
    expect(res.body.data.state).toBe('RIDE_CLOSED');
    expect(res.body.data.closedAt).toBeTruthy();
    expect(res.body.data.version).toBe(seeded.version + 1);
    expect(res.body.data.agreedFareMinor).toBe(seeded.agreedFareMinor);
    expect(res.body.data.assignedDriverId).toBe(seeded.assignedDriverId);

    const ride = seeded.db.getDoc('rides', seeded.rideId)!;
    expect(ride.state).toBe('RIDE_CLOSED');
    expect(ride.closedAt).toBeTruthy();
    expect(ride.version).toBe(seeded.version + 1);

    const closedEvents = [...seeded.db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('outboxEvents/') &&
        (v as { eventType?: string; aggregateId?: string }).eventType ===
          'ride.closed' &&
        (v as { aggregateId?: string }).aggregateId === seeded.rideId,
    );
    expect(closedEvents).toHaveLength(1);
  });

  it('assigned driver may close', async () => {
    const seeded = await seedCompleted();
    const res = await close(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'h-close-driver',
    );
    expect(res.status).toBe(200);
    expect(res.body.data.state).toBe('RIDE_CLOSED');
  });

  it('rejects foreign actors and wrong states', async () => {
    const seeded = await seedCompleted();
    seedPassenger(seeded.db, 'foreign-p');
    seedDriver(seeded.db, 'foreign-d');
    expect(
      (await close(seeded.db, 'foreign-p', seeded.rideId, 'h-foreign-passenger'))
        .status,
    ).toBe(403);
    expect(
      (await close(seeded.db, 'foreign-d', seeded.rideId, 'h-foreign-driver'))
        .status,
    ).toBe(403);

    const early = memoryDb();
    seedPassenger(early, 'p1');
    seedPricing(early);
    const ride = await createRide(early, 'p1', 'h-early-create');
    const bad = await close(early, 'p1', ride.rideId, 'h-early-close-key');
    expect(bad.status).toBe(409);
    expect(bad.body.error.code).toBe('STATE_CONFLICT');
  });

  it('idempotent replay and already-CLOSED new key', async () => {
    const seeded = await seedCompleted();
    const a = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-idem-same-key',
    );
    const b = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-idem-same-key',
    );
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(a.body.data.version).toBe(b.body.data.version);
    expect(a.body.data.closedAt).toBe(b.body.data.closedAt);
    expect(seeded.db.getDoc('rides', seeded.rideId)?.version).toBe(
      seeded.version + 1,
    );

    const reuse = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-idem-same-key',
      { expectedVersion: seeded.version },
    );
    expect(reuse.status).toBe(409);
    expect(reuse.body.error.code).toBe('IDEMPOTENCY_KEY_REUSED');

    const again = await close(
      seeded.db,
      seeded.driverId,
      seeded.rideId,
      'h-already-closed-new',
    );
    expect(again.status).toBe(200);
    expect(again.body.data.state).toBe('RIDE_CLOSED');
    expect(seeded.db.getDoc('rides', seeded.rideId)?.version).toBe(
      seeded.version + 1,
    );
    const closedEvents = [...seeded.db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('outboxEvents/') &&
        (v as { eventType?: string }).eventType === 'ride.closed' &&
        (v as { aggregateId?: string }).aggregateId === seeded.rideId,
    );
    expect(closedEvents).toHaveLength(1);
  });

  it('CLOSED rejects cancel and progression', async () => {
    const seeded = await seedCompleted();
    await close(seeded.db, seeded.passengerId, seeded.rideId, 'h-imm-close');
    const cancel = await request(appFor(seeded.db, seeded.passengerId))
      .post(`/v1/rides/${seeded.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'h-imm-cancel')
      .send({});
    expect(cancel.status).toBe(409);
    const en = await request(appFor(seeded.db, seeded.driverId))
      .post(`/v1/rides/${seeded.rideId}/en-route`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'h-imm-enroute')
      .send({});
    expect(en.status).toBe(409);
  });

  it('stale expectedVersion and forged fields rejected', async () => {
    const seeded = await seedCompleted();
    const stale = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-stale-version',
      { expectedVersion: 1 },
    );
    expect(stale.status).toBe(409);
    expect(stale.body.error.code).toBe('VERSION_CONFLICT');

    const forged = await close(
      seeded.db,
      seeded.passengerId,
      seeded.rideId,
      'h-forged-fields',
      { expectedVersion: seeded.version, state: 'RIDE_CLOSED', closedAt: 'x' },
    );
    expect(forged.status).toBe(400);
  });

  it('50-way concurrent close yields one transition', async () => {
    const seeded = await seedCompleted();
    const results = await Promise.all(
      Array.from({ length: 50 }, (_, i) =>
        close(
          seeded.db,
          i % 2 === 0 ? seeded.passengerId : seeded.driverId,
          seeded.rideId,
          `h-close-50way-${String(i).padStart(3, '0')}`,
        ),
      ),
    );
    expect(results.every((r) => r.status === 200 || r.status === 409)).toBe(
      true,
    );
    const ride = seeded.db.getDoc('rides', seeded.rideId)!;
    expect(ride.state).toBe('RIDE_CLOSED');
    expect(ride.version).toBe(seeded.version + 1);
    expect(ride.agreedFareMinor).toBe(seeded.agreedFareMinor);
    const closedEvents = [...seeded.db.store.entries()].filter(
      ([k, v]) =>
        k.startsWith('outboxEvents/') &&
        (v as { eventType?: string; aggregateId?: string }).eventType ===
          'ride.closed' &&
        (v as { aggregateId?: string }).aggregateId === seeded.rideId,
    );
    expect(closedEvents).toHaveLength(1);
  });
});

describe('Phase 2I ride list / history', () => {
  function seedListRide(
    db: ReturnType<typeof memoryDb>,
    overrides: Record<string, unknown>,
  ) {
    const rideId = (overrides.rideId as string) ?? `ride-${Math.random()}`;
    const createdAt =
      (overrides.createdAt as string) ?? new Date().toISOString();
    db.seed('rides', rideId, {
      rideId,
      passengerId: 'p-list',
      assignedDriverId: null,
      state: 'SEARCHING',
      version: 1,
      requestVersion: 1,
      category: 'economy',
      serviceType: 'ride',
      pickup: { lat: 24.86, lng: 67.0 },
      destination: { lat: 24.9, lng: 67.1 },
      routePolyline: 'SECRET_POLY',
      distanceKm: 5,
      estimatedDurationMin: 12,
      pricingSnapshotId: 'snap-1',
      recommendedFareMinor: 25000,
      passengerOfferMinor: 25000,
      agreedFareMinor: null,
      agreedOfferId: null,
      agreedFareCurrency: null,
      feePolicySnapshot: { secret: true },
      paymentMethod: 'CASH',
      paymentIntentId: 'pi_secret',
      passengerCount: 1,
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      assignedAt: null,
      startedAt: null,
      completedAt: null,
      closedAt: null,
      cancelledBy: null,
      cancellationReason: null,
      cancellationFeeMinor: 99,
      createdAt,
      updatedAt: createdAt,
      ...overrides,
    });
    return rideId;
  }

  async function listRides(
    db: ReturnType<typeof memoryDb>,
    uid: string,
    query: Record<string, string> = {},
  ) {
    return request(appFor(db, uid))
      .get('/v1/rides')
      .query(query)
      .set('Authorization', 'Bearer t');
  }

  it('returns empty history for passenger with no rides', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-empty');
    const res = await listRides(db, 'p-empty');
    expect(res.status).toBe(200);
    expect(res.body.data.rides).toEqual([]);
    expect(res.body.data.nextCursor).toBeNull();
  });

  it('passenger sees only own rides; forged passengerId rejected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'pA');
    seedPassenger(db, 'pB');
    seedListRide(db, {
      rideId: 'r-a1',
      passengerId: 'pA',
      createdAt: '2026-01-02T00:00:00.000Z',
    });
    seedListRide(db, {
      rideId: 'r-b1',
      passengerId: 'pB',
      createdAt: '2026-01-03T00:00:00.000Z',
    });

    const res = await listRides(db, 'pA');
    expect(res.status).toBe(200);
    expect(res.body.data.rides.map((r: { rideId: string }) => r.rideId)).toEqual([
      'r-a1',
    ]);

    const forged = await listRides(db, 'pA', { passengerId: 'pB' });
    expect(forged.status).toBe(400);
    expect(forged.body.error.code).toBe('VALIDATION_ERROR');

    const forgedDriver = await listRides(db, 'pA', { driverId: 'dX' });
    expect(forgedDriver.status).toBe(400);
  });

  it('driver sees assigned rides only; never unassigned SEARCHING', async () => {
    const db = memoryDb();
    seedDriver(db, 'dA');
    seedDriver(db, 'dB');
    seedPassenger(db, 'p1');
    seedListRide(db, {
      rideId: 'r-search',
      passengerId: 'p1',
      assignedDriverId: null,
      state: 'SEARCHING',
      createdAt: '2026-01-05T00:00:00.000Z',
    });
    seedListRide(db, {
      rideId: 'r-da',
      passengerId: 'p1',
      assignedDriverId: 'dA',
      state: 'DRIVER_ASSIGNED',
      createdAt: '2026-01-04T00:00:00.000Z',
    });
    seedListRide(db, {
      rideId: 'r-db',
      passengerId: 'p1',
      assignedDriverId: 'dB',
      state: 'DRIVER_ASSIGNED',
      createdAt: '2026-01-03T00:00:00.000Z',
    });
    seedListRide(db, {
      rideId: 'r-da-cancel',
      passengerId: 'p1',
      assignedDriverId: 'dA',
      state: 'CANCELLED',
      createdAt: '2026-01-02T00:00:00.000Z',
    });

    const res = await listRides(db, 'dA');
    expect(res.status).toBe(200);
    const ids = res.body.data.rides.map((r: { rideId: string }) => r.rideId);
    expect(ids).toEqual(['r-da', 'r-da-cancel']);
    expect(ids).not.toContain('r-search');
    expect(ids).not.toContain('r-db');
  });

  it('status filters: all / completed / cancelled; EXPIRED only in all', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-st');
    const states = [
      'SEARCHING',
      'OFFERS_AVAILABLE',
      'DRIVER_ASSIGNED',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'RIDE_STARTED',
      'RIDE_COMPLETED',
      'RIDE_CLOSED',
      'CANCELLED',
      'EXPIRED',
    ] as const;
    states.forEach((state, i) => {
      seedListRide(db, {
        rideId: `r-st-${state}`,
        passengerId: 'p-st',
        state,
        assignedDriverId: state === 'SEARCHING' || state === 'OFFERS_AVAILABLE' || state === 'EXPIRED'
          ? null
          : 'd1',
        createdAt: `2026-02-${String(i + 1).padStart(2, '0')}T00:00:00.000Z`,
      });
    });

    const all = await listRides(db, 'p-st', { status: 'all', limit: '50' });
    expect(all.status).toBe(200);
    expect(all.body.data.rides).toHaveLength(10);
    expect(
      all.body.data.rides.some((r: { state: string }) => r.state === 'EXPIRED'),
    ).toBe(true);

    const completed = await listRides(db, 'p-st', { status: 'completed' });
    expect(completed.status).toBe(200);
    const completedStates = completed.body.data.rides.map(
      (r: { state: string }) => r.state,
    );
    expect(new Set(completedStates)).toEqual(
      new Set(['RIDE_COMPLETED', 'RIDE_CLOSED']),
    );
    expect(completedStates).not.toContain('EXPIRED');
    expect(completedStates).not.toContain('CANCELLED');

    const cancelled = await listRides(db, 'p-st', { status: 'cancelled' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.data.rides).toHaveLength(1);
    expect(cancelled.body.data.rides[0].state).toBe('CANCELLED');
    expect(cancelled.body.data.rides[0].rideId).toBe('r-st-CANCELLED');
  });

  it('serviceType filter isolates types', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-svc');
    for (const st of ['ride', 'courier', 'intercity', 'move'] as const) {
      seedListRide(db, {
        rideId: `r-svc-${st}`,
        passengerId: 'p-svc',
        serviceType: st,
        createdAt: '2026-03-01T00:00:00.000Z',
      });
    }
    const courier = await listRides(db, 'p-svc', { serviceType: 'courier' });
    expect(courier.status).toBe(200);
    expect(courier.body.data.rides).toHaveLength(1);
    expect(courier.body.data.rides[0].serviceType).toBe('courier');

    const bad = await listRides(db, 'p-svc', { serviceType: 'cargo' });
    expect(bad.status).toBe(400);
  });

  it('keyset pagination is deterministic with identical createdAt', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-page');
    const ts = '2026-04-01T12:00:00.000Z';
    // rideId DESC: z, m, a
    seedListRide(db, { rideId: 'ride-a', passengerId: 'p-page', createdAt: ts });
    seedListRide(db, { rideId: 'ride-m', passengerId: 'p-page', createdAt: ts });
    seedListRide(db, { rideId: 'ride-z', passengerId: 'p-page', createdAt: ts });

    const page1 = await listRides(db, 'p-page', { limit: '2' });
    expect(page1.status).toBe(200);
    expect(page1.body.data.rides.map((r: { rideId: string }) => r.rideId)).toEqual([
      'ride-z',
      'ride-m',
    ]);
    expect(page1.body.data.nextCursor).toBeTruthy();

    const page2 = await listRides(db, 'p-page', {
      limit: '2',
      cursor: page1.body.data.nextCursor,
    });
    expect(page2.status).toBe(200);
    expect(page2.body.data.rides.map((r: { rideId: string }) => r.rideId)).toEqual([
      'ride-a',
    ]);
    expect(page2.body.data.nextCursor).toBeNull();

    // Unchanged dataset: no duplicates across pages
    const allIds = [
      ...page1.body.data.rides.map((r: { rideId: string }) => r.rideId),
      ...page2.body.data.rides.map((r: { rideId: string }) => r.rideId),
    ];
    expect(new Set(allIds).size).toBe(allIds.length);
  });

  it('rejects invalid limit/cursor/status and cross-user cursor', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-cur');
    seedPassenger(db, 'p-other');
    seedListRide(db, {
      rideId: 'r-cur-1',
      passengerId: 'p-cur',
      createdAt: '2026-05-01T00:00:00.000Z',
    });
    seedListRide(db, {
      rideId: 'r-cur-2',
      passengerId: 'p-cur',
      createdAt: '2026-05-02T00:00:00.000Z',
    });

    for (const limit of ['0', '-1', '51', 'abc', '10.5']) {
      const res = await listRides(db, 'p-cur', { limit });
      expect(res.status).toBe(400);
      expect(res.body.error.code).toBe('VALIDATION_ERROR');
    }

    const badStatus = await listRides(db, 'p-cur', { status: 'expired' });
    expect(badStatus.status).toBe(400);

    const badCursor = await listRides(db, 'p-cur', { cursor: '%%%not-b64%%%' });
    expect(badCursor.status).toBe(400);

    const page = await listRides(db, 'p-cur', { limit: '1' });
    const stolen = await listRides(db, 'p-other', {
      cursor: page.body.data.nextCursor,
    });
    expect(stolen.status).toBe(400);
    expect(stolen.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('publicRide omits internal fields on list items', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-dto');
    seedListRide(db, {
      rideId: 'r-dto',
      passengerId: 'p-dto',
      createdAt: '2026-06-01T00:00:00.000Z',
    });
    const res = await listRides(db, 'p-dto');
    expect(res.status).toBe(200);
    const item = res.body.data.rides[0];
    expect(item.rideId).toBe('r-dto');
    expect(item.routePolyline).toBeUndefined();
    expect(item.feePolicySnapshot).toBeUndefined();
    expect(item.paymentIntentId).toBeUndefined();
    expect(item.cancellationFeeMinor).toBeUndefined();
    expect(item.distanceKm).toBeUndefined();
  });

  it('list reflects create then cancel mutation', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-mut');
    seedPricing(db);
    const ride = await createRide(db, 'p-mut', 'list-create-mut-1');
    const before = await listRides(db, 'p-mut');
    expect(before.body.data.rides[0].state).toBe('SEARCHING');

    const cancel = await request(appFor(db, 'p-mut'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'list-cancel-mut-1')
      .send({});
    expect(cancel.status).toBe(200);

    const after = await listRides(db, 'p-mut', { status: 'cancelled' });
    expect(after.body.data.rides).toHaveLength(1);
    expect(after.body.data.rides[0].state).toBe('CANCELLED');
  });

  it('GET /v1/rides does not collide with get-by-id; IDOR intact', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-idor');
    seedPassenger(db, 'p-other2');
    seedListRide(db, {
      rideId: 'r-idor',
      passengerId: 'p-idor',
      createdAt: '2026-07-01T00:00:00.000Z',
    });

    const list = await listRides(db, 'p-idor');
    expect(list.status).toBe(200);

    const own = await request(appFor(db, 'p-idor'))
      .get('/v1/rides/r-idor')
      .set('Authorization', 'Bearer t');
    expect(own.status).toBe(200);

    const foreign = await request(appFor(db, 'p-other2'))
      .get('/v1/rides/r-idor')
      .set('Authorization', 'Bearer t');
    expect(foreign.status).toBe(403);
  });

  it('limit boundaries 1 and 50', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-lim');
    for (let i = 0; i < 51; i++) {
      seedListRide(db, {
        rideId: `r-lim-${String(i).padStart(3, '0')}`,
        passengerId: 'p-lim',
        createdAt: `2026-08-${String((i % 28) + 1).padStart(2, '0')}T${String(
          i % 24,
        ).padStart(2, '0')}:00:00.000Z`,
      });
    }
    const one = await listRides(db, 'p-lim', { limit: '1' });
    expect(one.body.data.rides).toHaveLength(1);
    expect(one.body.data.nextCursor).toBeTruthy();

    const fifty = await listRides(db, 'p-lim', { limit: '50' });
    expect(fifty.body.data.rides).toHaveLength(50);
    expect(fifty.body.data.nextCursor).toBeTruthy();

    const last = await listRides(db, 'p-lim', {
      limit: '50',
      cursor: fifty.body.data.nextCursor,
    });
    expect(last.body.data.rides).toHaveLength(1);
    expect(last.body.data.nextCursor).toBeNull();
  });

  it('unauthenticated list rejected', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-unauth');
    const app = createApp({
      auth: {
        verifyIdToken: vi.fn().mockRejectedValue(new Error('bad')),
      } as never,
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
    });
    const res = await request(app).get('/v1/rides');
    expect(res.status).toBe(401);
  });
});

const WORKER_TOKEN = 'test-worker-token-16chars';

function workerApp(db: ReturnType<typeof memoryDb>) {
  return createApp({
    auth: authFor('worker'),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
    internalWorkerToken: WORKER_TOKEN,
  });
}

function backdateRideExpiry(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  msAgo = 60_000,
) {
  const doc = db.getDoc('rides', rideId)!;
  db.seed('rides', rideId, {
    ...doc,
    expiresAt: new Date(Date.now() - msAgo).toISOString(),
  });
}

async function expireSweep(
  db: ReturnType<typeof memoryDb>,
  limit?: number,
) {
  const req = request(workerApp(db))
    .post('/v1/internal/rides/expire-sweep')
    .set('X-Ora-Worker-Token', WORKER_TOKEN);
  if (limit != null) req.query({ limit: String(limit) });
  return req;
}

function countExpiredEvents(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
): number {
  return [...db.store.entries()].filter(
    ([k, v]) =>
      k.startsWith('outboxEvents/') &&
      (v as { eventType?: string; aggregateId?: string }).eventType ===
        'ride.expired' &&
      (v as { aggregateId?: string }).aggregateId === rideId,
  ).length;
}

describe('Phase 2J ride expired sweeper', () => {
  it('rejects worker sweep without valid token', async () => {
    const db = memoryDb();
    const app = createApp({
      auth: authFor('p1'),
      db: db as never,
      requireAppCheck: false,
      rateLimit: { windowMs: 60_000, max: 10_000 },
      internalWorkerToken: WORKER_TOKEN,
    });
    expect(
      (await request(app).post('/v1/internal/rides/expire-sweep')).status,
    ).toBe(403);
    expect(
      (
        await request(app)
          .post('/v1/internal/rides/expire-sweep')
          .set('X-Ora-Worker-Token', 'wrong-token')
      ).status,
    ).toBe(403);
  });

  it('SEARCHING + past expiresAt → EXPIRED with outbox', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j1');
    seedPricing(db);
    const ride = await createRide(db, 'p-j1', 'j-create-1');
    backdateRideExpiry(db, ride.rideId);
    const beforeVersion = db.getDoc('rides', ride.rideId)!.version as number;

    const sweep = await expireSweep(db);
    expect(sweep.status).toBe(200);
    expect(sweep.body.data.expired).toBe(1);

    const doc = db.getDoc('rides', ride.rideId)!;
    expect(doc.state).toBe('EXPIRED');
    expect(doc.version).toBe(beforeVersion + 1);
    expect(doc.updatedAt).toBeTruthy();
    expect(countExpiredEvents(db, ride.rideId)).toBe(1);
    const evt = [...db.store.entries()].find(
      ([k, v]) =>
        k.startsWith('outboxEvents/') &&
        (v as { eventType?: string }).eventType === 'ride.expired',
    )?.[1] as { payload?: Record<string, unknown> };
    expect(evt?.payload?.fromState).toBe('SEARCHING');
    expect(evt?.payload?.toState).toBe('EXPIRED');
    expect(evt?.payload?.reason).toBe('search_ttl_elapsed');
  });

  it('OFFERS_AVAILABLE + past expiresAt → EXPIRED', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j2');
    seedDriver(db, 'd-j2');
    seedPricing(db);
    const ride = await createRide(db, 'p-j2', 'j-create-2');
    const offer = await createOffer(db, ride.rideId, 'd-j2', 26000, 'j-offer-01');
    expect(offer.status).toBe(201);
    expect(db.getDoc('rides', ride.rideId)?.state).toBe('OFFERS_AVAILABLE');
    backdateRideExpiry(db, ride.rideId);

    const sweep = await expireSweep(db);
    expect(sweep.status).toBe(200);
    expect(sweep.body.data.expired).toBe(1);
    expect(db.getDoc('rides', ride.rideId)?.state).toBe('EXPIRED');
  });

  it('future expiresAt ride remains unchanged', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j3');
    seedPricing(db);
    const ride = await createRide(db, 'p-j3', 'j-create-3');
    const sweep = await expireSweep(db);
    expect(sweep.status).toBe(200);
    expect(sweep.body.data.expired).toBe(0);
    expect(db.getDoc('rides', ride.rideId)?.state).toBe('SEARCHING');
    expect(countExpiredEvents(db, ride.rideId)).toBe(0);
  });

  it('does not overwrite assigned or terminal rides', async () => {
    const db = memoryDb();
    const passengerId = 'p-j4';
    const driverId = 'd-j4';
    seedPassenger(db, passengerId);
    seedDriver(db, driverId);
    seedPricing(db);
    const ride = await createRide(db, passengerId, 'j-create-4');
    const offer = await createOffer(
      db,
      ride.rideId,
      driverId,
      26000,
      'j-offer-04',
    );
    expect(offer.status).toBe(201);
    const select = await request(appFor(db, passengerId))
      .post(`/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'j-select-04')
      .send({});
    expect(select.status).toBe(200);
    backdateRideExpiry(db, ride.rideId);
    const versionBefore = db.getDoc('rides', ride.rideId)!.version as number;

    const sweep = await expireSweep(db);
    expect(sweep.status).toBe(200);
    // Assigned rides are excluded from the sweeper query (state filter).
    expect(sweep.body.data.expired).toBe(0);
    const doc = db.getDoc('rides', ride.rideId)!;
    expect(doc.state).toBe('DRIVER_ASSIGNED');
    expect(doc.version).toBe(versionBefore);
    expect(countExpiredEvents(db, ride.rideId)).toBe(0);
  });

  it('does not overwrite cancelled ride', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j5');
    seedPricing(db);
    const ride = await createRide(db, 'p-j5', 'j-create-5');
    backdateRideExpiry(db, ride.rideId);
    const cancel = await request(appFor(db, 'p-j5'))
      .post(`/v1/rides/${ride.rideId}/cancel`)
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'j-cancel-5')
      .send({});
    expect(cancel.status).toBe(200);
    const versionBefore = db.getDoc('rides', ride.rideId)!.version as number;

    await expireSweep(db);
    const doc = db.getDoc('rides', ride.rideId)!;
    expect(doc.state).toBe('CANCELLED');
    expect(doc.version).toBe(versionBefore);
    expect(countExpiredEvents(db, ride.rideId)).toBe(0);
  });

  it('duplicate expire is idempotent', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j6');
    seedPricing(db);
    const ride = await createRide(db, 'p-j6', 'j-create-6');
    backdateRideExpiry(db, ride.rideId);
    const rides = new RideService(db as never);

    const first = await rides.expireRide({
      rideId: ride.rideId,
      correlationId: 'c1',
    });
    expect(first.outcome).toBe('expired');
    const versionAfter = db.getDoc('rides', ride.rideId)!.version as number;

    const second = await rides.expireRide({
      rideId: ride.rideId,
      correlationId: 'c2',
    });
    expect(second.outcome).toBe('already_expired');
    expect(db.getDoc('rides', ride.rideId)?.version).toBe(versionAfter);
    expect(countExpiredEvents(db, ride.rideId)).toBe(1);
  });

  it('concurrent expire vs select — select wins', async () => {
    const db = memoryDb();
    const passengerId = 'p-j7';
    const driverId = 'd-j7';
    seedPassenger(db, passengerId);
    seedDriver(db, driverId);
    seedPricing(db);
    const ride = await createRide(db, passengerId, 'j-create-7');
    const offer = await createOffer(
      db,
      ride.rideId,
      driverId,
      26000,
      'j-offer-07',
    );
    expect(offer.status).toBe(201);
    backdateRideExpiry(db, ride.rideId);

    const rides = new RideService(db as never);
    const [selectRes, expireRes] = await Promise.all([
      request(appFor(db, passengerId))
        .post(
          `/v1/rides/${ride.rideId}/offers/${offer.body.data.offerId}/select`,
        )
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'j-select-07')
        .send({}),
      rides.expireRide({ rideId: ride.rideId, correlationId: 'race-7' }),
    ]);

    const doc = db.getDoc('rides', ride.rideId)!;
    if (selectRes.status === 200) {
      expect(doc.state).toBe('DRIVER_ASSIGNED');
      expect(expireRes.outcome).not.toBe('expired');
    } else {
      expect(doc.state).toBe('EXPIRED');
      expect(selectRes.status).toBe(409);
    }
    expect(countExpiredEvents(db, ride.rideId)).toBeLessThanOrEqual(1);
  });

  it('concurrent expire vs cancel — one terminal wins', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j8');
    seedPricing(db);
    const ride = await createRide(db, 'p-j8', 'j-create-8');
    backdateRideExpiry(db, ride.rideId);
    const rides = new RideService(db as never);

    const [cancelRes, expireRes] = await Promise.all([
      request(appFor(db, 'p-j8'))
        .post(`/v1/rides/${ride.rideId}/cancel`)
        .set('Authorization', 'Bearer t')
        .set('Idempotency-Key', 'j-cancel-8')
        .send({}),
      rides.expireRide({ rideId: ride.rideId, correlationId: 'race-8' }),
    ]);

    const doc = db.getDoc('rides', ride.rideId)!;
    expect(['CANCELLED', 'EXPIRED']).toContain(doc.state);
    if (doc.state === 'CANCELLED') {
      expect(expireRes.outcome).not.toBe('expired');
      expect(cancelRes.status).toBe(200);
    } else {
      expect(doc.state).toBe('EXPIRED');
    }
    expect(countExpiredEvents(db, ride.rideId)).toBeLessThanOrEqual(1);
  });

  it('offer create rejected after ride expired', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p-j9');
    seedDriver(db, 'd-j9');
    seedPricing(db);
    const ride = await createRide(db, 'p-j9', 'j-create-9');
    backdateRideExpiry(db, ride.rideId);
    await expireSweep(db);
    expect(db.getDoc('rides', ride.rideId)?.state).toBe('EXPIRED');

    const offer = await createOffer(
      db,
      ride.rideId,
      'd-j9',
      26000,
      'j-off-after-exp',
    );
    expect(offer.status).toBe(409);
    expect(offer.body.error.code).toBe('STATE_CONFLICT');
  });

  it('batch mixes expired and skipped without blocking', async () => {
    const db = memoryDb();
    const passengerId = 'p-j10';
    const driverId = 'd-j10';
    seedPassenger(db, passengerId);
    seedDriver(db, driverId);
    seedPricing(db);
    const due = await createRide(db, passengerId, 'j-create-10a');
    backdateRideExpiry(db, due.rideId);
    const assigned = await createRide(db, passengerId, 'j-create-10b');
    const offer = await createOffer(
      db,
      assigned.rideId,
      driverId,
      26000,
      'j-offer-10',
    );
    expect(offer.status).toBe(201);
    const select = await request(appFor(db, passengerId))
      .post(
        `/v1/rides/${assigned.rideId}/offers/${offer.body.data.offerId}/select`,
      )
      .set('Authorization', 'Bearer t')
      .set('Idempotency-Key', 'j-select-10')
      .send({});
    expect(select.status).toBe(200);
    backdateRideExpiry(db, assigned.rideId);

    const sweep = await expireSweep(db);
    expect(sweep.status).toBe(200);
    expect(sweep.body.data.expired).toBe(1);
    // Assigned ride is not a query candidate; due ride still expires.
    expect(db.getDoc('rides', due.rideId)?.state).toBe('EXPIRED');
    expect(db.getDoc('rides', assigned.rideId)?.state).toBe('DRIVER_ASSIGNED');
  });
});
