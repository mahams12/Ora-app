import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { sendApiError, logSafe } from '../http/errors';
import { getRequestId } from '../http/request_id';
import {
  createBooking,
  customerTransition,
  getBooking,
  listBookings,
  vendorTransition,
  type VendorAction,
} from './bookings';
import {
  createListing,
  deleteListing,
  getOwnListing,
  getPublishedListing,
  listOwnListings,
  listPublishedListings,
  updateListing,
} from './listings';
import { MarketplaceError } from './types';
import type { VendorType } from '../types';

function handleError(
  req: AuthedRequest,
  res: import('express').Response,
  op: string,
  err: unknown,
  fallback: string,
): void {
  if (err instanceof MarketplaceError) {
    sendApiError(req, res, err.httpStatus, err.code, err.message);
    return;
  }
  logSafe(`${op}_failed`, {
    requestId: getRequestId(req),
    uid: req.caller?.uid,
    op,
    errorType: err instanceof Error ? err.name : 'unknown',
  });
  sendApiError(req, res, 500, 'INTERNAL', fallback);
}

function requireCaller(
  req: AuthedRequest,
  res: import('express').Response,
): req is AuthedRequest & { caller: NonNullable<AuthedRequest['caller']> } {
  if (!req.caller) {
    sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
    return false;
  }
  return true;
}

function requireIdempotencyKey(
  req: AuthedRequest,
  res: import('express').Response,
): string | null {
  const key = req.header('Idempotency-Key');
  if (!key || key.trim().length < 8) {
    sendApiError(
      req,
      res,
      400,
      'IDEMPOTENCY_KEY_REQUIRED',
      'Idempotency-Key header (min 8 chars) is required.',
    );
    return null;
  }
  return key.trim();
}

/**
 * Vendor-side marketplace surface: listing CRUD + publish lifecycle. Every
 * route gates on vendorApplications.{type}.status === 'approved' inside the
 * service layer, and ownership on the doc's vendorId.
 */
export function createVendorListingsRouter(db: Firestore): Router {
  const router = Router();

  router.post('/listings', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    if (!requireIdempotencyKey(req, res)) return;
    try {
      const listing = await createListing(db, req.caller, req.body, new Date());
      logSafe('marketplace_listing_created', {
        requestId: getRequestId(req),
        uid: req.caller.uid,
        op: 'listing_create',
      });
      res.status(201).json({ listing });
    } catch (err) {
      handleError(req, res, 'listing_create', err, 'Failed to create listing.');
    }
  });

  router.get('/listings', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const listings = await listOwnListings(db, req.caller, req.query.type);
      res.status(200).json({ listings });
    } catch (err) {
      handleError(req, res, 'listing_list', err, 'Failed to list listings.');
    }
  });

  router.get('/listings/:id', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const listing = await getOwnListing(db, req.caller, req.params.id);
      res.status(200).json({ listing });
    } catch (err) {
      handleError(req, res, 'listing_get', err, 'Failed to load listing.');
    }
  });

  router.patch('/listings/:id', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const listing = await updateListing(
        db,
        req.caller,
        req.params.id,
        req.body,
        new Date(),
      );
      res.status(200).json({ listing });
    } catch (err) {
      handleError(req, res, 'listing_update', err, 'Failed to update listing.');
    }
  });

  router.delete('/listings/:id', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      await deleteListing(db, req.caller, req.params.id, new Date());
      res.status(200).json({ deleted: true });
    } catch (err) {
      handleError(req, res, 'listing_delete', err, 'Failed to delete listing.');
    }
  });

  return router;
}

/**
 * Customer discovery + the booking/quotation workflow shared by both sides.
 */
export function createMarketplaceRouter(db: Firestore): Router {
  const router = Router();

  router.get('/listings', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    const type = req.query.type;
    if (
      typeof type !== 'string' ||
      !(['cargo', 'rental', 'service'] as const).includes(type as VendorType)
    ) {
      sendApiError(
        req,
        res,
        400,
        'VALIDATION_ERROR',
        "type must be 'cargo', 'rental', or 'service'.",
      );
      return;
    }
    try {
      const listings = await listPublishedListings(db, {
        type: type as VendorType,
        categoryId:
          typeof req.query.categoryId === 'string'
            ? req.query.categoryId
            : undefined,
        subcategoryId:
          typeof req.query.subcategoryId === 'string'
            ? req.query.subcategoryId
            : undefined,
        q: typeof req.query.q === 'string' ? req.query.q : undefined,
        limit:
          typeof req.query.limit === 'string'
            ? Math.max(1, Math.min(Number(req.query.limit) || 20, 50))
            : 20,
      });
      res.status(200).json({ listings });
    } catch (err) {
      handleError(req, res, 'marketplace_list', err, 'Failed to load listings.');
    }
  });

  router.get('/listings/:id', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const listing = await getPublishedListing(db, req.params.id);
      res.status(200).json({ listing });
    } catch (err) {
      handleError(req, res, 'marketplace_get', err, 'Failed to load listing.');
    }
  });

  router.post('/bookings', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    const key = requireIdempotencyKey(req, res);
    if (!key) return;
    const body = req.body;
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Request body must be a JSON object.');
      return;
    }
    const extra = Object.keys(body).filter(
      (k) => !['listingId', 'request'].includes(k),
    );
    if (extra.length > 0) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', `Unexpected fields: ${extra.join(', ')}.`);
      return;
    }
    try {
      const booking = await createBooking(
        db,
        req.caller,
        body.listingId,
        body.request,
        key,
        new Date(),
      );
      logSafe('marketplace_booking_created', {
        requestId: getRequestId(req),
        uid: req.caller.uid,
        op: 'booking_create',
      });
      res.status(201).json({ booking });
    } catch (err) {
      handleError(req, res, 'booking_create', err, 'Failed to create booking.');
    }
  });

  router.get('/bookings', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    const role = req.query.role === 'vendor' ? 'vendor' : 'customer';
    try {
      const bookings = await listBookings(db, req.caller, role, {
        type: typeof req.query.type === 'string' ? req.query.type : undefined,
        limit:
          typeof req.query.limit === 'string'
            ? Number(req.query.limit)
            : undefined,
      });
      res.status(200).json({ bookings });
    } catch (err) {
      handleError(req, res, 'booking_list', err, 'Failed to load bookings.');
    }
  });

  router.get('/bookings/:id', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const booking = await getBooking(db, req.caller, req.params.id);
      res.status(200).json({ booking });
    } catch (err) {
      handleError(req, res, 'booking_get', err, 'Failed to load booking.');
    }
  });

  /** Vendor actions: quote / accept / reject / cancel / start / complete. */
  router.post('/bookings/:id/vendor-action', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    const body = req.body;
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Request body must be a JSON object.');
      return;
    }
    const allowed = new Set(['action', 'amount', 'note']);
    const extra = Object.keys(body).filter((k) => !allowed.has(k));
    if (extra.length > 0) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', `Unexpected fields: ${extra.join(', ')}.`);
      return;
    }
    try {
      const booking = await vendorTransition(
        db,
        req.caller,
        req.params.id,
        body as VendorAction,
        new Date(),
      );
      res.status(200).json({ booking });
    } catch (err) {
      handleError(req, res, 'booking_vendor', err, 'Failed to update booking.');
    }
  });

  /** Customer actions: accept (a quote) / cancel. */
  router.post(
    '/bookings/:id/customer-action',
    async (req: AuthedRequest, res) => {
      if (!requireCaller(req, res)) return;
      const body = req.body;
      if (body == null || typeof body !== 'object' || Array.isArray(body)) {
        sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Request body must be a JSON object.');
        return;
      }
      const allowed = new Set(['action', 'note']);
      const extra = Object.keys(body).filter((k) => !allowed.has(k));
      if (extra.length > 0) {
        sendApiError(req, res, 400, 'VALIDATION_ERROR', `Unexpected fields: ${extra.join(', ')}.`);
        return;
      }
      const action = (body as { action?: unknown }).action;
      if (action !== 'accept' && action !== 'cancel') {
        sendApiError(req, res, 400, 'VALIDATION_ERROR', "action must be 'accept' or 'cancel'.");
        return;
      }
      try {
        const booking = await customerTransition(
          db,
          req.caller,
          req.params.id,
          action,
          (body as { note?: unknown }).note,
          new Date(),
        );
        res.status(200).json({ booking });
      } catch (err) {
        handleError(req, res, 'booking_customer', err, 'Failed to update booking.');
      }
    },
  );

  return router;
}
