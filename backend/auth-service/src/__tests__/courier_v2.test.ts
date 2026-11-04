import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';
import type { RideDoc } from '../rides/types';

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
};

const P = { lat: 24.86, lng: 67.0, address: 'Pickup A' };
const M = { lat: 24.88, lng: 67.05, address: 'Mid' };
const D = { lat: 24.9, lng: 67.1, address: 'Drop B' };

const v2CreateBody = {
  pickup: P,
  destination: D,
  city: 'Karachi',
  category: 'courier_bike',
  serviceType: 'courier',
  passengerOfferMinor: 30000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  parcel,
  stops: [
    { type: 'PICKUP', location: P, label: 'Home' },
    { type: 'PICKUP', location: M, label: 'Office' },
    { type: 'DROPOFF', location: D, label: 'Client' },
  ],
};

const bdCreateBody = {
  pickup: P,
  destination: D,
  city: 'Karachi',
  category: 'courier_bike',
  serviceType: 'buy_deliver',
  passengerOfferMinor: 30000,
  pricingSnapshotId: 'snap-1',
  paymentMethod: 'CASH',
  stops: [
    {
      type: 'SHOP',
      location: P,
      label: 'Pharmacy',
      items: [
        { name: 'Panadol', qty: 2, note: '500mg' },
        { name: 'ORS sachets', qty: 4 },
      ],
    },
    { type: 'DROPOFF', location: D, label: 'Home' },
  ],
  shopping: { totalBudgetMinor: 200000, attestationAccepted: true },
};

function post(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  path: string,
  body: Record<string, unknown>,
  idem: string,
) {
  return request(appFor(db, uid))
    .post(path)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem.length < 8 ? idem.padEnd(8, 'x') : idem)
    .send(body);
}

function driverPost(
  db: ReturnType<typeof memoryDb>,
  driverId: string,
  rideId: string,
  path: string,
  body: Record<string, unknown>,
  idem: string,
) {
  return post(db, driverId, `/v1/rides/${rideId}${path}`, body, idem);
}

async function createRide(
  db: ReturnType<typeof memoryDb>,
  passengerId: string,
  body: Record<string, unknown>,
  idem: string,
) {
  const res = await post(db, passengerId, '/v1/rides', body, idem);
  expect(res.status).toBe(201);
  return res.body.data as { rideId: string; version: number; state: string };
}

async function assignRide(
  db: ReturnType<typeof memoryDb>,
  rideId: string,
  passengerId: string,
  driverId: string,
  idemPrefix: string,
) {
  const offer = await driverPost(db, driverId, rideId, '/offers', {
    type: 'DRIVER_COUNTEROFFER',
    amountMinor: 32000,
    expectedRequestVersion: 1,
  }, `${idemPrefix}-offer`);
  expect(offer.status).toBe(201);
  const sel = await post(
    db,
    passengerId,
    `/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`,
    { expectedVersion: 2 },
    `${idemPrefix}-select`,
  );
  expect(sel.status).toBe(200);
}

function doc(db: ReturnType<typeof memoryDb>, rideId: string): RideDoc {
  return db.getDoc('rides', rideId) as unknown as RideDoc;
}

describe('courier v2 create validation', () => {
  it('creates a v2 multi-stop courier booking (protocol 2, no OTP later)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', v2CreateBody, 'v2-create-1');
    const d = doc(db, r.rideId);
    expect(d.courierProtocolVersion).toBe(2);
    expect(d.stops).toHaveLength(3);
    expect(d.stops![0].status).toBe('PENDING');
    expect(d.currentStopIndex).toBe(0);
    expect(d.settlement?.status).toBe('PENDING');
  });

  it('rejects stops on normal rides', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      pickup: P,
      destination: D,
      city: 'Karachi',
      category: 'bike',
      serviceType: 'ride',
      passengerOfferMinor: 30000,
      pricingSnapshotId: 'snap-1',
      paymentMethod: 'CASH',
      stops: v2CreateBody.stops,
    }, 'v2-stops-ride');
    expect(res.status).toBe(400);
  });

  it('rejects stops mismatched with pickup/destination', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...v2CreateBody,
      stops: [
        { type: 'PICKUP', location: M },
        { type: 'DROPOFF', location: D },
      ],
    }, 'v2-stops-mismatch');
    expect(res.status).toBe(400);
  });

  it('rejects last stop that is not a DROPOFF', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...v2CreateBody,
      stops: [
        { type: 'PICKUP', location: P },
        { type: 'PICKUP', location: D },
      ],
    }, 'v2-last-dropoff');
    expect(res.status).toBe(400);
  });

  it('rejects >5 stops (default cap)', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const stops = [P, M, { lat: 24.87, lng: 67.02 }, { lat: 24.89, lng: 67.07 }, { lat: 24.91, lng: 67.12 }, D].map((l, i) => ({
      type: i === 5 ? 'DROPOFF' : 'PICKUP',
      location: l,
    }));
    const res = await post(db, 'p1', '/v1/rides', {
      ...v2CreateBody,
      destination: D,
      stops,
    }, 'v2-too-many');
    expect(res.status).toBe(400);
  });
});

describe('buy_deliver create validation', () => {
  it('creates a B&D booking with shop items + budget', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', bdCreateBody, 'bd-create-1');
    const d = doc(db, r.rideId);
    expect(d.serviceType).toBe('buy_deliver');
    expect(d.shopping?.totalBudgetMinor).toBe(200000);
    expect(d.shopping?.paymentArrangement).toBe('RIDER_CASH');
    expect(d.stops![0].items).toHaveLength(2);
  });

  it('rejects B&D without shopping block', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      shopping: undefined,
    }, 'bd-no-shopping');
    expect(res.status).toBe(400);
  });

  it('rejects B&D without stops', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      stops: undefined,
    }, 'bd-no-stops');
    expect(res.status).toBe(400);
  });

  it('rejects budget above the Rs 3,000 cap', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      shopping: { totalBudgetMinor: 300001, attestationAccepted: true },
    }, 'bd-over-cap');
    expect(res.status).toBe(400);
  });

  it('rejects B&D without a SHOP stop', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      stops: [
        { type: 'PICKUP', location: P },
        { type: 'DROPOFF', location: D },
      ],
    }, 'bd-no-shop');
    expect(res.status).toBe(400);
  });

  it('rejects prohibited items at booking', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      stops: [
        {
          type: 'SHOP',
          location: P,
          items: [{ name: 'Tramadol 100mg', qty: 1 }],
        },
        { type: 'DROPOFF', location: D },
      ],
    }, 'bd-prohibited');
    expect(res.status).toBe(400);
    expect(JSON.stringify(res.body)).toContain('not permitted');
  });

  it('rejects B&D when attestation not accepted', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      shopping: { totalBudgetMinor: 100000, attestationAccepted: false },
    }, 'bd-no-attest');
    expect(res.status).toBe(400);
  });

  it('B&D single-shop — origin is the FIRST SHOP stop, no separate ' +
      'PICKUP waypoint persisted', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', bdCreateBody, 'bd-single-shop');
    const d = doc(db, r.rideId);
    // Legacy pickup field derives from the first SHOP's location.
    expect(d.pickup.lat).toBe(P.lat);
    expect(d.pickup.lng).toBe(P.lng);
    expect(d.stops).toHaveLength(2);
    expect(d.stops![0].type).toBe('SHOP');
    expect(d.stops![1].type).toBe('DROPOFF');
    expect(d.stops!.some((s) => s.type === 'PICKUP')).toBe(false);
  });

  it('B&D multi-shop — both shops persist without duplicating the ' +
      'origin', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const r = await createRide(db, 'p1', {
      ...bdCreateBody,
      stops: [
        {
          type: 'SHOP',
          location: P,
          label: 'Pharmacy',
          items: [{ name: 'Panadol', qty: 2 }],
        },
        {
          type: 'SHOP',
          location: M,
          label: 'Supermarket',
          items: [{ name: 'Bread', qty: 1 }],
        },
        { type: 'DROPOFF', location: D, label: 'Home' },
      ],
    }, 'bd-multi-shop');
    const d = doc(db, r.rideId);
    expect(d.pickup.lat).toBe(P.lat);
    expect(d.destination.lat).toBe(D.lat);
    expect(d.stops).toHaveLength(3);
    expect(d.stops!.map((s) => s.type)).toEqual([
      'SHOP',
      'SHOP',
      'DROPOFF',
    ]);
  });

  it('rejects B&D beyond the five-stop cap', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedPricing(db);
    const shop = (loc: typeof P, label: string) => ({
      type: 'SHOP',
      location: loc,
      label,
      items: [{ name: 'Item', qty: 1 }],
    });
    const res = await post(db, 'p1', '/v1/rides', {
      ...bdCreateBody,
      stops: [
        shop(P, 'S1'),
        shop(M, 'S2'),
        shop(P, 'S3'),
        shop(M, 'S4'),
        shop(P, 'S5'),
        { type: 'DROPOFF', location: D },
      ],
    }, 'bd-over-cap');
    expect(res.status).toBe(400);
  });
});

describe('courier v2 multi-stop progression (code-free)', () => {
  async function v2Assigned(db: ReturnType<typeof memoryDb>) {
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', v2CreateBody, 'v2-prog-create');
    await assignRide(db, r.rideId, 'p1', 'd1', 'v2-prog');
    return r.rideId;
  }

  it('issues NO OTP on assignment for v2 bookings', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    const d = doc(db, rideId);
    expect(d.parcelOtp).toBeUndefined();
    expect(d.settlement?.deliveryFareMinor).toBe(32000);
    expect(d.settlement?.totalDueMinor).toBe(32000);
  });

  it('progresses stops → STARTED → COMPLETED without any code', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);

    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2-p-enroute');
    const a0 = await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'v2-p-a0');
    expect(a0.status).toBe(200);
    expect(doc(db, rideId).state).toBe('DRIVER_ARRIVED');

    const c0 = await driverPost(db, 'd1', rideId, '/stops/0/confirm', {}, 'v2-p-c0');
    expect(c0.status).toBe(200);
    let d = doc(db, rideId);
    expect(d.state).toBe('RIDE_STARTED'); // custody begins
    expect(d.currentStopIndex).toBe(1);
    expect(d.evidence?.confirms).toHaveLength(1);

    await driverPost(db, 'd1', rideId, '/stops/1/arrive', {}, 'v2-p-a1');
    await driverPost(db, 'd1', rideId, '/stops/1/confirm', {}, 'v2-p-c1');
    await driverPost(db, 'd1', rideId, '/stops/2/arrive', {}, 'v2-p-a2');
    const c2 = await driverPost(db, 'd1', rideId, '/stops/2/confirm', {}, 'v2-p-c2');
    expect(c2.status).toBe(200);
    d = doc(db, rideId);
    expect(d.state).toBe('RIDE_COMPLETED');
    expect(d.stops![2].status).toBe('DONE');
    expect(d.partialFulfillment).toBeFalsy();
  });

  it('start/complete endpoints still work for v2 (no OTP required)', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2s-enroute');
    await driverPost(db, 'd1', rideId, '/arrive', {}, 'v2s-arrive');
    const start = await driverPost(db, 'd1', rideId, '/start', {}, 'v2s-start');
    expect(start.status).toBe(200);
    const complete = await driverPost(db, 'd1', rideId, '/complete', {}, 'v2s-complete');
    expect(complete.status).toBe(200);
    expect(doc(db, rideId).state).toBe('RIDE_COMPLETED');
  });

  it('rejects confirm of a non-current stop', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2o-enroute');
    const res = await driverPost(db, 'd1', rideId, '/stops/1/confirm', {}, 'v2o-c1');
    expect(res.status).toBe(409);
  });

  it('blocks cancellation once parcel is in custody', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2c-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'v2c-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/confirm', {}, 'v2c-c0');
    const res = await post(db, 'p1', `/v1/rides/${rideId}/cancel`, {}, 'v2c-cancel');
    expect(res.status).toBe(409);
  });

  it('allows cancellation before pickup', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    const res = await post(db, 'p1', `/v1/rides/${rideId}/cancel`, { reason: 'changed mind' }, 'v2c2-cancel');
    expect(res.status).toBe(200);
    expect(doc(db, rideId).state).toBe('CANCELLED');
  });

  it('failed stop keeps itinerary moving; last-stop fail → DELIVERY_FAILED', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2f-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'v2f-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/confirm', {}, 'v2f-c0');
    await driverPost(db, 'd1', rideId, '/stops/1/arrive', {}, 'v2f-a1');
    const f1 = await driverPost(db, 'd1', rideId, '/stops/1/fail', { reason: 'SENDER_UNAVAILABLE' }, 'v2f-f1');
    expect(f1.status).toBe(200);
    expect(doc(db, rideId).currentStopIndex).toBe(2);
    expect(doc(db, rideId).partialFulfillment).toBe(true);
    await driverPost(db, 'd1', rideId, '/stops/2/arrive', {}, 'v2f-a2');
    const f2 = await driverPost(db, 'd1', rideId, '/stops/2/fail', { reason: 'RECEIVER_UNREACHABLE' }, 'v2f-f2');
    expect(f2.status).toBe(200);
    expect(doc(db, rideId).state).toBe('DELIVERY_FAILED');
  });

  it('non-custody DELIVERY_FAILED can be cancelled; retry reopens failed stop', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    // Fail first pickup without custody → DELIVERY_FAILED path after exhausting.
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2r-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'v2r-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/fail', { reason: 'SENDER_UNAVAILABLE' }, 'v2r-f0');
    await driverPost(db, 'd1', rideId, '/stops/1/fail', { reason: 'SENDER_UNAVAILABLE' }, 'v2r-f1');
    // Failing seq1 while seq0 failed: current is index1? After f0, currentStopIndex=1.
    const f2 = await driverPost(db, 'd1', rideId, '/stops/2/fail', { reason: 'ADDRESS_INCORRECT' }, 'v2r-f2');
    expect(f2.status).toBe(200);
    expect(doc(db, rideId).state).toBe('DELIVERY_FAILED');

    // No custody → passenger may cancel.
    const cancel = await post(db, 'p1', `/v1/rides/${rideId}/cancel`, {}, 'v2r-cancel');
    expect(cancel.status).toBe(200);
  });

  it('with custody, DELIVERY_FAILED → retry reopens the failed stop', async () => {
    const db = memoryDb();
    const rideId = await v2Assigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'v2rr-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'v2rr-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/confirm', {}, 'v2rr-c0');
    await driverPost(db, 'd1', rideId, '/stops/1/arrive', {}, 'v2rr-a1');
    await driverPost(db, 'd1', rideId, '/stops/1/fail', { reason: 'SENDER_UNAVAILABLE' }, 'v2rr-f1');
    await driverPost(db, 'd1', rideId, '/stops/2/arrive', {}, 'v2rr-a2');
    await driverPost(db, 'd1', rideId, '/stops/2/fail', { reason: 'RECEIVER_UNREACHABLE' }, 'v2rr-f2');
    expect(doc(db, rideId).state).toBe('DELIVERY_FAILED');

    // Custody → cancel blocked.
    const cancel = await post(db, 'p1', `/v1/rides/${rideId}/cancel`, {}, 'v2rr-cancel');
    expect(cancel.status).toBe(409);

    // Retry → RIDE_STARTED + last failed stop reopened.
    const retry = await driverPost(db, 'd1', rideId, '/retry-delivery', {}, 'v2rr-retry');
    expect(retry.status).toBe(200);
    const d = doc(db, rideId);
    expect(d.state).toBe('RIDE_STARTED');
    expect(d.stops![2].status).toBe('PENDING');
    expect(d.currentStopIndex).toBe(2);
  });
});

describe('buy_deliver quotes, purchase, settlement', () => {
  async function bdAssigned(db: ReturnType<typeof memoryDb>) {
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', bdCreateBody, 'bd-prog-create');
    await assignRide(db, r.rideId, 'p1', 'd1', 'bd-prog');
    return r.rideId;
  }

  it('full flow: quote → approve → purchase → deliver → settle', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdf-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdf-a0');

    // Driver cannot confirm purchase before approval.
    const early = await driverPost(db, 'd1', rideId, '/stops/0/confirm', { purchaseTotalMinor: 150000 }, 'bdf-early');
    expect(early.status).toBe(409);

    const q = await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [
        { name: 'Panadol', qty: 2, priceMinor: 15000 },
        { name: 'ORS sachets', qty: 4, priceMinor: 5000 },
      ],
    }, 'bdf-quote');
    expect(q.status).toBe(200);
    expect(doc(db, rideId).stops![0].status).toBe('WAITING_APPROVAL');
    expect(doc(db, rideId).stops![0].quote?.totalMinor).toBe(50000);

    const approve = await post(db, 'p1', `/v1/rides/${rideId}/stops/0/quote-response`, { decision: 'APPROVE' }, 'bdf-approve');
    expect(approve.status).toBe(200);
    expect(doc(db, rideId).stops![0].status).toBe('ARRIVED');
    expect(doc(db, rideId).shopping?.approvedTotalMinor).toBe(50000);

    const purchase = await driverPost(db, 'd1', rideId, '/stops/0/confirm', { purchaseTotalMinor: 48000 }, 'bdf-purchase');
    expect(purchase.status).toBe(200);
    let d = doc(db, rideId);
    expect(d.shopping?.spentMinor).toBe(48000);
    expect(d.state).toBe('RIDE_STARTED');
    expect(d.settlement?.shoppingTotalMinor).toBe(48000);
    expect(d.settlement?.totalDueMinor).toBe(32000 + 48000);

    // Purchase over approved → rejected.
    await driverPost(db, 'd1', rideId, '/stops/1/arrive', {}, 'bdf-a1');
    const c1 = await driverPost(db, 'd1', rideId, '/stops/1/confirm', {}, 'bdf-c1');
    expect(c1.status).toBe(200);
    d = doc(db, rideId);
    expect(d.state).toBe('RIDE_COMPLETED');

    // Driver reports cash settlement.
    const settle = await driverPost(db, 'd1', rideId, '/settlement', { status: 'PAID' }, 'bdf-settle');
    expect(settle.status).toBe(200);
    d = doc(db, rideId);
    expect(d.settlement?.driverReportedStatus).toBe('PAID');
    expect(d.settlement?.status).toBe('SETTLED');

    // Customer acknowledges receipt.
    const ack = await post(db, 'p1', `/v1/rides/${rideId}/acknowledge`, {}, 'bdf-ack');
    expect(ack.status).toBe(200);
    expect(doc(db, rideId).evidence?.customerAckAt).toBeTruthy();
  });

  it('rejects purchase above approved quote', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdo-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdo-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Panadol', qty: 1, priceMinor: 50000 }],
    }, 'bdo-quote');
    await post(db, 'p1', `/v1/rides/${rideId}/stops/0/quote-response`, { decision: 'APPROVE' }, 'bdo-approve');
    const over = await driverPost(db, 'd1', rideId, '/stops/0/confirm', { purchaseTotalMinor: 51000 }, 'bdo-over');
    expect(over.status).toBe(400);
  });

  it('rejects quote above booking budget', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdb-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdb-a0');
    const q = await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Expensive item', qty: 1, priceMinor: 250000 }],
    }, 'bdb-quote');
    expect(q.status).toBe(400);
  });

  it('rejects prohibited items in quotes', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdp-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdp-a0');
    const q = await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Cigarettes pack', qty: 1, priceMinor: 5000 }],
    }, 'bdp-quote');
    expect(q.status).toBe(400);
  });

  it('rejects quote-response from the driver', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdr-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdr-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Panadol', qty: 1, priceMinor: 5000 }],
    }, 'bdr-quote');
    const res = await driverPost(db, 'd1', rideId, '/stops/0/quote-response', { decision: 'APPROVE' }, 'bdr-resp');
    expect(res.status).toBe(403);
  });

  it('reject → driver can re-quote', async () => {
    const db = memoryDb();
    const rideId = await bdAssigned(db);
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'bdre-enroute');
    await driverPost(db, 'd1', rideId, '/stops/0/arrive', {}, 'bdre-a0');
    await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Panadol', qty: 1, priceMinor: 50000 }],
    }, 'bdre-q1');
    const rej = await post(db, 'p1', `/v1/rides/${rideId}/stops/0/quote-response`, { decision: 'REJECT' }, 'bdre-rej');
    expect(rej.status).toBe(200);
    const q2 = await driverPost(db, 'd1', rideId, '/stops/0/quote', {
      items: [{ name: 'Panadol', qty: 1, priceMinor: 30000 }],
    }, 'bdre-q2');
    expect(q2.status).toBe(200);
    expect(doc(db, rideId).stops![0].quote?.totalMinor).toBe(30000);
  });

  it('does not double-count surcharges already inside the agreed fare', async () => {
    const db = memoryDb();
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    // Snapshot whose serviceFee/stopFees are already folded into the fare.
    db.seed('pricingSnapshots', 'snap-fees', {
      snapshotId: 'snap-fees',
      recommendedFareMinor: 35000,
      offerBoundMinMinor: 15000,
      offerBoundMaxMinor: 90000,
      currency: 'PKR',
      pricingRulesVersion: 'fixture-v1',
      computedAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
      inputs: {
        distanceKm: 6.1,
        durationMin: 22,
        serviceFeeMinor: 10000,
        stopFeesMinor: 5000,
      },
    });
    const r = await createRide(
      db,
      'p1',
      { ...bdCreateBody, pricingSnapshotId: 'snap-fees' },
      'fees-create',
    );
    await assignRide(db, r.rideId, 'p1', 'd1', 'fees');
    let d = doc(db, r.rideId);
    expect(d.settlement?.deliveryFareMinor).toBe(32000);
    expect(d.settlement?.serviceFeeMinor).toBe(10000);
    expect(d.settlement?.stopFeesMinor).toBe(5000);
    // totalDue = fare + shopping only — fees must not be added a second time.
    expect(d.settlement?.totalDueMinor).toBe(32000);

    await driverPost(db, 'd1', r.rideId, '/en-route', {}, 'fees-enroute');
    await driverPost(db, 'd1', r.rideId, '/stops/0/arrive', {}, 'fees-a0');
    await driverPost(db, 'd1', r.rideId, '/stops/0/quote', {
      items: [{ name: 'Panadol', qty: 1, priceMinor: 50000 }],
    }, 'fees-quote');
    await post(db, 'p1', `/v1/rides/${r.rideId}/stops/0/quote-response`, { decision: 'APPROVE' }, 'fees-approve');
    await driverPost(db, 'd1', r.rideId, '/stops/0/confirm', { purchaseTotalMinor: 48000 }, 'fees-purchase');
    d = doc(db, r.rideId);
    expect(d.settlement?.totalDueMinor).toBe(32000 + 48000);
  });
});

describe('settlement + disputes', () => {
  async function completedV2(db: ReturnType<typeof memoryDb>) {
    seedPassenger(db, 'p1');
    seedDriver(db, 'd1');
    seedPricing(db);
    const r = await createRide(db, 'p1', v2CreateBody, 'sd-create');
    await assignRide(db, r.rideId, 'p1', 'd1', 'sd');
    const rideId = r.rideId;
    await driverPost(db, 'd1', rideId, '/en-route', {}, 'sd-enroute');
    for (const seq of [0, 1, 2]) {
      await driverPost(db, 'd1', rideId, `/stops/${seq}/arrive`, {}, `sd-a${seq}`);
      await driverPost(db, 'd1', rideId, `/stops/${seq}/confirm`, {}, `sd-c${seq}`);
    }
    return rideId;
  }

  it('UNPAID report leaves settlement PENDING', async () => {
    const db = memoryDb();
    const rideId = await completedV2(db);
    const res = await driverPost(db, 'd1', rideId, '/settlement', { status: 'UNPAID' }, 'sd-unpaid');
    expect(res.status).toBe(200);
    const d = doc(db, rideId);
    expect(d.settlement?.driverReportedStatus).toBe('UNPAID');
    expect(d.settlement?.status).toBe('PENDING');
  });

  it('customer opens a dispute → disputeStatus OPEN, settlement DISPUTED', async () => {
    const db = memoryDb();
    const rideId = await completedV2(db);
    const res = await post(db, 'p1', `/v1/rides/${rideId}/disputes`, {
      category: 'NOT_DELIVERED',
      message: 'Package never arrived',
    }, 'sd-dispute');
    expect(res.status).toBe(200);
    const d = doc(db, rideId);
    expect(d.disputeStatus).toBe('OPEN');
    expect(d.settlement?.status).toBe('DISPUTED');
    const dispute = db.getDoc('disputes', d.disputeId!) as Record<string, unknown>;
    expect(dispute.category).toBe('NOT_DELIVERED');
    expect(dispute.reporterRole).toBe('passenger');
  });

  it('rejects a second open dispute', async () => {
    const db = memoryDb();
    const rideId = await completedV2(db);
    await post(db, 'p1', `/v1/rides/${rideId}/disputes`, {
      category: 'DAMAGED',
      message: 'Box was crushed',
    }, 'sd-d1');
    const res = await post(db, 'd1', `/v1/rides/${rideId}/disputes`, {
      category: 'CUSTOMER_BEHAVIOR',
      message: 'Customer abusive',
    }, 'sd-d2');
    expect(res.status).toBe(409);
  });

  it('rejects disputes from non-parties', async () => {
    const db = memoryDb();
    const rideId = await completedV2(db);
    const res = await post(db, 'stranger', `/v1/rides/${rideId}/disputes`, {
      category: 'OTHER',
      message: 'Not my business',
    }, 'sd-stranger');
    expect(res.status).toBe(403);
  });
});
