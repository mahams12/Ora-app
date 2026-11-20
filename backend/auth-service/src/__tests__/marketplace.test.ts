import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

const IDEMPOTENCY = 'test-idem-key-0001';

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
) {
  const apps: Record<string, unknown> = {};
  for (const t of types) {
    apps[t] = { status: 'approved', submittedAt: '2025-01-01T00:00:00Z' };
  }
  seedUser(db, uid, { vendorApplications: apps });
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


function authed(app: ReturnType<typeof appFor>) {
  return {
    get: (url: string) => request(app).get(url).set('Authorization', 'Bearer t'),
    post: (url: string) => request(app).post(url).set('Authorization', 'Bearer t'),
    patch: (url: string) => request(app).patch(url).set('Authorization', 'Bearer t'),
    delete: (url: string) => request(app).delete(url).set('Authorization', 'Bearer t'),
  };
}

const SERVICE_BODY = {
  type: 'service',
  categoryId: 'home_repair',
  subcategoryId: 'ac',
  title: 'AC repair & gas refill',
  description: 'Certified AC technician, all makes and models.',
  price: 2500,
  priceUnit: 'Per Visit',
  location: 'DHA Phase 5, Lahore',
  contactNumber: '+923001234567',
  details: { timing: '9am–9pm', features: ['Same-day', '90-day warranty'] },
};

const RENTAL_BODY = {
  type: 'rental',
  categoryId: 'residential',
  subcategoryId: 'apartments_flats',
  title: '2-bed furnished flat',
  description: 'Family apartment near MM Alam Road.',
  price: 85000,
  priceUnit: 'Per Month',
  location: 'Gulberg III, Lahore',
  contactNumber: '+923007654321',
  details: { amenities: ['Parking', 'Lift'], subcategoryName: 'Apartments' },
};

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

async function createListing(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  body: Record<string, unknown> = SERVICE_BODY,
) {
  const res = await authed(appFor(db, uid))
    .post('/v1/vendor/listings')
    .set('Idempotency-Key', IDEMPOTENCY)
    .send(body);
  return res;
}

async function createBookingFor(
  db: ReturnType<typeof memoryDb>,
  customerUid: string,
  listingId: string,
  key = 'bk-key-1',
  requestBody: Record<string, unknown> = {},
) {
  return authed(appFor(db, customerUid))
    .post('/v1/marketplace/bookings')
    .set('Idempotency-Key', key)
    .send({
      listingId,
      request: {
        contactName: 'Test Customer',
        contactPhone: '+923004445555',
        ...requestBody,
      },
    });
}

describe('marketplace listings', () => {
  it('creates a published listing for an approved vendor', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    const res = await createListing(db, 'vendor1');
    expect(res.status).toBe(201);
    expect(res.body.listing.type).toBe('service');
    expect(res.body.listing.status).toBe('published');
    expect(res.body.listing.vendorId).toBe('vendor1');
  });

  it('rejects vendors who are pending, suspended, or never applied', async () => {
    const db = memoryDb();
    seedUser(db, 'pending', {
      vendorApplications: { service: { status: 'pending' } },
    });
    seedUser(db, 'suspended', {
      vendorApplications: { service: { status: 'suspended' } },
    });
    seedUser(db, 'none');

    for (const [uid, code] of [
      ['pending', 'VENDOR_NOT_APPROVED'],
      ['suspended', 'VENDOR_SUSPENDED'],
      ['none', 'VENDOR_NOT_APPROVED'],
    ] as const) {
      const res = await createListing(db, uid);
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe(code);
    }
  });

  it('blocks cross-role posting (service vendor cannot post rental)', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    const res = await createListing(db, 'vendor1', RENTAL_BODY);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('VENDOR_NOT_APPROVED');
  });

  it('validates taxonomy, price unit, required fields, and photo bounds', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);

    const badCat = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      categoryId: 'not_a_category',
    });
    expect(badCat.status).toBe(400);

    const badSub = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      subcategoryId: 'houses', // valid rental id, wrong vertical
    });
    expect(badSub.status).toBe(400);

    const badUnit = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      priceUnit: 'Per Month',
    });
    expect(badUnit.status).toBe(400);

    const shortTitle = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      title: 'ab',
    });
    expect(shortTitle.status).toBe(400);

    const bigPhoto = `data:image/jpeg;base64,${'A'.repeat(700 * 1024)}`;
    const bigPhotos = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      photos: [bigPhoto],
    });
    expect(bigPhotos.status).toBe(400);

    const injection = await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      vendorId: 'spoofed',
      status: 'published',
    });
    expect(injection.status).toBe(400);
  });

  it('enforces ownership on get/patch/delete — cross-vendor sees 404', async () => {
    const db = memoryDb();
    approvedVendor(db, 'owner', ['service']);
    approvedVendor(db, 'other', ['service']);
    const created = await createListing(db, 'owner');
    const id = created.body.listing.listingId;

    const otherGet = await authed(appFor(db, 'other')).get(
      `/v1/vendor/listings/${id}`,
    );
    expect(otherGet.status).toBe(404);

    const otherPatch = await authed(appFor(db, 'other'))
      .patch(`/v1/vendor/listings/${id}`)
      .send({ title: 'hijacked title' });
    expect(otherPatch.status).toBe(404);

    const otherDelete = await authed(appFor(db, 'other')).delete(
      `/v1/vendor/listings/${id}`,
    );
    expect(otherDelete.status).toBe(404);

    // Owner edit works; type cannot change.
    const patch = await authed(appFor(db, 'owner'))
      .patch(`/v1/vendor/listings/${id}`)
      .send({ title: 'Updated AC service', price: 3000 });
    expect(patch.status).toBe(200);
    expect(patch.body.listing.title).toBe('Updated AC service');
    expect(patch.body.listing.price).toBe(3000);

    const typeChange = await authed(appFor(db, 'owner'))
      .patch(`/v1/vendor/listings/${id}`)
      .send({ type: 'rental' });
    expect(typeChange.status).toBe(400);
  });

  it('publish/pause controls customer discovery; delete hides everywhere', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const created = await createListing(db, 'vendor1');
    const id = created.body.listing.listingId;

    const list1 = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/listings?type=service&categoryId=home_repair',
    );
    expect(list1.body.listings).toHaveLength(1);

    const paused = await authed(appFor(db, 'vendor1'))
      .patch(`/v1/vendor/listings/${id}`)
      .send({ status: 'paused' });
    expect(paused.status).toBe(200);

    const list2 = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/listings?type=service&categoryId=home_repair',
    );
    expect(list2.body.listings).toHaveLength(0);

    const detail = await authed(appFor(db, 'customer')).get(
      `/v1/marketplace/listings/${id}`,
    );
    expect(detail.status).toBe(404);

    const republished = await authed(appFor(db, 'vendor1'))
      .patch(`/v1/vendor/listings/${id}`)
      .send({ status: 'published' });
    expect(republished.status).toBe(200);

    const del = await authed(appFor(db, 'vendor1')).delete(
      `/v1/vendor/listings/${id}`,
    );
    expect(del.status).toBe(200);
    const list3 = await authed(appFor(db, 'vendor1')).get(
      '/v1/vendor/listings?type=service',
    );
    expect(list3.body.listings).toHaveLength(0);
  });

  it('filters published listings by subcategory and free-text q', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    await createListing(db, 'vendor1');
    await createListing(db, 'vendor1', {
      ...SERVICE_BODY,
      subcategoryId: 'plumbing',
      title: 'Emergency plumber 24/7',
      description: 'Leak repair and pipe fitting.',
    });
    seedUser(db, 'customer');

    const bySub = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/listings?type=service&categoryId=home_repair&subcategoryId=plumbing',
    );
    expect(bySub.body.listings).toHaveLength(1);
    expect(bySub.body.listings[0].title).toContain('plumber');

    const byQ = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/listings?type=service&q=emergency',
    );
    expect(byQ.body.listings).toHaveLength(1);
  });

  it('rejects invalid type query on the discovery endpoint', async () => {
    const db = memoryDb();
    seedUser(db, 'customer');
    const res = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/listings?type=admin',
    );
    expect(res.status).toBe(400);
  });
});

describe('marketplace bookings', () => {
  async function listingOf(
    db: ReturnType<typeof memoryDb>,
    vendorUid = 'vendor1',
    body: Record<string, unknown> = SERVICE_BODY,
  ) {
    const res = await createListing(db, vendorUid, body);
    expect(res.status).toBe(201);
    return res.body.listing.listingId as string;
  }

  it('creates a request; vendor quotes; customer accepts → confirmed', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer', { displayName: 'Sara' });
    const listingId = await listingOf(db);

    const created = await createBookingFor(db, 'customer', listingId);
    expect(created.status).toBe(201);
    const bookingId = created.body.booking.bookingId;
    expect(created.body.booking.status).toBe('requested');
    expect(created.body.booking.vendorId).toBe('vendor1');

    const quoted = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${bookingId}/vendor-action`)
      .send({ action: 'quote', amount: 2800, note: 'Includes parts' });
    expect(quoted.status).toBe(200);
    expect(quoted.body.booking.status).toBe('quoted');
    expect(quoted.body.booking.quote.amount).toBe(2800);

    const accepted = await authed(appFor(db, 'customer'))
      .post(`/v1/marketplace/bookings/${bookingId}/customer-action`)
      .send({ action: 'accept' });
    expect(accepted.status).toBe(200);
    expect(accepted.body.booking.status).toBe('confirmed');
    expect(accepted.body.booking.statusHistory.map((h: { status: string }) => h.status))
      .toEqual(['requested', 'quoted', 'confirmed']);
  });

  it('full lifecycle: request → accept → start → complete', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['cargo']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db, 'vendor1', CARGO_BODY);
    const created = await createBookingFor(db, 'customer', listingId);
    const id = created.body.booking.bookingId;

    const accept = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'accept' });
    expect(accept.body.booking.status).toBe('confirmed');

    const start = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'start' });
    expect(start.body.booking.status).toBe('in_progress');

    const complete = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'complete' });
    expect(complete.body.booking.status).toBe('completed');

    // Terminal — no further transitions.
    const late = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'cancel' });
    expect(late.status).toBe(409);
    expect(late.body.error.code).toBe('INVALID_STATUS_TRANSITION');
  });

  it('rejects duplicate active requests but idempotent retry returns original', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db);

    const first = await createBookingFor(db, 'customer', listingId);
    expect(first.status).toBe(201);

    const dup = await createBookingFor(db, 'customer', listingId, 'bk-key-2');
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('BOOKING_ALREADY_ACTIVE');

    const retry = await createBookingFor(db, 'customer', listingId);
    expect(retry.status).toBe(201);
    expect(retry.body.booking.bookingId).toBe(first.body.booking.bookingId);
  });

  it('blocks: own listing, unpublished listing, missing idempotency, bad request', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db);

    const own = await createBookingFor(db, 'vendor1', listingId);
    expect(own.status).toBe(403);

    const draft = await authed(appFor(db, 'vendor1'))
      .post('/v1/vendor/listings')
      .set('Idempotency-Key', IDEMPOTENCY)
      .send({ ...SERVICE_BODY, status: 'draft' });
    const onDraft = await createBookingFor(
      db,
      'customer',
      draft.body.listing.listingId,
    );
    expect(onDraft.status).toBe(404);

    const noKey = await authed(appFor(db, 'customer'))
      .post('/v1/marketplace/bookings')
      .send({ listingId, request: { contactName: 'X', contactPhone: '12345' } });
    expect(noKey.status).toBe(400);
    expect(noKey.body.error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');

    const noContact = await createBookingFor(db, 'customer', listingId, 'bk-key-x', {
      contactName: 'x',
    });
    expect(noContact.status).toBe(400);
  });

  it('enforces invalid transitions on both sides', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db);
    const created = await createBookingFor(db, 'customer', listingId);
    const id = created.body.booking.bookingId;

    // Customer can't accept an unquoted request.
    const earlyAccept = await authed(appFor(db, 'customer'))
      .post(`/v1/marketplace/bookings/${id}/customer-action`)
      .send({ action: 'accept' });
    expect(earlyAccept.status).toBe(409);

    // Vendor can't start an unconfirmed booking.
    const earlyStart = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'start' });
    expect(earlyStart.status).toBe(409);

    // Customer can cancel while requested.
    const cancelled = await authed(appFor(db, 'customer'))
      .post(`/v1/marketplace/bookings/${id}/customer-action`)
      .send({ action: 'cancel', note: 'Changed my mind' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.booking.status).toBe('cancelled');

    // Vendor can't reject a cancelled booking.
    const lateReject = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'reject' });
    expect(lateReject.status).toBe(409);
  });

  it('rental: second customer cannot confirm overlapping dates', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['rental']);
    seedUser(db, 'cust1');
    seedUser(db, 'cust2');
    const listingId = await listingOf(db, 'vendor1', RENTAL_BODY);
    const dates = {
      details: { checkIn: '2025-03-10', checkOut: '2025-03-15', guests: '2' },
    };

    const b1 = await createBookingFor(db, 'cust1', listingId, 'bk-key-1', dates);
    const b2 = await createBookingFor(db, 'cust2', listingId, 'bk-key-2', dates);
    expect(b1.status).toBe(201);
    expect(b2.status).toBe(201);

    const confirm1 = await authed(appFor(db, 'vendor1'))
      .post(
        `/v1/marketplace/bookings/${b1.body.booking.bookingId}/vendor-action`,
      )
      .send({ action: 'accept' });
    expect(confirm1.status).toBe(200);

    const confirm2 = await authed(appFor(db, 'vendor1'))
      .post(
        `/v1/marketplace/bookings/${b2.body.booking.bookingId}/vendor-action`,
      )
      .send({ action: 'accept' });
    expect(confirm2.status).toBe(409);
    expect(confirm2.body.error.code).toBe('BOOKING_CONFLICT');
  });

  it('prevents delete while a booking is active; allows it after cancel', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db);
    const created = await createBookingFor(db, 'customer', listingId);

    const blocked = await authed(appFor(db, 'vendor1')).delete(
      `/v1/vendor/listings/${listingId}`,
    );
    expect(blocked.status).toBe(409);
    expect(blocked.body.error.code).toBe('LISTING_HAS_ACTIVE_BOOKINGS');

    await authed(appFor(db, 'customer'))
      .post(
        `/v1/marketplace/bookings/${created.body.booking.bookingId}/customer-action`,
      )
      .send({ action: 'cancel' });

    const del = await authed(appFor(db, 'vendor1')).delete(
      `/v1/vendor/listings/${listingId}`,
    );
    expect(del.status).toBe(200);
  });

  it('suspending a vendor mid-workflow blocks further vendor actions', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    seedUser(db, 'customer');
    const listingId = await listingOf(db);
    const created = await createBookingFor(db, 'customer', listingId);
    const id = created.body.booking.bookingId;

    // Admin suspends the vendor.
    db.seed('users', 'vendor1', {
      ...(db.getDoc('users', 'vendor1') ?? {}),
      vendorApplications: { service: { status: 'suspended' } },
    });

    const act = await authed(appFor(db, 'vendor1'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'quote', amount: 100 });
    expect(act.status).toBe(403);
    expect(act.body.error.code).toBe('VENDOR_SUSPENDED');
  });

  it('cross-vendor and cross-customer access to bookings returns 404', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    approvedVendor(db, 'vendor2', ['service']);
    seedUser(db, 'customer');
    seedUser(db, 'stranger');
    const listingId = await listingOf(db);
    const created = await createBookingFor(db, 'customer', listingId);
    const id = created.body.booking.bookingId;

    const v2Act = await authed(appFor(db, 'vendor2'))
      .post(`/v1/marketplace/bookings/${id}/vendor-action`)
      .send({ action: 'accept' });
    expect(v2Act.status).toBe(404);

    const strangerGet = await authed(appFor(db, 'stranger')).get(
      `/v1/marketplace/bookings/${id}`,
    );
    expect(strangerGet.status).toBe(404);

    // Customer can read their own; vendor can read their inbox copy.
    const custGet = await authed(appFor(db, 'customer')).get(
      `/v1/marketplace/bookings/${id}`,
    );
    expect(custGet.status).toBe(200);
    const vendorGet = await authed(appFor(db, 'vendor1')).get(
      `/v1/marketplace/bookings/${id}`,
    );
    expect(vendorGet.status).toBe(200);
  });

  it('lists bookings by role — vendor inbox vs customer history', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    approvedVendor(db, 'vendor2', ['cargo']);
    seedUser(db, 'customer');
    const sId = await listingOf(db, 'vendor1', SERVICE_BODY);
    const cId = await listingOf(db, 'vendor2', CARGO_BODY);
    await createBookingFor(db, 'customer', sId, 'bk-key-1');
    await createBookingFor(db, 'customer', cId, 'bk-key-2');

    const vendorInbox = await authed(appFor(db, 'vendor1')).get(
      '/v1/marketplace/bookings?role=vendor',
    );
    expect(vendorInbox.body.bookings).toHaveLength(1);
    expect(vendorInbox.body.bookings[0].type).toBe('service');

    const custList = await authed(appFor(db, 'customer')).get(
      '/v1/marketplace/bookings',
    );
    expect(custList.body.bookings).toHaveLength(2);
  });

  it('requires Idempotency-Key on listing creation', async () => {
    const db = memoryDb();
    approvedVendor(db, 'vendor1', ['service']);
    const res = await authed(appFor(db, 'vendor1'))
      .post('/v1/vendor/listings')
      .send(SERVICE_BODY);
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('IDEMPOTENCY_KEY_REQUIRED');
  });
});
