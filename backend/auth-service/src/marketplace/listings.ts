import { randomUUID } from 'node:crypto';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller, VendorType } from '../types';
import { MARKETPLACE_TAXONOMY } from './catalogue_data';
import {
  ACTIVE_BOOKING_STATUSES,
  LISTING_TYPES,
  MARKETPLACE_BOOKINGS,
  MARKETPLACE_LISTINGS,
  MarketplaceError,
  type ListingStatus,
  type MarketplaceListing,
} from './types';

const USERS = 'users';

const TITLE_MIN = 3;
const TITLE_MAX = 120;
const DESCRIPTION_MIN = 10;
const DESCRIPTION_MAX = 2000;
const LOCATION_MIN = 3;
const LOCATION_MAX = 160;
const PRICE_MAX = 100_000_000;
const CONTACT_MAX = 24;
const MAX_PHOTOS = 6;
const MAX_PHOTO_TOTAL_BYTES = 600 * 1024;
const MAX_DETAILS_BYTES = 8 * 1024;
const MAX_DETAILS_KEYS = 30;
const MAX_DETAILS_VALUE_LEN = 500;
const MAX_LIST_LIMIT = 50;

const PRICE_UNITS: Record<VendorType, readonly string[]> = {
  service: ['Per Service', 'Per Visit', 'Per Hour', 'Per Day', 'Per Job'],
  rental: ['Per Day', 'Per Week', 'Per Month', 'Per Year'],
  cargo: ['Per Trip', 'Per Km', 'Per Day', 'Per Ton'],
};

const LISTING_WRITE_KEYS = new Set([
  'type',
  'categoryId',
  'subcategoryId',
  'title',
  'description',
  'price',
  'priceUnit',
  'location',
  'details',
  'photos',
  'contactNumber',
  'status',
]);

function err(code: string, httpStatus: number, message: string): never {
  throw new MarketplaceError(code, httpStatus, message);
}

function isObj(v: unknown): v is Record<string, unknown> {
  return v != null && typeof v === 'object' && !Array.isArray(v);
}

function requireString(
  value: unknown,
  field: string,
  min: number,
  max: number,
): string {
  if (typeof value !== 'string') {
    err('VALIDATION_ERROR', 400, `${field} is required.`);
  }
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    err('VALIDATION_ERROR', 400, `${field} must be ${min}–${max} characters.`);
  }
  return trimmed;
}

function normalizeType(value: unknown): VendorType {
  if (
    typeof value !== 'string' ||
    !(LISTING_TYPES as readonly string[]).includes(value)
  ) {
    err('VALIDATION_ERROR', 400, "type must be 'cargo', 'rental', or 'service'.");
  }
  return value as VendorType;
}

function normalizePrice(value: unknown): number {
  const n = typeof value === 'string' ? Number(value) : value;
  if (typeof n !== 'number' || !Number.isFinite(n) || !Number.isInteger(n)) {
    err('VALIDATION_ERROR', 400, 'price must be a whole-rupee integer.');
  }
  if (n < 0 || n > PRICE_MAX) {
    err('VALIDATION_ERROR', 400, `price must be 0–${PRICE_MAX}.`);
  }
  return n;
}

function normalizePriceUnit(value: unknown, type: VendorType): string {
  const unit =
    typeof value === 'string' && !value.startsWith('Per ')
      ? `Per ${value}`
      : value;
  if (typeof unit !== 'string' || !PRICE_UNITS[type].includes(unit)) {
    err(
      'VALIDATION_ERROR',
      400,
      `priceUnit must be one of: ${PRICE_UNITS[type].join(', ')}.`,
    );
  }
  return unit;
}

function normalizeTaxonomy(
  type: VendorType,
  categoryId: unknown,
  subcategoryId: unknown,
): { categoryId: string; subcategoryId: string } {
  if (typeof categoryId !== 'string' || categoryId.trim() === '') {
    err('VALIDATION_ERROR', 400, 'categoryId is required.');
  }
  const allowed = MARKETPLACE_TAXONOMY[type]?.[categoryId];
  if (!allowed) {
    err('VALIDATION_ERROR', 400, 'categoryId is not a valid category.');
  }
  if (typeof subcategoryId !== 'string' || !allowed.includes(subcategoryId)) {
    err('VALIDATION_ERROR', 400, 'subcategoryId is not valid for this category.');
  }
  return { categoryId, subcategoryId };
}

function normalizeDetails(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null) return {};
  if (!isObj(value)) {
    err('VALIDATION_ERROR', 400, 'details must be an object.');
  }
  const out: Record<string, unknown> = {};
  for (const [key, val] of Object.entries(value)) {
    if (Object.keys(out).length >= MAX_DETAILS_KEYS) break;
    if (typeof key !== 'string' || key.length === 0 || key.length > 60) {
      continue;
    }
    if (typeof val === 'string') {
      const t = val.trim();
      if (t.length > 0 && t.length <= MAX_DETAILS_VALUE_LEN) out[key] = t;
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
        .filter((i) => i.length > 0 && i.length <= MAX_DETAILS_VALUE_LEN);
      if (items.length > 0) out[key] = items;
    }
  }
  if (JSON.stringify(out).length > MAX_DETAILS_BYTES) {
    err('VALIDATION_ERROR', 400, 'details payload too large.');
  }
  return out;
}

function normalizePhotos(value: unknown): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > MAX_PHOTOS) {
    err('VALIDATION_ERROR', 400, `photos must be an array of ≤${MAX_PHOTOS}.`);
  }
  let total = 0;
  const photos: string[] = [];
  for (const item of value) {
    if (
      typeof item !== 'string' ||
      !/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(item)
    ) {
      err('VALIDATION_ERROR', 400, 'photos must be base64 image data URLs.');
    }
    total += item.length;
    photos.push(item);
  }
  if (total > MAX_PHOTO_TOTAL_BYTES) {
    err(
      'VALIDATION_ERROR',
      400,
      `photos exceed the ${MAX_PHOTO_TOTAL_BYTES / 1024}KB total limit — upload fewer or smaller images.`,
    );
  }
  return photos;
}

interface NormalizedFields {
  categoryId: string;
  subcategoryId: string;
  title: string;
  description: string;
  price: number;
  priceUnit: string;
  location: string;
  details: Record<string, unknown>;
  photos: string[];
  contactNumber: string;
}

function normalizeFields(
  body: Record<string, unknown>,
  type: VendorType,
): NormalizedFields {
  const taxonomy = normalizeTaxonomy(
    type,
    body.categoryId,
    body.subcategoryId,
  );
  return {
    ...taxonomy,
    title: requireString(body.title, 'title', TITLE_MIN, TITLE_MAX),
    description: requireString(
      body.description,
      'description',
      DESCRIPTION_MIN,
      DESCRIPTION_MAX,
    ),
    price: normalizePrice(body.price),
    priceUnit: normalizePriceUnit(body.priceUnit, type),
    location: requireString(body.location, 'location', LOCATION_MIN, LOCATION_MAX),
    details: normalizeDetails(body.details),
    photos: normalizePhotos(body.photos),
    contactNumber: requireString(
      body.contactNumber,
      'contactNumber',
      5,
      CONTACT_MAX,
    ),
  };
}

/**
 * Per-role write gate: the user doc's vendorApplications.{type}.status must
 * be 'approved'. Suspended and unapproved vendors are both rejected — the
 * distinction only changes the error code surfaced to the app.
 */
export async function requireApprovedVendor(
  db: Firestore,
  caller: AuthenticatedCaller,
  type: VendorType,
): Promise<{ displayName: string | null }> {
  const snap = await db.collection(USERS).doc(caller.uid).get();
  if (!snap.exists) {
    err('USER_NOT_FOUND', 404, 'User profile does not exist.');
  }
  const data = snap.data() ?? {};
  if (data.isActive === false || data.banned === true) {
    err('ACCOUNT_DISABLED', 403, 'This account is disabled.');
  }
  const apps = (data.vendorApplications ?? {}) as Record<
    string,
    { status?: unknown }
  >;
  const status = apps[type]?.status;
  if (status === 'suspended') {
    err(
      'VENDOR_SUSPENDED',
      403,
      'This partner access is suspended — contact support.',
    );
  }
  if (status !== 'approved') {
    err(
      'VENDOR_NOT_APPROVED',
      403,
      `You are not an approved ${type} partner.`,
    );
  }
  return {
    displayName:
      typeof data.displayName === 'string' ? data.displayName : null,
  };
}

function toListing(id: string, data: Record<string, unknown>): MarketplaceListing {
  return {
    listingId: id,
    vendorId: String(data.vendorId),
    vendorName: String(data.vendorName ?? 'ORA Vendor'),
    type: data.type as VendorType,
    categoryId: String(data.categoryId),
    subcategoryId: String(data.subcategoryId),
    title: String(data.title),
    description: String(data.description),
    price: Number(data.price),
    priceUnit: String(data.priceUnit),
    location: String(data.location),
    details: isObj(data.details) ? data.details : {},
    photos: Array.isArray(data.photos)
      ? data.photos.filter((p): p is string => typeof p === 'string')
      : [],
    contactNumber: String(data.contactNumber),
    status: data.status as ListingStatus,
    createdAt: String(data.createdAt),
    updatedAt: String(data.updatedAt),
    ...(typeof data.publishedAt === 'string'
      ? { publishedAt: data.publishedAt }
      : {}),
    version: Number(data.version ?? 0),
  };
}

export async function createListing(
  db: Firestore,
  caller: AuthenticatedCaller,
  body: unknown,
  now: Date,
): Promise<MarketplaceListing> {
  if (!isObj(body)) {
    err('VALIDATION_ERROR', 400, 'Request body must be a JSON object.');
  }
  const extra = Object.keys(body).filter((k) => !LISTING_WRITE_KEYS.has(k));
  if (extra.length > 0) {
    err('VALIDATION_ERROR', 400, `Unexpected fields: ${extra.join(', ')}.`);
  }
  const type = normalizeType(body.type);
  const { displayName } = await requireApprovedVendor(db, caller, type);
  const fields = normalizeFields(body, type);

  const status: ListingStatus = body.status === 'draft' ? 'draft' : 'published';
  const nowIso = now.toISOString();
  const id = `lst-${randomUUID()}`;
  const doc: MarketplaceListing = {
    listingId: id,
    vendorId: caller.uid,
    vendorName: displayName ? `${displayName}` : 'ORA Vendor',
    type,
    ...fields,
    status,
    createdAt: nowIso,
    updatedAt: nowIso,
    ...(status === 'published' ? { publishedAt: nowIso } : {}),
    version: 1,
  };
  await db
    .collection(MARKETPLACE_LISTINGS)
    .doc(id)
    .set(doc as unknown as Record<string, unknown>);
  return doc;
}

async function getOwnedListing(
  db: Firestore,
  caller: AuthenticatedCaller,
  listingId: string,
): Promise<{ ref: FirebaseFirestore.DocumentReference; data: MarketplaceListing }> {
  const ref = db.collection(MARKETPLACE_LISTINGS).doc(listingId);
  const snap = await ref.get();
  if (!snap.exists) {
    err('LISTING_NOT_FOUND', 404, 'Listing not found.');
  }
  const data = toListing(snap.id, snap.data() ?? {});
  if (data.vendorId !== caller.uid) {
    // Same response as a missing doc — never confirm ownership of another
    // vendor's listing.
    err('LISTING_NOT_FOUND', 404, 'Listing not found.');
  }
  if (data.status === 'deleted') {
    err('LISTING_NOT_FOUND', 404, 'Listing not found.');
  }
  return { ref, data };
}

export async function updateListing(
  db: Firestore,
  caller: AuthenticatedCaller,
  listingId: string,
  body: unknown,
  now: Date,
): Promise<MarketplaceListing> {
  if (!isObj(body)) {
    err('VALIDATION_ERROR', 400, 'Request body must be a JSON object.');
  }
  const extra = Object.keys(body).filter((k) => !LISTING_WRITE_KEYS.has(k));
  if (extra.length > 0) {
    err('VALIDATION_ERROR', 400, `Unexpected fields: ${extra.join(', ')}.`);
  }
  const { ref, data: existing } = await getOwnedListing(db, caller, listingId);
  // Editing never moves a listing across vendor-role boundaries.
  if (body.type !== undefined && body.type !== existing.type) {
    err('VALIDATION_ERROR', 400, 'type cannot be changed after creation.');
  }
  await requireApprovedVendor(db, caller, existing.type);
  const nowIso = now.toISOString();

  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      err('LISTING_NOT_FOUND', 404, 'Listing not found.');
    }
    const current = toListing(snap.id, snap.data() ?? {});
    if (current.status === 'deleted') {
      err('LISTING_NOT_FOUND', 404, 'Listing not found.');
    }

    const patch: Record<string, unknown> = {
      updatedAt: nowIso,
      version: current.version + 1,
    };
    const editable = [
      'title',
      'description',
      'price',
      'priceUnit',
      'location',
      'details',
      'photos',
      'contactNumber',
      'categoryId',
      'subcategoryId',
    ] as const;
    const fieldProvided = editable.some((k) => body[k] !== undefined);
    if (fieldProvided) {
      // Full re-validation against the merged view — clients send a partial
      // patch but every required field must still pass after merge.
      const merged = {
        type: current.type,
        categoryId: body.categoryId ?? current.categoryId,
        subcategoryId: body.subcategoryId ?? current.subcategoryId,
        title: body.title ?? current.title,
        description: body.description ?? current.description,
        price: body.price ?? current.price,
        priceUnit: body.priceUnit ?? current.priceUnit,
        location: body.location ?? current.location,
        details: body.details !== undefined ? body.details : current.details,
        photos: body.photos !== undefined ? body.photos : current.photos,
        contactNumber: body.contactNumber ?? current.contactNumber,
      };
      const fields = normalizeFields(merged, current.type);
      Object.assign(patch, fields);
    }

    if (body.status !== undefined) {
      const target = body.status as ListingStatus;
      const allowed: Record<ListingStatus, readonly ListingStatus[]> = {
        draft: ['published', 'paused'],
        published: ['paused', 'draft'],
        paused: ['published', 'draft'],
        deleted: [],
      };
      if (
        typeof target !== 'string' ||
        !allowed[current.status].includes(target)
      ) {
        err(
          'INVALID_STATUS_TRANSITION',
          409,
          `Cannot move a ${current.status} listing to '${String(body.status)}'.`,
        );
      }
      patch.status = target;
      if (target === 'published' && !current.publishedAt) {
        patch.publishedAt = nowIso;
      }
    }

    tx.update(ref, patch);
    return toListing(snap.id, { ...snap.data(), ...patch });
  });
}

/**
 * Soft delete → status 'deleted'. Listings with active bookings cannot be
 * deleted so customer requests never orphan.
 */
export async function deleteListing(
  db: Firestore,
  caller: AuthenticatedCaller,
  listingId: string,
  now: Date,
): Promise<void> {
  const { ref, data } = await getOwnedListing(db, caller, listingId);
  await requireApprovedVendor(db, caller, data.type);

  const active = await db
    .collection(MARKETPLACE_BOOKINGS)
    .where('listingId', '==', listingId)
    .where('status', 'in', [...ACTIVE_BOOKING_STATUSES])
    .limit(1)
    .get();
  if (!active.empty) {
    err(
      'LISTING_HAS_ACTIVE_BOOKINGS',
      409,
      'This listing has active bookings — complete or cancel them first, or pause the listing.',
    );
  }
  await ref.update({
    status: 'deleted',
    updatedAt: now.toISOString(),
    version: data.version + 1,
  });
}

export async function getOwnListing(
  db: Firestore,
  caller: AuthenticatedCaller,
  listingId: string,
): Promise<MarketplaceListing> {
  const { data } = await getOwnedListing(db, caller, listingId);
  return data;
}

export async function listOwnListings(
  db: Firestore,
  caller: AuthenticatedCaller,
  typeRaw: unknown,
): Promise<MarketplaceListing[]> {
  const type = normalizeType(typeRaw);
  await requireApprovedVendor(db, caller, type);
  const snap = await db
    .collection(MARKETPLACE_LISTINGS)
    .where('vendorId', '==', caller.uid)
    .where('type', '==', type)
    .orderBy('createdAt', 'desc')
    .limit(MAX_LIST_LIMIT)
    .get();
  return snap.docs
    .map((d) => toListing(d.id, d.data()))
    .filter((l) => l.status !== 'deleted');
}

export interface PublishedQuery {
  type: VendorType;
  categoryId?: string;
  subcategoryId?: string;
  q?: string;
  limit: number;
}

/** Customer discovery: published listings only, newest first. The `q`
 * substring filter runs server-side in-memory over the bounded result set —
 * Firestore has no substring operator and the catalogue is small. */
export async function listPublishedListings(
  db: Firestore,
  query: PublishedQuery,
): Promise<MarketplaceListing[]> {
  let ref = db
    .collection(MARKETPLACE_LISTINGS)
    .where('type', '==', query.type)
    .where('status', '==', 'published') as FirebaseFirestore.Query;
  if (query.categoryId) {
    ref = ref.where('categoryId', '==', query.categoryId);
  }
  if (query.subcategoryId) {
    ref = ref.where('subcategoryId', '==', query.subcategoryId);
  }
  const snap = await ref
    .orderBy('publishedAt', 'desc')
    .limit(MAX_LIST_LIMIT)
    .get();
  let listings = snap.docs.map((d) => toListing(d.id, d.data()));
  const q = query.q?.trim().toLowerCase();
  if (q) {
    listings = listings.filter(
      (l) =>
        l.title.toLowerCase().includes(q) ||
        l.description.toLowerCase().includes(q) ||
        l.location.toLowerCase().includes(q),
    );
  }
  return listings.slice(0, query.limit);
}

/** Public read path: published only. Vendors read their own drafts via
 * getOwnListing instead. */
export async function getPublishedListing(
  db: Firestore,
  listingId: string,
): Promise<MarketplaceListing> {
  const snap = await db.collection(MARKETPLACE_LISTINGS).doc(listingId).get();
  if (!snap.exists) {
    err('LISTING_NOT_FOUND', 404, 'Listing not found.');
  }
  const data = toListing(snap.id, snap.data() ?? {});
  if (data.status !== 'published') {
    err('LISTING_NOT_FOUND', 404, 'Listing not found.');
  }
  return data;
}
