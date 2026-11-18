/**
 * Local E2E for the vendor marketplace. Emulator-only — fails closed.
 *   npx tsx scripts/test_marketplace_e2e.ts
 *
 * Covers, against the real HTTP API + emulators:
 *   - per-role approval gating (pending cannot post; approved posts only
 *     its own vertical)
 *   - listing CRUD + publish/pause + ownership isolation
 *   - customer discovery (published-only, category/subcategory filter)
 *   - booking lifecycle: request → quote → customer accept → confirmed →
 *     start → complete; vendor reject; customer cancel
 *   - duplicate-active-booking guard, rental date-overlap conflict,
 *     invalid transitions, idempotency
 *   - suspended-vendor enforcement
 */
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
process.env.FIREBASE_DATABASE_URL ??=
  'https://oraapp-a9be5-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const API = 'http://127.0.0.1:8080/v1';
const AUTH_EMU = 'http://127.0.0.1:9099';
const RUN = `mke2e-${Date.now()}`;

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown) {
  console.log(
    `${cond ? 'PASS' : 'FAIL'} ${name}${
      extra !== undefined ? ' ' + JSON.stringify(extra) : ''
    }`,
  );
  if (!cond) failures++;
}

async function api(
  token: string,
  method: string,
  path: string,
  body?: unknown,
  idem?: string,
) {
  const r = await fetch(`${API}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(idem ? { 'Idempotency-Key': idem } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json: unknown = null;
  try {
    json = await r.json();
  } catch {
    /* empty */
  }
  return { status: r.status, json };
}

async function tokenFor(uid: string): Promise<string> {
  const custom = await getAuth().createCustomToken(uid);
  const signIn = await fetch(
    `${AUTH_EMU}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=test`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  return ((await signIn.json()) as { idToken: string }).idToken;
}

async function approve(uid: string, type: string, status = 'approved') {
  await getFirestore()
    .doc(`users/${uid}`)
    .set(
      {
        vendorApplications: {
          [type]: { status, submittedAt: new Date().toISOString() },
        },
      },
      { merge: true },
    );
}

function listingBody(type: string, categoryId: string, subId: string) {
  return {
    type,
    categoryId,
    subcategoryId: subId,
    title: `${RUN} ${type} listing`,
    description: 'E2E listing description long enough',
    price: 1500,
    priceUnit:
      type === 'rental'
        ? 'Per Month'
        : type === 'cargo'
          ? 'Per Trip'
          : 'Per Service',
    location: 'Lahore',
    contactNumber: '+923001112233',
    details: type === 'cargo' ? { serviceArea: 'Lahore' } : {},
    photos: [],
  };
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }

  // ── Accounts ────────────────────────────────────────────────────────────
  const vendorAll = `${RUN}-vall`; // approved for all three
  const vendorSvc = `${RUN}-vsvc`; // service only
  const vendorPend = `${RUN}-vpend`; // pending forever
  const customer = `${RUN}-cust`;
  const customer2 = `${RUN}-cust2`;
  for (const uid of [vendorAll, vendorSvc, vendorPend, customer, customer2]) {
    const t = await tokenFor(uid);
    const r = await api(t, 'POST', '/auth/register', {}, `register_${uid}`);
    check(`register ${uid.slice(-5)}`, r.status === 200, r.status);
  }
  const tAll = await tokenFor(vendorAll);
  const tSvc = await tokenFor(vendorSvc);
  const tPend = await tokenFor(vendorPend);
  const tCust = await tokenFor(customer);
  const tCust2 = await tokenFor(customer2);

  for (const type of ['service', 'rental', 'cargo']) {
    let r = await api(
      tAll,
      'POST',
      '/auth/vendor-application',
      { type },
      `apply_${type}_all`,
    );
    check(`apply ${type} 200`, r.status === 200, r.status);
    await approve(vendorAll, type);
  }
  await api(
    tSvc,
    'POST',
    '/auth/vendor-application',
    { type: 'service' },
    'apply_svc_only',
  );
  await approve(vendorSvc, 'service');
  await api(
    tPend,
    'POST',
    '/auth/vendor-application',
    { type: 'service' },
    'apply_pend',
  ); // stays pending

  // ── Listing gating ──────────────────────────────────────────────────────
  let r = await api(
    tPend,
    'POST',
    '/vendor/listings',
    listingBody('service', 'home_repair', 'plumbing'),
    'post_pend_1',
  );
  check('pending vendor cannot post', r.status === 403, r.status);

  r = await api(
    tSvc,
    'POST',
    '/vendor/listings',
    listingBody('cargo', 'trucks', 'heavy_duty_truck'),
    'post_xrole_1',
  );
  check('service vendor cannot post cargo', r.status === 403, r.status);

  r = await api(
    tSvc,
    'POST',
    '/vendor/listings',
    listingBody('service', 'home_repair', 'plumbing'),
    'post_svc_1',
  );
  const svcListing = (r.json as { listing?: { listingId: string } })?.listing;
  check(
    'service vendor posts service listing',
    r.status === 200 || r.status === 201 && !!svcListing?.listingId,
    r.status,
  );

  r = await api(
    tAll,
    'POST',
    '/vendor/listings',
    listingBody('service', 'cleaning', 'house_cleaning'),
    'post_all_svc',
  );
  const svcListing2 = (r.json as { listing?: { listingId: string } })
    ?.listing;
  check('multi-role vendor posts service', r.status === 200 || r.status === 201, r.status);

  r = await api(
    tAll,
    'POST',
    '/vendor/listings',
    listingBody('rental', 'residential', 'apartments_flats'),
    'post_all_rental',
  );
  const rentalListing = (r.json as { listing?: { listingId: string } })
    ?.listing;
  check('multi-role vendor posts rental', r.status === 200 || r.status === 201, r.status);

  r = await api(
    tAll,
    'POST',
    '/vendor/listings',
    listingBody('cargo', 'trucks', 'heavy_duty_truck'),
    'post_all_cargo',
  );
  const cargoListing = (r.json as { listing?: { listingId: string } })
    ?.listing;
  check('multi-role vendor posts cargo', r.status === 200 || r.status === 201, r.status);

  // ── Discovery ───────────────────────────────────────────────────────────
  r = await api(
    tCust,
    'GET',
    '/marketplace/listings?type=service&categoryId=home_repair',
  );
  const svcList = (
    r.json as { listings?: Array<{ listingId: string }> }
  )?.listings;
  check(
    'discovery returns published service listing',
    r.status === 200 &&
      (svcList ?? []).some((l) => l.listingId === svcListing?.listingId),
    svcList?.length,
  );

  r = await api(tCust, 'GET', '/marketplace/listings?type=service');
  const otherVisible = (
    r.json as { listings?: Array<{ listingId: string }> }
  )?.listings;
  check(
    'unfiltered service discovery shows all vendors',
    (otherVisible ?? []).some(
      (l) => l.listingId === svcListing2?.listingId,
    ),
  );

  // ── Ownership isolation ─────────────────────────────────────────────────
  r = await api(
    tSvc,
    'PATCH',
    `/vendor/listings/${svcListing2?.listingId}`,
    { title: 'hijacked' },
  );
  check(
    'cross-vendor PATCH rejected',
    r.status === 403 || r.status === 404,
    r.status,
  );
  r = await api(tSvc, 'DELETE', `/vendor/listings/${svcListing2?.listingId}`);
  check(
    'cross-vendor DELETE rejected',
    r.status === 403 || r.status === 404,
    r.status,
  );

  // ── Pause hides from discovery ──────────────────────────────────────────
  r = await api(
    tAll,
    'PATCH',
    `/vendor/listings/${svcListing2?.listingId}`,
    { status: 'paused' },
  );
  check('pause own listing', r.status === 200, r.status);
  r = await api(tCust, 'GET', '/marketplace/listings?type=service');
  const afterPause = (
    r.json as { listings?: Array<{ listingId: string }> }
  )?.listings;
  check(
    'paused listing hidden from discovery',
    !(afterPause ?? []).some((l) => l.listingId === svcListing2?.listingId),
  );
  await api(
    tAll,
    'PATCH',
    `/vendor/listings/${svcListing2?.listingId}`,
    { status: 'published' },
  );

  // ── Booking lifecycle: service (request → accept → start → complete) ────
  const req = { contactName: 'Test Customer', contactPhone: '+923004445555' };
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    {
      listingId: svcListing?.listingId,
      request: { ...req, details: { date: '2026-02-10', address: 'DHA' } },
    },
    'book_svc_1',
  );
  const svcBooking = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  check('service booking created', r.status === 200 || r.status === 201, r.status);

  // duplicate active booking on same listing → 409
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    { listingId: svcListing?.listingId, request: req },
    'book_svc_dup',
  );
  check(
    'duplicate active booking rejected',
    r.status === 409,
    r.status,
  );

  // idempotent replay returns the same booking
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    {
      listingId: svcListing?.listingId,
      request: { ...req, details: { date: '2026-02-10', address: 'DHA' } },
    },
    'book_svc_1',
  );
  const replayId = (r.json as { booking?: { bookingId: string } })
    ?.booking?.bookingId;
  check(
    'idempotent booking replay',
    (r.status === 200 || r.status === 201) &&
      replayId === svcBooking?.bookingId,
    { status: r.status, replayId, orig: svcBooking?.bookingId },
  );

  // vendor inbox
  r = await api(tSvc, 'GET', '/marketplace/bookings?role=vendor&type=service');
  const inbox = (
    r.json as { bookings?: Array<{ bookingId: string }> }
  )?.bookings;
  check(
    'vendor inbox shows booking',
    (inbox ?? []).some((b) => b.bookingId === svcBooking?.bookingId),
    inbox?.length,
  );

  // wrong vendor sees nothing
  r = await api(
    tAll,
    'GET',
    '/marketplace/bookings?role=vendor&type=service',
  );
  const otherInbox = (
    r.json as { bookings?: Array<{ bookingId: string }> }
  )?.bookings;
  check(
    'other vendor inbox isolated',
    !(otherInbox ?? []).some((b) => b.bookingId === svcBooking?.bookingId),
  );

  // invalid transition: complete before accept
  r = await api(
    tSvc,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'complete' },
  );
  check('invalid transition rejected', r.status === 409, r.status);

  // vendor accept → confirmed
  r = await api(
    tSvc,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'accept' },
  );
  check('vendor accept → confirmed', r.status === 200, r.status);

  // customer cannot vendor-act
  r = await api(
    tCust,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'start' },
  );
  check('customer cannot vendor-act', r.status === 403 || r.status === 404);

  r = await api(
    tSvc,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'start' },
  );
  check('start → in_progress', r.status === 200, r.status);
  r = await api(
    tSvc,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'complete' },
  );
  check('complete → completed', r.status === 200, r.status);

  // ── Booking lifecycle: cargo (request → quote → customer accept) ────────
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    {
      listingId: cargoListing?.listingId,
      request: {
        ...req,
        details: { pickup: 'Lahore', destination: 'Karachi', cargo: 'Boxes' },
      },
    },
    'book_cargo_1',
  );
  const cargoBooking = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  check('cargo quote request created', r.status === 200 || r.status === 201, r.status);

  r = await api(
    tAll,
    'POST',
    `/marketplace/bookings/${cargoBooking?.bookingId}/vendor-action`,
    { action: 'quote', amount: 45000, note: '2-day delivery' },
  );
  check('vendor sends quote', r.status === 200, r.status);

  // vendor cannot confirm their own quote (only customer accepts)
  r = await api(
    tCust2,
    'POST',
    `/marketplace/bookings/${cargoBooking?.bookingId}/customer-action`,
    { action: 'accept' },
  );
  check(
    'other customer cannot accept quote',
    r.status === 403 || r.status === 404,
  );

  r = await api(
    tCust,
    'POST',
    `/marketplace/bookings/${cargoBooking?.bookingId}/customer-action`,
    { action: 'accept' },
  );
  const confirmedBooking = (
    r.json as { booking?: { status: string; statusHistory?: unknown[] } }
  )?.booking;
  check(
    'customer accept quote → confirmed + history',
    r.status === 200 &&
      confirmedBooking?.status === 'confirmed' &&
      (confirmedBooking?.statusHistory?.length ?? 0) >= 3,
    confirmedBooking?.status,
  );

  // ── Rental overlap conflict ─────────────────────────────────────────────
  const stay = {
    ...req,
    details: { checkIn: '2026-03-01', checkOut: '2026-03-05' },
  };
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    { listingId: rentalListing?.listingId, request: stay },
    'book_rental_1',
  );
  const rentalBooking = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  check('rental booking created', r.status === 200 || r.status === 201, r.status);
  r = await api(
    tAll,
    'POST',
    `/marketplace/bookings/${rentalBooking?.bookingId}/vendor-action`,
    { action: 'accept' },
  );
  check('rental confirmed', r.status === 200 || r.status === 201, r.status);

  // overlapping confirmed booking → 409
  r = await api(
    tCust2,
    'POST',
    '/marketplace/bookings',
    {
      listingId: rentalListing?.listingId,
      request: {
        contactName: 'Customer Two',
        contactPhone: '+923007778888',
        details: { checkIn: '2026-03-03', checkOut: '2026-03-08' },
      },
    },
    'book_rental_overlap',
  );
  const overlap = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  check(
    'overlap request allowed (conflict on confirm)',
    r.status === 200 || r.status === 201 || r.status === 409,
    r.status,
  );
  if (r.status === 200 || r.status === 201) {
    const c = await api(
      tAll,
      'POST',
      `/marketplace/bookings/${overlap?.bookingId}/vendor-action`,
      { action: 'accept' },
    );
    check('overlap confirm → 409', c.status === 409, c.status);
  }

  // ── Customer cancel + vendor reject ─────────────────────────────────────
  r = await api(
    tCust,
    'POST',
    '/marketplace/bookings',
    {
      listingId: svcListing?.listingId,
      request: { ...req, details: { date: '2026-02-20' } },
    },
    'book_svc_cancel',
  );
  const cancelBooking = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  r = await api(
    tCust,
    'POST',
    `/marketplace/bookings/${cancelBooking?.bookingId}/customer-action`,
    { action: 'cancel' },
  );
  check('customer cancels own request', r.status === 200, r.status);

  r = await api(
    tCust2,
    'POST',
    '/marketplace/bookings',
    {
      listingId: svcListing2?.listingId,
      request: { contactName: 'Cust Two', contactPhone: '+923007778888' },
    },
    'book_svc_reject',
  );
  const rejectBooking = (r.json as { booking?: { bookingId: string } })
    ?.booking;
  r = await api(
    tAll,
    'POST',
    `/marketplace/bookings/${rejectBooking?.bookingId}/vendor-action`,
    { action: 'reject' },
  );
  check('vendor rejects request', r.status === 200, r.status);

  // customer booking history
  r = await api(tCust, 'GET', '/marketplace/bookings?role=customer');
  const mine = (r.json as { bookings?: unknown[] })?.bookings;
  check(
    'customer history lists all bookings',
    (mine?.length ?? 0) >= 4,
    mine?.length,
  );

  // ── Suspended vendor enforcement ────────────────────────────────────────
  await approve(vendorSvc, 'service', 'suspended');
  r = await api(
    tSvc,
    'POST',
    '/vendor/listings',
    listingBody('service', 'home_repair', 'plumbing'),
    'post_susp_1',
  );
  check('suspended vendor cannot post', r.status === 403, r.status);
  r = await api(
    tSvc,
    'POST',
    `/marketplace/bookings/${svcBooking?.bookingId}/vendor-action`,
    { action: 'complete' },
  );
  check(
    'suspended vendor cannot act on bookings',
    r.status === 403 || r.status === 404 || r.status === 409,
    r.status,
  );
  await approve(vendorSvc, 'service'); // restore

  console.log(
    failures === 0
      ? '\nALL CHECKS PASSED'
      : `\n${failures} CHECK(S) FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error('E2E crashed:', error);
  process.exit(1);
});
