import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { sendApiError, logSafe } from '../http/errors';
import { getRequestId } from '../http/request_id';
import {
  createTopup,
  getWallet,
  listLedger,
  listTopups,
  resolveTopup,
} from './wallet';
import { WalletError } from './types';

function handleError(
  req: AuthedRequest,
  res: import('express').Response,
  op: string,
  err: unknown,
  fallback: string,
): void {
  if (err instanceof WalletError) {
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
 * Shared partner wallet — one account per UID, readable from every approved
 * partner dashboard (driver, cargo, rental, service). Customers cannot call
 * any of these routes; approvedPartnerRoles() gates each one.
 */
export function createWalletRouter(db: Firestore): Router {
  const router = Router();

  router.get('/', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const wallet = await getWallet(db, req.caller, new Date());
      res.status(200).json({
        account: wallet.account,
        points: wallet.points,
        roles: wallet.roles,
        lowBalance: wallet.lowBalance,
        acceptBlocked: wallet.acceptBlocked,
        config: {
          minorPerPoint: wallet.config.minorPerPoint,
          commissionBps: wallet.config.commissionBps,
          lowBalanceWarnMinor: wallet.config.lowBalanceWarnMinor,
        },
      });
    } catch (err) {
      handleError(req, res, 'wallet_get', err, 'Failed to load wallet.');
    }
  });

  router.get('/transactions', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const entries = await listLedger(db, req.caller, {
        limit:
          typeof req.query.limit === 'string'
            ? Math.max(1, Math.min(Number(req.query.limit) || 50, 100))
            : 50,
      });
      res.status(200).json({ entries });
    } catch (err) {
      handleError(req, res, 'wallet_ledger', err, 'Failed to load history.');
    }
  });

  router.get('/topups', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    try {
      const topups = await listTopups(db, req.caller, {
        limit:
          typeof req.query.limit === 'string'
            ? Math.max(1, Math.min(Number(req.query.limit) || 50, 100))
            : 50,
      });
      res.status(200).json({ topups });
    } catch (err) {
      handleError(req, res, 'wallet_topups', err, 'Failed to load top-ups.');
    }
  });

  /**
   * Creates a PENDING top-up/withdrawal request. Points NEVER move here —
   * only the internal resolver (payment-verified/admin) posts the ledger.
   */
  router.post('/topups', async (req: AuthedRequest, res) => {
    if (!requireCaller(req, res)) return;
    if (!requireIdempotencyKey(req, res)) return;
    try {
      const topup = await createTopup(
        db,
        req.caller,
        req.body,
        req.header('Idempotency-Key')!.trim(),
        new Date(),
      );
      res.status(201).json({ topup });
    } catch (err) {
      handleError(req, res, 'wallet_topup', err, 'Failed to create top-up.');
    }
  });

  return router;
}

/**
 * Admin/PSP-verification endpoints, mounted behind the internal worker
 * middleware on /v1/internal. Approving credits points atomically.
 */
export function createInternalWalletRouter(db: Firestore): Router {
  const router = Router();

  router.post('/wallet/topups/:id/resolve', async (req, res) => {
    const action = req.body?.action;
    if (action !== 'approve' && action !== 'reject') {
      sendApiError(
        req,
        res,
        400,
        'VALIDATION_ERROR',
        "action must be 'approve' or 'reject'.",
      );
      return;
    }
    const resolvedBy =
      typeof req.body?.resolvedBy === 'string' &&
      req.body.resolvedBy.trim().length > 0
        ? req.body.resolvedBy.trim().slice(0, 120)
        : 'internal';
    try {
      const topup = await resolveTopup(
        db,
        req.params.id,
        action,
        resolvedBy,
        new Date(),
      );
      res.status(200).json({ topup });
    } catch (err) {
      if (err instanceof WalletError) {
        sendApiError(req, res, err.httpStatus, err.code, err.message);
        return;
      }
      logSafe('wallet_topup_resolve_failed', {
        requestId: getRequestId(req),
        op: 'wallet_topup_resolve',
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      sendApiError(req, res, 500, 'INTERNAL', 'Failed to resolve top-up.');
    }
  });

  return router;
}
