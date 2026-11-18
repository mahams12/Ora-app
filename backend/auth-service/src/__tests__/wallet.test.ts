import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

const WORKER = 'test-worker-token-16';
const IDEM = 'wallet-idem-key-01';

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function approvedVendor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  types: string[],
  overrides: Record<string, unknown> = {},
) {
  const apps: Record<string, unknown> = {};
  for (const t of types) {
    apps[t] = { status: 'approved', submittedAt: '2025-01-01T00:00:00Z' };
  }
  seedUser(db, uid, { vendorApplications: apps, ...overrides });
}

function approvedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  seedUser(db, uid, { role: 'driver', driverStatus: 'approved', ...overrides });
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
    internalWorkerToken: WORKER,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

function authed(app: ReturnType<typeof appFor>) {
  return {
    get: (url: string) => request(app).get(url).set('Authorization', 'Bearer t'),
    post: (url: string) =>
      request(app).post(url).set('Authorization', 'Bearer t'),
  };
}

function worker(app: ReturnType<typeof appFor>) {
  return {
    post: (url: string) =>
      request(app).post(url).set('X-Ora-Worker-Token', WORKER),
  };
}

function walletBalanceMinor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
): number {
  const doc = db.getDoc('walletAccounts', uid);
  return Number(doc?.balanceMinor ?? 0);
}

function ledgerEntries(db: ReturnType<typeof memoryDb>) {
  return [...db.store.entries()]
    .filter(([k]) => k.startsWith('walletLedgerEntries/'))
    .map(([k, v]) => ({ id: k, ...(v as Record<string, unknown>) }));
}

// ---- Marketplace seed helpers (same shapes as marketplace.test.ts) ----------

const CARGO_BODY = {
  type: 'cargo',
  categoryId: 'pickups',
  subcategoryId: 'shehzore',
  title: 'Shehzore with driver',
  description: 'City + intercity goods transport, loading included.',
  price: 4500,
  priceUnit: 'Per Trip',
  location: 'Lahore',
  contactNumber: '+923009998877',
  details: { capacity: '1 ton', serviceArea: 'Lahore + motorway' },
};

async function listingOf(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  body: Record<string, unknown> = CARGO_BODY,
) {
  const res = await authed(appFor(db, uid))
    .post('/v1/vendor/listings')
    .set('Idempotency-Key', IDEM)
    .send(body);
  expect(res.status).toBe(201);
  return res.body.listing.listingId as string;
}

async function bookListing(
  db: ReturnType<typeof memoryDb>,
  customerUid: string,
  listingId: string,
  key: string,
) {
  const res = await authed(appFor(db, customerUid))
    .post('/v1/marketplace/bookings')
    .set('Idempotency-Key', key)
    .send({
      listingId,
      request: { contactName: 'Test', contactPhone: '+923004445555' },
    });
  expect(res.status).toBe(201);
  return res.body.booking.bookingId as string;
}

function vendorAct(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  bookingId: string,
  payload: Record<string, unknown>,
) {
  return authed(appFor(db, uid))
    .post(`/v1/marketplace/bookings/${bookingId}/vendor-action`)
    .send(payload);
}

// ---- Ride seed helpers (same flow as rides.test.ts) -------------------------

function seedPricing(db: ReturnType<typeof memoryDb>, id = 'snap-1') {
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
  });
}

async function assignRide(db: ReturnType<typeof memoryDb>) {
  const passengerId = 'p-1';
  const driverId = 'd-1';
  seedUser(db, passengerId, { displayName: 'Passenger' });
  approvedDriver(db, driverId);
  seedPricing(db);
  const app = appFor(db, passengerId);
  const created = await request(app)
    .post('/v1/rides')
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', 'w-create-ride-01')
    .send({
      pickup: { lat: 24.86, lng: 67.0, address: 'A' },
      destination: { lat: 24.9, lng: 67.1, address: 'B' },
      city: 'Karachi',
      category: 'economy',
      serviceType: 'ride',
      passengerOfferMinor: 25000,
      pricingSnapshotId: 'snap-1',
      paymentMethod: 'CASH',
      passengerCount: 1,
    });
  expect(created.status).toBe(201);
  const rideId = created.body.data.rideId as string;
  const offer = await request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/offers`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', 'w-offer-01')
    .send({
      type: 'DRIVER_COUNTEROFFER',
      amountMinor: 26000,
      expectedRequestVersion: 1,
    });
  expect(offer.status).toBe(201);
  const select = await request(app)
    .post(`/v1/rides/${rideId}/offers/${offer.body.data.offerId}/select`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', 'w-select-01')
    .send({});
  expect(select.status).toBe(200);
  return { rideId, driverId, passengerId };
}

async function drive(
  db: ReturnType<typeof memoryDb>,
  driverId: string,
  rideId: string,
  path: string,
  idem: string,
) {
  return request(appFor(db, driverId))
    .post(`/v1/rides/${rideId}/${path}`)
    .set('Authorization', 'Bearer t')
    .set('Idempotency-Key', idem)
    .send({});
}

// ===========================================================================

describe('partner wallet — access', () => {
  it('denies plain passengers (403 NOT_A_PARTNER)', async () => {
    const db = memoryDb();
    seedUser(db, 'customer');
    const res = await authed(appFor(db, 'customer')).get('/v1/wallet');
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('NOT_A_PARTNER');
  });

  it('serves one shared wallet across every approved role', async () => {
    const db = memoryDb();
    approvedVendor(db, 'multi', ['cargo', 'service'], {
      driverStatus: 'approved',
      role: 'driver',
    });
    const first = await authed(appFor(db, 'multi')).get('/v1/wallet');
    expect(first.status).toBe(200);
    expect(first.body.roles.sort()).toEqual(['cargo', 'driver', 'service']);
    expect(first.body.points).toBe(0);
    expect(first.body.account.balanceMinor).toBe(0);
    // Same account doc — lazily created once, reused by every dashboard.
    const second = await authed(appFor(db, 'multi')).get('/v1/wallet');
    expect(second.body.account.userId).toBe('multi');
    expect(walletBalanceMinor(db, 'multi')).toBe(0);
  });

  it('flags lowBalance / acceptBlocked from balance', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    db.seed('walletAccounts', 'v1', {
      userId: 'v1',
      balanceMinor: -5000,
      currency: 'PKR',
      createdAt: 'x',
      updatedAt: 'x',
      version: 1,
    });
    const res = await authed(appFor(db, 'v1')).get('/v1/wallet');
    expect(res.body.acceptBlocked).toBe(true);
    expect(res.body.points).toBe(-50);
  });
});

describe('partner wallet — top-ups', () => {
  it('creates a PENDING top-up; points never credit from the client call', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    const app = appFor(db, 'v1');
    const res = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'topup-key-1')
      .send({ points: 2000, method: 'easypaisa', reference: 'EP-123' });
    expect(res.status).toBe(201);
    expect(res.body.topup.status).toBe('PENDING');
    expect(res.body.topup.points).toBe(2000);
    expect(walletBalanceMinor(db, 'v1')).toBe(0); // unchanged

    // Idempotent retry — same key returns the same pending request.
    const retry = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'topup-key-1')
      .send({ points: 2000, method: 'easypaisa', reference: 'EP-123' });
    expect(retry.body.topup.topupId).toBe(res.body.topup.topupId);
  });

  it('credits points only on internal approve — atomically, exactly once', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    const app = appFor(db, 'v1');
    const created = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'topup-key-2')
      .send({ points: 2000, method: 'jazzcash' });
    const topupId = created.body.topup.topupId;

    // Client cannot self-resolve.
    const forbidden = await authed(app).post(
      `/v1/internal/wallet/topups/${topupId}/resolve`,
    );
    expect([401, 403]).toContain(forbidden.status);

    const approved = await worker(app)
      .post(`/v1/internal/wallet/topups/${topupId}/resolve`)
      .send({ action: 'approve', resolvedBy: 'ops-1' });
    expect(approved.status).toBe(200);
    expect(approved.body.topup.status).toBe('CREDITED');
    expect(walletBalanceMinor(db, 'v1')).toBe(200_000);

    const wallet = await authed(app).get('/v1/wallet');
    expect(wallet.body.points).toBe(2000);

    const txns = await authed(app).get('/v1/wallet/transactions');
    expect(txns.body.entries).toHaveLength(1);
    expect(txns.body.entries[0].type).toBe('TOPUP_CREDIT');
    expect(txns.body.entries[0].pointsDelta).toBe(2000);
    expect(txns.body.entries[0].balanceAfterMinor).toBe(200_000);

    // Replay-safe: approving again returns the same record, no double credit.
    const again = await worker(app)
      .post(`/v1/internal/wallet/topups/${topupId}/resolve`)
      .send({ action: 'approve', resolvedBy: 'ops-1' });
    expect(again.status).toBe(200);
    expect(walletBalanceMinor(db, 'v1')).toBe(200_000);
    expect(ledgerEntries(db)).toHaveLength(1);
  });

  it('rejects a top-up without crediting', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    const app = appFor(db, 'v1');
    const created = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'topup-key-3')
      .send({ points: 500, method: 'bank_transfer' });
    const rejected = await worker(app)
      .post(`/v1/internal/wallet/topups/${created.body.topup.topupId}/resolve`)
      .send({ action: 'reject', resolvedBy: 'ops-1' });
    expect(rejected.body.topup.status).toBe('REJECTED');
    expect(walletBalanceMinor(db, 'v1')).toBe(0);
    expect(ledgerEntries(db)).toHaveLength(0);
  });

  it('validates points range, method and partner role', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    seedUser(db, 'customer');
    const app = appFor(db, 'v1');
    for (const body of [
      { points: 10, method: 'easypaisa' },
      { points: 600_000, method: 'easypaisa' },
      { points: 500, method: 'bitcoin' },
      { points: 'abc', method: 'easypaisa' },
    ]) {
      const res = await authed(app)
        .post('/v1/wallet/topups')
        .set('Idempotency-Key', `bad-${JSON.stringify(body).length}-${body.points}`)
        .send(body);
      expect(res.status).toBe(400);
    }
    const notPartner = await authed(appFor(db, 'customer'))
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'customer-key-1')
      .send({ points: 500, method: 'easypaisa' });
    expect(notPartner.status).toBe(403);
  });
});

describe('partner wallet — commission on marketplace completion', () => {
  it('deducts 10% only at vendor-confirmed completion, exactly once', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v-cargo', ['cargo']);
    seedUser(db, 'customer');
    db.seed('walletAccounts', 'v-cargo', {
      userId: 'v-cargo',
      balanceMinor: 100_000, // 1,000 pts
      currency: 'PKR',
      createdAt: 'x',
      updatedAt: 'x',
      version: 1,
    });
    const listingId = await listingOf(db, 'v-cargo');
    const id = await bookListing(db, 'customer', listingId, 'booking-key-1');

    // No commission before completion.
    await vendorAct(db, 'v-cargo', id, { action: 'accept' });
    await vendorAct(db, 'v-cargo', id, { action: 'start' });
    expect(walletBalanceMinor(db, 'v-cargo')).toBe(100_000);
    expect(ledgerEntries(db)).toHaveLength(0);

    // Complete → 10% of Rs 4,500 = 450 points (45,000 minor).
    const done = await vendorAct(db, 'v-cargo', id, { action: 'complete' });
    expect(done.status).toBe(200);
    expect(done.body.booking.status).toBe('completed');
    expect(done.body.booking.commission.points).toBe(450);
    expect(done.body.booking.commission.bps).toBe(1000);
    expect(walletBalanceMinor(db, 'v-cargo')).toBe(55_000);

    const entries = ledgerEntries(db);
    expect(entries).toHaveLength(1);
    expect(entries[0].type).toBe('COMMISSION_DEBIT');
    expect(entries[0].role).toBe('cargo');
    expect(entries[0].sourceId).toBe(id);
    expect(entries[0].pointsDelta).toBe(-450);
    expect(entries[0].grossMinor).toBe(450_000);

    // Re-completing is blocked — the ledger still holds a single entry.
    const again = await vendorAct(db, 'v-cargo', id, { action: 'complete' });
    expect(again.status).toBe(409);
    expect(ledgerEntries(db)).toHaveLength(1);
  });

  it('uses the agreed quote amount, not the listing price', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v-cargo', ['cargo']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db, 'v-cargo');
    const id = await bookListing(db, 'customer', listingId, 'booking-key-q');

    await vendorAct(db, 'v-cargo', id, { action: 'quote', amount: 6000 });
    await authed(appFor(db, 'customer'))
      .post(`/v1/marketplace/bookings/${id}/customer-action`)
      .send({ action: 'accept' });
    await vendorAct(db, 'v-cargo', id, { action: 'complete' });

    // 10% of Rs 6,000 quote = 600 pts.
    const entry = ledgerEntries(db).find((e) => e.type === 'COMMISSION_DEBIT');
    expect(entry?.pointsDelta).toBe(-600);
    expect(entry?.grossMinor).toBe(600_000);
  });

  it('honours finalAmount overrides (rental early checkout / extension)', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v-rental', ['rental']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db, 'v-rental', {
      type: 'rental',
      categoryId: 'residential',
      subcategoryId: 'apartments_flats',
      title: '2-bed furnished flat',
      description: 'Family apartment near MM Alam Road.',
      price: 85000,
      priceUnit: 'Per Month',
      location: 'Gulberg III, Lahore',
      contactNumber: '+923007654321',
      details: { amenities: ['Parking'] },
    });
    const res = await authed(appFor(db, 'customer'))
      .post('/v1/marketplace/bookings')
      .set('Idempotency-Key', 'booking-key-r')
      .send({
        listingId,
        request: {
          contactName: 'Test',
          contactPhone: '+923004445555',
          details: { finalAmount: 50000, checkIn: '2026-12-01', checkOut: '2026-12-15' },
        },
      });
    expect(res.status).toBe(201);
    const id = res.body.booking.bookingId;
    await vendorAct(db, 'v-rental', id, { action: 'accept' });
    await vendorAct(db, 'v-rental', id, { action: 'complete' });
    // 10% of Rs 50,000 final amount = 5,000 pts — not the Rs 85,000 list price.
    const entry = ledgerEntries(db).find((e) => e.type === 'COMMISSION_DEBIT');
    expect(entry?.pointsDelta).toBe(-5000);
  });

  it('respects an admin-configured commission rate override', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v-cargo', ['cargo']);
    seedUser(db, 'customer');
    db.seed('walletConfig', 'global', {
      commissionBps: { cargo: 2000 },
    });
    const listingId = await listingOf(db, 'v-cargo');
    const id = await bookListing(db, 'customer', listingId, 'booking-key-cfg');
    await vendorAct(db, 'v-cargo', id, { action: 'accept' });
    await vendorAct(db, 'v-cargo', id, { action: 'complete' });
    const entry = ledgerEntries(db).find((e) => e.type === 'COMMISSION_DEBIT');
    expect(entry?.commissionBps).toBe(2000);
    expect(entry?.pointsDelta).toBe(-900); // 20% of 4,500
  });

  it('drives the balance negative on insufficient funds and blocks new accepts', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v-cargo', ['cargo']);
    seedUser(db, 'customer');
    db.seed('walletAccounts', 'v-cargo', {
      userId: 'v-cargo',
      balanceMinor: 10_000, // only 100 pts — cannot cover 450
      currency: 'PKR',
      createdAt: 'x',
      updatedAt: 'x',
      version: 1,
    });
    const listingId = await listingOf(db, 'v-cargo');
    const id = await bookListing(db, 'customer', listingId, 'booking-key-n1');
    await vendorAct(db, 'v-cargo', id, { action: 'accept' });
    const done = await vendorAct(db, 'v-cargo', id, { action: 'complete' });
    expect(done.status).toBe(200); // completion is NEVER blocked
    expect(walletBalanceMinor(db, 'v-cargo')).toBe(10_000 - 45_000);

    // Next accept is gated until recharge.
    const listing2 = await listingOf(db, 'v-cargo', {
      ...CARGO_BODY,
      title: 'Second truck listing',
    });
    const id2 = await bookListing(db, 'customer', listing2, 'booking-key-n2');
    const blocked = await vendorAct(db, 'v-cargo', id2, { action: 'accept' });
    expect(blocked.status).toBe(402);
    expect(blocked.body.error.code).toBe('WALLET_BALANCE_LOW');

    // Recharge (verified) → eligibility restored.
    const app = appFor(db, 'v-cargo');
    const tu = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'tu-restore')
      .send({ points: 1000, method: 'easypaisa' });
    await worker(app)
      .post(`/v1/internal/wallet/topups/${tu.body.topup.topupId}/resolve`)
      .send({ action: 'approve' });
    expect(walletBalanceMinor(db, 'v-cargo')).toBe(10_000 - 45_000 + 100_000);
    const retry = await vendorAct(db, 'v-cargo', id2, { action: 'accept' });
    expect(retry.status).toBe(200);
  });
});

describe('partner wallet — commission on driver ride completion', () => {
  it('deducts 10% of the agreed fare inside the completion transaction', async () => {
    const db = memoryDb();
    const { rideId, driverId } = await assignRide(db);
    await drive(db, driverId, rideId, 'en-route', 'w-enroute-01');
    await drive(db, driverId, rideId, 'arrive', 'w-arrived-01');
    await drive(db, driverId, rideId, 'start', 'w-started-01');
    expect(walletBalanceMinor(db, driverId)).toBe(0); // nothing before complete

    const done = await drive(db, driverId, rideId, 'complete', 'w-complete-01');
    expect(done.status).toBe(200);
    expect(done.body.data.state).toBe('RIDE_COMPLETED');

    // 10% of 26,000 minor (Rs 260) = 2,600 minor = 26 points.
    const entry = ledgerEntries(db).find((e) => e.type === 'COMMISSION_DEBIT');
    expect(entry).toBeTruthy();
    expect(entry?.sourceType).toBe('ride');
    expect(entry?.sourceId).toBe(rideId);
    expect(entry?.role).toBe('driver');
    expect(entry?.pointsDelta).toBe(-26);
    expect(walletBalanceMinor(db, driverId)).toBe(-2600);

    const ride = db.getDoc('rides', rideId)!;
    expect(ride.commission).toMatchObject({ points: 26, bps: 1000 });
  });
});

describe('partner wallet — withdrawals', () => {
  it('creates a pending debit request; approve debits, insufficient rejects', async () => {
    const db = memoryDb();
    approvedVendor(db, 'v1', ['service']);
    db.seed('walletAccounts', 'v1', {
      userId: 'v1',
      balanceMinor: 100_000,
      currency: 'PKR',
      createdAt: 'x',
      updatedAt: 'x',
      version: 1,
    });
    const app = appFor(db, 'v1');

    const ok = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'withdraw-key-1')
      .send({ kind: 'debit', points: 500, method: 'easypaisa' });
    expect(ok.body.topup.status).toBe('PENDING');
    expect(walletBalanceMinor(db, 'v1')).toBe(100_000); // untouched

    const approved = await worker(app)
      .post(`/v1/internal/wallet/topups/${ok.body.topup.topupId}/resolve`)
      .send({ action: 'approve', resolvedBy: 'ops-1' });
    expect(approved.status).toBe(200);
    expect(walletBalanceMinor(db, 'v1')).toBe(50_000);
    const entry = ledgerEntries(db).find((e) => e.type === 'WITHDRAWAL_DEBIT');
    expect(entry?.pointsDelta).toBe(-500);

    // A second withdrawal larger than the balance cannot be approved.
    const big = await authed(app)
      .post('/v1/wallet/topups')
      .set('Idempotency-Key', 'withdraw-key-2')
      .send({ kind: 'debit', points: 900, method: 'easypaisa' });
    const denied = await worker(app)
      .post(`/v1/internal/wallet/topups/${big.body.topup.topupId}/resolve`)
      .send({ action: 'approve', resolvedBy: 'ops-1' });
    expect(denied.status).toBe(409);
    expect(denied.body.error.code).toBe('INSUFFICIENT_BALANCE');
    expect(walletBalanceMinor(db, 'v1')).toBe(50_000);
  });
});
