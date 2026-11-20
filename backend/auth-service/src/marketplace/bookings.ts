import { randomUUID } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import {
  assertWalletEligibleInsideTx,
  chargeCommissionInsideTx,
} from '../wallet/wallet';
import { WalletError } from '../wallet/types';
import { getPublishedListing, requireApprovedVendor } from './listings';
import {
  ACTIVE_BOOKING_STATUSES,
  MARKETPLACE_BOOKINGS,
  MARKETPLACE_LISTINGS,
  MarketplaceError,
  type BookingStatus,
  type MarketplaceBooking,
} from './types';

const USERS = 'users';
const MAX_REQUEST_BYTES = 8 * 1024;
const MAX_REQUEST_KEYS = 30;
const MAX_STRING_LEN = 2000;
const QUOTE_MAX = 100_000_000;
const LIST_LIMIT = 50;

function err(code: string, httpStatus: number, message: string): never {
  throw new MarketplaceError(code, httpStatus, message);
}

function isObj(v: unknown): v is Record<string, unknown> {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

/**
 * Customer request payload: contactName + contactPhone required, everything
 * else rides in a bounded free-form `details` map (route, dates, cargo…).
 */
function normalizeRequest(value: unknown): Record<string, unknown> {
  if (!isObj(value)) {
    err('VALIDATION_ERROR', 400, 'request must be an object.');
  }
  const contactName = value.contactName;
  const contactPhone = value.contactPhone;
  if (
    typeof contactName !== 'string' ||
    contactName.trim().length < 2 ||
    contactName.trim().length > 80
  ) {
    err('VALIDATION_ERROR', 400, 'request.contactName is required (2–80 chars).');
  }
  if (
    typeof contactPhone !== 'string' ||
    contactPhone.trim().length < 5 ||
    contactPhone.trim().length > 24
  ) {
    err(
      'VALIDATION_ERROR',
      400,
      'request.contactPhone is required (5–24 chars).',
    );
  }
  const out: Record<string, unknown> = {
    contactName: contactName.trim(),
    contactPhone: contactPhone.trim(),
  };
  for (const [key, val] of Object.entries(value)) {
    if (key === 'contactName' || key === 'contactPhone') continue;
    if (Object.keys(out).length >= MAX_REQUEST_KEYS) break;
    if (typeof key !== 'string' || key.length === 0 || key.length > 60) {
      continue;
    }
    if (typeof val === 'string') {
      const t = val.trim();
      if (t.length > 0 && t.length <= MAX_STRING_LEN) out[key] = t;
    } else if (
      (typeof val === 'number' && Number.isFinite(val)) ||
      typeof val === 'boolean'
    ) {
      out[key] = val;
    } else if (Array.isArray(val)) {
      const items = val
        .slice(0, 24)
        .filter((i): i is string => typeof i === 'string')
        .map((i) => i.trim())
        .filter((i) => i.length > 0 && i.length <= MAX_STRING_LEN);
      if (items.length > 0) out[key] = items;
    } else if (isObj(val)) {
      // One nested level (e.g. details{checkIn, checkOut}) — bounded.
      const nested: Record<string, unknown> = {};
      for (const [nk, nv] of Object.entries(val).slice(0, MAX_REQUEST_KEYS)) {
        if (typeof nv === 'string' && nv.trim().length <= MAX_STRING_LEN) {
          nested[nk] = nv.trim();
        } else if (
          (typeof nv === 'number' && Number.isFinite(nv)) ||
          typeof nv === 'boolean'
        ) {
          nested[nk] = nv;
        }
      }
      if (Object.keys(nested).length > 0) out[key] = nested;
    }
  }
  if (JSON.stringify(out).length > MAX_REQUEST_BYTES) {
    err('VALIDATION_ERROR', 400, 'request payload too large.');
  }
  return out;
}

function toBooking(id: string, data: Record<string, unknown>): MarketplaceBooking {
  const quote = isObj(data.quote)
    ? {
        amount: Number(data.quote.amount),
        ...(typeof data.quote.note === 'string'
          ? { note: data.quote.note }
          : {}),
        sentAt: String(data.quote.sentAt),
      }
    : undefined;
  const commission = isObj(data.commission)
    ? {
        points: Number(data.commission.points),
        amountMinor: Number(data.commission.amountMinor),
        grossMinor: Number(data.commission.grossMinor),
        bps: Number(data.commission.bps),
        ledgerEntryId: String(data.commission.ledgerEntryId),
      }
    : undefined;
  return {
    bookingId: id,
    listingId: String(data.listingId),
    listingTitle: String(data.listingTitle),
    type: data.type as MarketplaceBooking['type'],
    vendorId: String(data.vendorId),
    customerId: String(data.customerId),
    customerName: String(data.customerName),
    status: data.status as BookingStatus,
    request: isObj(data.request) ? data.request : {},
    ...(quote ? { quote } : {}),
    ...(commission ? { commission } : {}),
    statusHistory: Array.isArray(data.statusHistory)
      ? (data.statusHistory as MarketplaceBooking['statusHistory'])
      : [],
    createdAt: String(data.createdAt),
    updatedAt: String(data.updatedAt),
    version: Number(data.version ?? 0),
  };
}

async function customerName(
  db: Firestore,
  caller: AuthenticatedCaller,
): Promise<string> {
  const snap = await db.collection(USERS).doc(caller.uid).get();
  const data = snap.data();
  const name = data?.displayName;
  return typeof name === 'string' && name.trim().length > 0
    ? name
    : 'ORA Customer';
}

/**
 * Creates a booking request. Guards, all inside one transaction:
 *  - listing must be published (re-checked inside the tx so a vendor cannot
 *    race a delete/pause against a new request)
 *  - a customer cannot book their own listing
 *  - at most one ACTIVE booking per (customer, listing) — duplicate requests
 *    are 409, but a retry with the same Idempotency-Key returns the original
 *    booking instead.
 */
export async function createBooking(
  db: Firestore,
  caller: AuthenticatedCaller,
  listingId: unknown,
  requestRaw: unknown,
  idempotencyKey: string,
  now: Date,
): Promise<MarketplaceBooking> {
  if (typeof listingId !== 'string' || listingId.trim() === '') {
    err('VALIDATION_ERROR', 400, 'listingId is required.');
  }
  const request = normalizeRequest(requestRaw);
  const listing = await getPublishedListing(db, listingId.trim());
  if (listing.vendorId === caller.uid) {
    err('FORBIDDEN', 403, 'You cannot book your own listing.');
  }
  const name = await customerName(db, caller);
  const nowIso = now.toISOString();
  const id = `bkg-${randomUUID()}`;
  const ref = db.collection(MARKETPLACE_BOOKINGS).doc(id);

  return await db.runTransaction(async (tx) => {
    // Re-read the listing inside the tx: status must still be published.
    const listingSnap = await tx.get(
      db.collection(MARKETPLACE_LISTINGS).doc(listing.listingId),
    );
    const listingData = listingSnap.data();
    if (!listingSnap.exists || listingData?.status !== 'published') {
      err('LISTING_NOT_AVAILABLE', 409, 'This listing is no longer available.');
    }

    const existing = await tx.get(
      db
        .collection(MARKETPLACE_BOOKINGS)
        .where('customerId', '==', caller.uid)
        .where('listingId', '==', listing.listingId)
        .where('status', 'in', [...ACTIVE_BOOKING_STATUSES])
        .limit(5),
    );
    for (const doc of existing.docs) {
      const d = doc.data();
      // Same idempotency key = retried request → return the original.
      if (d.idempotencyKey === idempotencyKey) {
        return toBooking(doc.id, d);
      }
      err(
        'BOOKING_ALREADY_ACTIVE',
        409,
        'You already have an active request on this listing.',
      );
    }

    const booking: MarketplaceBooking & { idempotencyKey: string } = {
      bookingId: id,
      listingId: listing.listingId,
      listingTitle: listing.title,
      type: listing.type,
      vendorId: listing.vendorId,
      customerId: caller.uid,
      customerName: name,
      status: 'requested',
      request,
      statusHistory: [{ status: 'requested', at: nowIso, by: caller.uid }],
      createdAt: nowIso,
      updatedAt: nowIso,
      version: 1,
      idempotencyKey,
    };
    tx.set(ref, booking as unknown as Record<string, unknown>);
    return toBooking(id, booking as unknown as Record<string, unknown>);
  });
}

/** Rental date-overlap guard: two CONFIRMED bookings on one listing cannot
 * hold overlapping checkIn/checkOut windows. */
async function assertNoRentalConflict(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  booking: MarketplaceBooking,
): Promise<void> {
  const details = isObj(booking.request.details)
    ? booking.request.details
    : booking.request;
  const checkIn = details.checkIn;
  const checkOut = details.checkOut;
  if (typeof checkIn !== 'string' || typeof checkOut !== 'string') {
    return; // No dated stay requested — nothing to conflict with.
  }
  const confirmed = await tx.get(
    db
      .collection(MARKETPLACE_BOOKINGS)
      .where('listingId', '==', booking.listingId)
      .where('status', '==', 'confirmed')
      .limit(20),
  );
  for (const doc of confirmed.docs) {
    if (doc.id === booking.bookingId) continue;
    const other = toBooking(doc.id, doc.data());
    const d = isObj(other.request.details)
      ? other.request.details
      : other.request;
    const oIn = d.checkIn;
    const oOut = d.checkOut;
    if (
      typeof oIn === 'string' &&
      typeof oOut === 'string' &&
      checkIn < oOut &&
      checkOut > oIn
    ) {
      err(
        'BOOKING_CONFLICT',
        409,
        'These dates conflict with another confirmed booking.',
      );
    }
  }
}

/**
 * Gross completed amount (whole rupees) a commission applies to, in priority
 * order: an explicit finalAmount on the request (rental adjustments —
 * early checkout / extensions land here) → the agreed quote → the
 * customer-proposed amount → the listing's advertised price.
 */
async function bookingGrossRupees(
  db: Firestore,
  tx: FirebaseFirestore.Transaction,
  booking: MarketplaceBooking,
): Promise<number> {
  const details = isObj(booking.request.details)
    ? booking.request.details
    : booking.request;
  for (const key of ['finalAmount']) {
    const v = details[key];
    const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
    if (Number.isInteger(n) && n > 0 && n <= 100_000_000) return n;
  }
  if (booking.quote && Number.isInteger(booking.quote.amount)) {
    return booking.quote.amount;
  }
  for (const key of ['amount']) {
    const v = details[key];
    const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
    if (Number.isInteger(n) && n > 0 && n <= 100_000_000) return n;
  }
  const listingSnap = await tx.get(
    db.collection(MARKETPLACE_LISTINGS).doc(booking.listingId),
  );
  const price = Number(listingSnap.data()?.price);
  return Number.isInteger(price) && price > 0 ? price : 0;
}

export type VendorAction =
  | { action: 'quote'; amount: number; note?: string }
  | { action: 'accept' | 'reject' | 'cancel' | 'start' | 'complete'; note?: string };

const VENDOR_TRANSITIONS: Record<
  VendorAction['action'],
  { from: readonly BookingStatus[]; to: BookingStatus }
> = {
  quote: { from: ['requested', 'quoted'], to: 'quoted' },
  accept: { from: ['requested'], to: 'confirmed' },
  reject: { from: ['requested', 'quoted'], to: 'rejected' },
  cancel: { from: ['confirmed', 'in_progress'], to: 'cancelled' },
  start: { from: ['confirmed'], to: 'in_progress' },
  complete: { from: ['confirmed', 'in_progress'], to: 'completed' },
};

const CUSTOMER_TRANSITIONS: Record<
  string,
  { from: readonly BookingStatus[]; to: BookingStatus }
> = {
  accept: { from: ['quoted'], to: 'confirmed' },
  cancel: { from: ['requested', 'quoted', 'confirmed'], to: 'cancelled' },
};

/**
 * Vendor-side transition. Ownership is enforced by doc vendorId — a vendor
 * approved for another role still cannot touch this booking.
 */
export async function vendorTransition(
  db: Firestore,
  caller: AuthenticatedCaller,
  bookingId: string,
  payload: VendorAction,
  now: Date,
): Promise<MarketplaceBooking> {
  const rule = VENDOR_TRANSITIONS[payload.action];
  if (!rule) {
    err('VALIDATION_ERROR', 400, 'Unknown action.');
  }
  let quote: MarketplaceBooking['quote'];
  if (payload.action === 'quote') {
    const amount = payload.amount;
    if (
      typeof amount !== 'number' ||
      !Number.isInteger(amount) ||
      amount <= 0 ||
      amount > QUOTE_MAX
    ) {
      err('VALIDATION_ERROR', 400, `amount must be 1–${QUOTE_MAX}.`);
    }
    quote = {
      amount,
      ...(typeof payload.note === 'string' && payload.note.trim().length > 0
        ? { note: payload.note.trim().slice(0, 500) }
        : {}),
      sentAt: now.toISOString(),
    };
  }

  const ref = db.collection(MARKETPLACE_BOOKINGS).doc(bookingId);
  const preview = await ref.get();
  if (!preview.exists) {
    err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
  }
  const previewData = preview.data() ?? {};
  if (previewData.vendorId !== caller.uid) {
    err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
  }
  // Suspended / revoked vendors cannot act on their inbox either.
  await requireApprovedVendor(
    db,
    caller,
    previewData.type as MarketplaceBooking['type'],
  );
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
    }
    const booking = toBooking(snap.id, snap.data() ?? {});
    if (booking.vendorId !== caller.uid) {
      err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
    }
    if (!rule.from.includes(booking.status)) {
      err(
        'INVALID_STATUS_TRANSITION',
        409,
        `Cannot ${payload.action} a booking in status '${booking.status}'.`,
      );
    }
    // Eligibility gate: a negative shared-wallet balance blocks accepting
    // new work until the partner recharges (completion never blocks).
    if (rule.to === 'confirmed' && payload.action === 'accept') {
      try {
        await assertWalletEligibleInsideTx(db, tx, booking.vendorId);
      } catch (e) {
        if (e instanceof WalletError) {
          err(e.code, e.httpStatus, e.message);
        }
        throw e;
      }
    }
    if (rule.to === 'confirmed' && booking.type === 'rental') {
      await assertNoRentalConflict(db, tx, booking);
    }

    // Settlement: vendor-confirmed completion + payment received — the only
    // point commission is ever deducted. Deterministic ledger id keeps the
    // charge exactly-once; balance may go negative by approved policy.
    let commissionCharge: Awaited<
      ReturnType<typeof chargeCommissionInsideTx>
    > = null;
    if (rule.to === 'completed') {
      const grossRupees = await bookingGrossRupees(db, tx, booking);
      try {
        commissionCharge = await chargeCommissionInsideTx(db, tx, {
          uid: booking.vendorId,
          role: booking.type,
          sourceType: 'booking',
          sourceId: booking.bookingId,
          grossMinor: grossRupees * 100,
          description: `Commission — ${booking.type} booking ${booking.bookingId}`,
        }, now);
      } catch (e) {
        if (e instanceof WalletError) {
          err(e.code, e.httpStatus, e.message);
        }
        throw e;
      }
    }

    const nowIso = now.toISOString();
    const note =
      'note' in payload && typeof payload.note === 'string'
        ? payload.note.trim().slice(0, 500)
        : undefined;
    const patch: Record<string, unknown> = {
      status: rule.to,
      updatedAt: nowIso,
      version: booking.version + 1,
      statusHistory: [
        ...booking.statusHistory,
        {
          status: rule.to,
          at: nowIso,
          by: caller.uid,
          ...(note ? { note } : {}),
        },
      ],
    };
    if (quote) {
      patch.quote = quote;
    }
    if (commissionCharge) {
      patch.commission = {
        points: commissionCharge.commissionPoints,
        amountMinor: commissionCharge.commissionMinor,
        grossMinor: commissionCharge.grossMinor,
        bps: commissionCharge.bps,
        ledgerEntryId: commissionCharge.entryId,
        chargedAt: nowIso,
      };
    }
    tx.update(ref, patch);
    return toBooking(snap.id, { ...snap.data(), ...patch });
  });
}

/** Customer-side transition: accept a quote or cancel a non-terminal booking. */
export async function customerTransition(
  db: Firestore,
  caller: AuthenticatedCaller,
  bookingId: string,
  action: 'accept' | 'cancel',
  noteRaw: unknown,
  now: Date,
): Promise<MarketplaceBooking> {
  const rule = CUSTOMER_TRANSITIONS[action];
  if (!rule) {
    err('VALIDATION_ERROR', 400, 'Unknown action.');
  }
  const ref = db.collection(MARKETPLACE_BOOKINGS).doc(bookingId);
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
    }
    const booking = toBooking(snap.id, snap.data() ?? {});
    if (booking.customerId !== caller.uid) {
      err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
    }
    if (!rule.from.includes(booking.status)) {
      err(
        'INVALID_STATUS_TRANSITION',
        409,
        `Cannot ${action} a booking in status '${booking.status}'.`,
      );
    }
    if (rule.to === 'confirmed' && booking.type === 'rental') {
      await assertNoRentalConflict(db, tx, booking);
    }
    const nowIso = now.toISOString();
    const note =
      typeof noteRaw === 'string' && noteRaw.trim().length > 0
        ? noteRaw.trim().slice(0, 500)
        : undefined;
    const statusHistory = [
      ...booking.statusHistory,
      {
        status: rule.to,
        at: nowIso,
        by: caller.uid,
        ...(note ? { note } : {}),
      },
    ];
    tx.update(ref, {
      status: rule.to,
      updatedAt: nowIso,
      version: booking.version + 1,
      statusHistory,
    });
    return toBooking(snap.id, {
      ...snap.data(),
      status: rule.to,
      updatedAt: nowIso,
      version: booking.version + 1,
      statusHistory,
    });
  });
}

export async function getBooking(
  db: Firestore,
  caller: AuthenticatedCaller,
  bookingId: string,
): Promise<MarketplaceBooking> {
  const snap = await db.collection(MARKETPLACE_BOOKINGS).doc(bookingId).get();
  if (!snap.exists) {
    err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
  }
  const booking = toBooking(snap.id, snap.data() ?? {});
  if (booking.customerId !== caller.uid && booking.vendorId !== caller.uid) {
    err('BOOKING_NOT_FOUND', 404, 'Booking not found.');
  }
  return booking;
}

/** Lists the caller's bookings — as customer or as vendor. Vendor listing
 * requires approval for that booking type (a suspended vendor loses inbox
 * access like every other vendor surface). */
export async function listBookings(
  db: Firestore,
  caller: AuthenticatedCaller,
  role: 'customer' | 'vendor',
  opts: { type?: string; limit?: number },
): Promise<MarketplaceBooking[]> {
  const field = role === 'vendor' ? 'vendorId' : 'customerId';
  let ref = db
    .collection(MARKETPLACE_BOOKINGS)
    .where(field, '==', caller.uid) as FirebaseFirestore.Query;
  if (opts.type) {
    ref = ref.where('type', '==', opts.type);
  }
  const snap = await ref
    .orderBy('createdAt', 'desc')
    .limit(Math.min(opts.limit ?? LIST_LIMIT, LIST_LIMIT))
    .get();
  return snap.docs.map((d) => toBooking(d.id, d.data()));
}
