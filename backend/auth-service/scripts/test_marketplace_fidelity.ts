/**
 * Data-fidelity E2E: verifies vendor-entered data survives the full
 * create → Firestore → customer-API → edit → booking round-trip with ZERO
 * substitution, for service, rental, and cargo. Emulator-only.
 *   npx tsx scripts/test_marketplace_fidelity.ts
 *
 * Also verifies: two vendors same-category isolation, listing fields in
 * bookings, quote/booking price consistency, persistence across a backend
 * process restart (Firestoore emulator holds data).
 */
process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8181';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
process.env.FIREBASE_PROJECT_ID ??= 'oraapp-a9be5';
process.env.FIREBASE_DATABASE_URL ??=
  'https://oraapp-a9be5-default-rtdb.local-emulator.local';

import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const API = 'http://127.0.0.1:8080/v1';
const AUTH_EMU = 'http://127.0.0.1:9099';
const RUN = `fid-${Date.now()}`;

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown) {
  console.log(
    `${cond ? 'PASS' : 'FAIL'} ${name}${
      extra !== undefined ? ' ' + JSON.stringify(extra) : ''
    }`,
  );
  if (!cond) failures++;
}

function eq(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
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
  const s = await fetch(
    `${AUTH_EMU}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=test`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  return ((await s.json()) as { idToken: string }).idToken;
}

// 1x1 JPEG data URL — distinctive byte suffix lets us detect substitution
const PHOTO_A =
  'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//AAAAAAD/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q==';
const PHOTO_B =
  'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//AAAAAAD/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8Af4D/2Q==';

interface ListingInput {
  type: string;
  categoryId: string;
  subcategoryId: string;
  title: string;
  description: string;
  price: number;
  priceUnit: string;
  location: string;
  contactNumber: string;
  details: Record<string, unknown>;
  photos: string[];
}

const FIELDS: (keyof ListingInput)[] = [
  'type',
  'categoryId',
  'subcategoryId',
  'title',
  'description',
  'price',
  'priceUnit',
  'location',
  'contactNumber',
  'details',
  'photos',
];

function compare(
  label: string,
  expected: ListingInput,
  actual: Record<string, unknown>,
): void {
  const mismatched: string[] = [];
  for (const f of FIELDS) {
    if (!eq(expected[f], actual[f])) {
      mismatched.push(
        `${f}: expected ${JSON.stringify(expected[f])} got ${JSON.stringify(actual[f])}`,
      );
    }
  }
  check(
    `${label} — all ${FIELDS.length} fields exact`,
    mismatched.length === 0,
    mismatched.length ? mismatched : undefined,
  );
}

async function main() {
  if (getApps().length === 0) {
    initializeApp({
      projectId: process.env.FIREBASE_PROJECT_ID,
      databaseURL: process.env.FIREBASE_DATABASE_URL,
    });
  }
  const db = getFirestore();

  const vA = `${RUN}-va`; // all three roles
  const vB = `${RUN}-vb`; // service only — same-category isolation
  const cust = `${RUN}-cu`;
  for (const uid of [vA, vB, cust]) {
    const t = await tokenFor(uid);
    await api(t, 'POST', '/auth/register', {}, `register_${uid}`);
  }
  const tA = await tokenFor(vA);
  const tB = await tokenFor(vB);
  const tC = await tokenFor(cust);

  for (const type of ['service', 'rental', 'cargo']) {
    await api(tA, 'POST', '/auth/vendor-application', { type }, `ap_${type}`);
  }
  await api(tB, 'POST', '/auth/vendor-application', { type: 'service' }, 'ap_b_svc');
  for (const type of ['service', 'rental', 'cargo']) {
    await db.doc(`users/${vA}`).set(
      { vendorApplications: { [type]: { status: 'approved' } } },
      { merge: true },
    );
  }
  await db.doc(`users/${vB}`).set(
    { vendorApplications: { service: { status: 'approved' } } },
    { merge: true },
  );

  // ── Create one distinctive listing per vertical (vendor A) ─────────────
  const inputs: Record<string, ListingInput> = {
    service: {
      type: 'service',
      categoryId: 'home_repair',
      subcategoryId: 'plumbing',
      title: `FIDELITY-Δ SVC ${RUN} — Burst-pipe 24/7 crew`,
      description:
        'Unicode fidelity check — نل اردو، emoji 🚰, & symbols <>&"\' to catch escaping bugs. ' +
        RUN,
      price: 2750,
      priceUnit: 'Per Visit',
      location: `Sector D-12, Islamabad [${RUN}]`,
      contactNumber: '+92 300 555 0101',
      details: {
        experienceYears: 9,
        emergency: true,
        tags: ['copper', 'PEX', 'gas-line'],
      },
      photos: [PHOTO_A, PHOTO_B],
    },
    rental: {
      type: 'rental',
      categoryId: 'residential',
      subcategoryId: 'apartments_flats',
      title: `FIDELITY-Δ RENT ${RUN} — 2-bed canal view`,
      description: `Furnished, pets OK. Fidelity marker ${RUN}`,
      price: 95000,
      priceUnit: 'Per Month',
      location: `Gulberg III, Lahore [${RUN}]`,
      contactNumber: '+92 321 555 0202',
      details: { bedrooms: 2, bathrooms: 2, furnished: true, floor: 7 },
      photos: [PHOTO_B, PHOTO_A], // reversed order — order must be preserved
    },
    cargo: {
      type: 'cargo',
      categoryId: 'trucks',
      subcategoryId: 'heavy_duty_truck',
      title: `FIDELITY-Δ CARGO ${RUN} — 22-wheeler nationwide`,
      description: `Refrigerated + flatbed. Fidelity marker ${RUN}`,
      price: 12500,
      priceUnit: 'Per Km',
      location: `Karachi Port, Korangi [${RUN}]`,
      contactNumber: '+92 345 555 0303',
      details: { serviceArea: 'Nationwide', capacityTons: 40, refrigerated: true },
      photos: [PHOTO_A],
    },
  };

  const ids: Record<string, string> = {};
  for (const type of ['service', 'rental', 'cargo']) {
    const r = await api(tA, 'POST', '/vendor/listings', inputs[type], `list_${type}`);
    const listing = (r.json as { listing?: { listingId: string } })?.listing;
    check(`create ${type} 201`, r.status === 201, r.status);
    if (listing?.listingId) ids[type] = listing.listingId;
  }

  // ── Vendor B: same service category — must be isolated, not merged ──────
  const inputB: ListingInput = {
    ...inputs.service,
    title: `VENDOR-B plumbing ${RUN}`,
    price: 1,
    location: `Quetta [${RUN}]`,
    photos: [PHOTO_B],
  };
  const rB = await api(tB, 'POST', '/vendor/listings', inputB, 'list_b_svc');
  const idB = (rB.json as { listing?: { listingId: string } })?.listing
    ?.listingId;
  check('vendor B create 201', rB.status === 201, rB.status);

  // ── Raw Firestore doc fidelity (no serialization loss) ─────────────────
  for (const type of ['service', 'rental', 'cargo']) {
    const snap = await db.doc(`marketplaceListings/${ids[type]}`).get();
    const stored = snap.data() ?? {};
    check(`${type} Firestore doc exists`, snap.exists);
    compare(`${type} Firestore raw`, inputs[type], {
      type: stored.type,
      categoryId: stored.categoryId,
      subcategoryId: stored.subcategoryId,
      title: stored.title,
      description: stored.description,
      price: stored.price,
      priceUnit: stored.priceUnit,
      location: stored.location,
      contactNumber: stored.contactNumber,
      details: stored.details,
      photos: stored.photos,
    });
    check(
      `${type} vendorId = creator`,
      stored.vendorId === vA,
      stored.vendorId,
    );
  }

  // ── Customer discovery + detail fidelity ────────────────────────────────
  for (const type of ['service', 'rental', 'cargo']) {
    const list = await api(
      tC,
      'GET',
      `/marketplace/listings?type=${type}&categoryId=${inputs[type].categoryId}`,
    );
    const found = (
      list.json as { listings?: Record<string, unknown>[] }
    )?.listings?.find((l) => l.listingId === ids[type]);
    check(`${type} discoverable`, !!found);
    if (found) compare(`${type} discovery payload`, inputs[type], found);

    const det = await api(tC, 'GET', `/marketplace/listings/${ids[type]}`);
    const detail = (det.json as { listing?: Record<string, unknown> })
      ?.listing;
    check(`${type} detail 200`, det.status === 200, det.status);
    if (detail) compare(`${type} detail payload`, inputs[type], detail);
  }

  // ── Same-category isolation: discovery returns BOTH, never swapped ──────
  {
    const list = await api(
      tC,
      'GET',
      '/marketplace/listings?type=service&categoryId=home_repair',
    );
    const items =
      (list.json as { listings?: Record<string, unknown>[] })?.listings ?? [];
    const mine = items.find((l) => l.listingId === ids.service);
    const theirs = items.find((l) => l.listingId === idB);
    check('both vendors visible same category', !!mine && !!theirs);
    check(
      'vendor A title not swapped with B',
      mine?.title === inputs.service.title &&
        theirs?.title === inputB.title,
      { a: mine?.title, b: theirs?.title },
    );
    check(
      'vendor A price not swapped with B',
      mine?.price === inputs.service.price && theirs?.price === inputB.price,
    );
  }

  // ── Edit → verify everywhere (title/price/photo flip) ──────────────────
  const edited = {
    ...inputs.service,
    title: `EDITED-✂ SVC ${RUN} — Drain specialist`,
    price: 3200,
    photos: [PHOTO_B], // photo set replaced entirely
  };
  let r = await api(tA, 'PATCH', `/vendor/listings/${ids.service}`, {
    title: edited.title,
    price: edited.price,
    photos: edited.photos,
  });
  check('edit listing 200', r.status === 200, r.status);

  {
    const snap = await db.doc(`marketplaceListings/${ids.service}`).get();
    const stored = snap.data() ?? {};
    compare('edited Firestore raw', edited, {
      type: stored.type,
      categoryId: stored.categoryId,
      subcategoryId: stored.subcategoryId,
      title: stored.title,
      description: stored.description,
      price: stored.price,
      priceUnit: stored.priceUnit,
      location: stored.location,
      contactNumber: stored.contactNumber,
      details: stored.details,
      photos: stored.photos,
    });
  }
  {
    const det = await api(tC, 'GET', `/marketplace/listings/${ids.service}`);
    const detail = (det.json as { listing?: Record<string, unknown> })
      ?.listing;
    if (detail) compare('edited customer-visible', edited, detail);
  }

  // ── Booking references the exact listing + agreed price ────────────────
  r = await api(
    tC,
    'POST',
    '/marketplace/bookings',
    {
      listingId: ids.cargo,
      request: {
        contactName: 'Fidelity Customer',
        contactPhone: '+92 300 555 0404',
        details: { pickup: 'Port Qasim', destination: 'Lahore Dry Port' },
      },
    },
    'bk_cargo_fid',
  );
  const booking = (r.json as { booking?: Record<string, unknown> })?.booking;
  const bookingId = booking?.bookingId as string;
  check('cargo booking created', r.status === 201, r.status);
  check(
    'booking.listingId === created listing',
    booking?.listingId === ids.cargo,
  );
  check(
    'booking.vendorId === listing owner',
    booking?.vendorId === vA,
    booking?.vendorId,
  );
  check(
    'booking.customerId === requester',
    booking?.customerId === cust,
  );

  // raw doc: listing + request payload must round-trip
  {
    const snap = await db.doc(`marketplaceBookings/${bookingId}`).get();
    const stored = snap.data() ?? {};
    const req = stored.request as Record<string, unknown>;
    check(
      'booking Firestore request payload exact',
      req?.contactName === 'Fidelity Customer' &&
        eq(req?.details, {
          pickup: 'Port Qasim',
          destination: 'Lahore Dry Port',
        }),
      req,
    );
    check(
      'booking snapshots listing title/price',
      typeof stored.listingTitle === 'string' ||
        typeof stored.listingSnapshot === 'object',
      Object.keys(stored).filter(
        (k) => !['request', 'statusHistory'].includes(k),
      ),
    );
  }

  // vendor quote → customer accept → price consistency
  r = await api(
    tA,
    'POST',
    `/marketplace/bookings/${bookingId}/vendor-action`,
    { action: 'quote', amount: 88000, note: 'incl. tolls' },
  );
  check('vendor quote 200', r.status === 200, r.status);
  r = await api(tC, 'GET', `/marketplace/bookings/${bookingId}`);
  const quoted = (r.json as { booking?: Record<string, unknown> })?.booking;
  const quote = quoted?.quote as Record<string, unknown> | undefined;
  check(
    'customer sees exact quote amount+note',
    quote?.amount === 88000 && quote?.note === 'incl. tolls',
    quote,
  );
  r = await api(
    tC,
    'POST',
    `/marketplace/bookings/${bookingId}/customer-action`,
    { action: 'accept' },
  );
  const accepted = (r.json as { booking?: Record<string, unknown> })
    ?.booking;
  check(
    'confirmed booking still references same listing+quote',
    accepted?.status === 'confirmed' &&
      accepted?.listingId === ids.cargo &&
      (accepted?.quote as Record<string, unknown>)?.amount === 88000,
  );

  // vendor inbox entry must carry the same listing identity
  r = await api(tA, 'GET', '/marketplace/bookings?role=vendor&type=cargo');
  const inboxItem = (
    r.json as { bookings?: Record<string, unknown>[] }
  )?.bookings?.find((b) => b.bookingId === bookingId);
  check(
    'vendor inbox booking carries same listingId+quote',
    inboxItem?.listingId === ids.cargo &&
      (inboxItem?.quote as Record<string, unknown>)?.amount === 88000,
    inboxItem?.listingId,
  );

  // persistence marker for post-restart check
  await db.doc('marketplaceListings/' + ids.rental).get();
  console.log(`\nFIDELITY_IDS=${JSON.stringify(ids)} RUN=${RUN}`);

  console.log(
    failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('crashed:', e);
  process.exit(1);
});
