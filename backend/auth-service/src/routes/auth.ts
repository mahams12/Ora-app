import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { sendApiError, logSafe } from '../http/errors';
import { getRequestId } from '../http/request_id';
import { DisplayNameValidationError } from '../services/display_name';
import { getMe, registerUser, updateProfile, UserNotFoundError } from '../services/users';

const PROFILE_ALLOWED_KEYS = new Set(['displayName']);

function rejectUnknownProfileFields(
  req: AuthedRequest,
  res: import('express').Response,
): boolean {
  const body = req.body;
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    sendApiError(
      req,
      res,
      400,
      'VALIDATION_ERROR',
      'Request body must be a JSON object.',
    );
    return true;
  }
  const extra = Object.keys(body).filter((key) => !PROFILE_ALLOWED_KEYS.has(key));
  if (extra.length > 0) {
    sendApiError(
      req,
      res,
      400,
      'VALIDATION_ERROR',
      'Only displayName may be updated.',
    );
    return true;
  }
  return false;
}

export function createAuthRouter(db: Firestore): Router {
  const router = Router();

  /**
   * POST /v1/auth/register
   *
   * Idempotent bootstrap. The Firebase uid is taken ONLY from the verified
   * bearer token. Any `uid` in the body is ignored to prevent forged identity.
   */
  router.post('/register', async (req: AuthedRequest, res) => {
    const caller = req.caller;
    if (!caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }

    const idempotencyKey = req.header('Idempotency-Key');
    if (!idempotencyKey || idempotencyKey.trim() === '') {
      sendApiError(
        req,
        res,
        400,
        'IDEMPOTENCY_KEY_REQUIRED',
        'Idempotency-Key header is required for registration.',
      );
      return;
    }

    const expected = `register_${caller.uid}`;
    if (idempotencyKey !== expected) {
      sendApiError(
        req,
        res,
        403,
        'FORBIDDEN',
        'Idempotency key must match the authenticated identity.',
      );
      return;
    }

    try {
      const profile = await registerUser(db, caller, new Date());
      if (!profile.isActive || profile.banned) {
        sendApiError(
          req,
          res,
          403,
          'ACCOUNT_DISABLED',
          'This account is disabled.',
        );
        return;
      }
      logSafe('register_ok', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'register',
      });
      res.status(200).json(profile);
    } catch (err) {
      logSafe('register_failed', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'register',
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      sendApiError(req, res, 500, 'INTERNAL', 'Registration failed.');
    }
  });

  /**
   * GET /v1/auth/me
   *
   * Identity is derived from the verified token. Query params like ?userId=
   * are never used as authority.
   */
  router.get('/me', async (req: AuthedRequest, res) => {
    const caller = req.caller;
    if (!caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }

    void req.query.userId;
    void req.body?.uid;

    try {
      const profile = await getMe(db, caller);
      if (!profile) {
        sendApiError(
          req,
          res,
          404,
          'USER_NOT_FOUND',
          'User profile does not exist. Call POST /v1/auth/register.',
        );
        return;
      }
      if (!profile.isActive || profile.banned) {
        sendApiError(
          req,
          res,
          403,
          'ACCOUNT_DISABLED',
          'This account is disabled.',
        );
        return;
      }
      res.status(200).json(profile);
    } catch (err) {
      logSafe('me_failed', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'me',
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      sendApiError(req, res, 500, 'INTERNAL', 'Failed to load profile.');
    }
  });

  /**
   * PATCH /v1/auth/profile
   *
   * Caller identity is the verified token uid only. Body uid/role/security
   * fields are rejected. Only displayName is written.
   */
  router.patch('/profile', async (req: AuthedRequest, res) => {
    const caller = req.caller;
    if (!caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }

    if (rejectUnknownProfileFields(req, res)) {
      return;
    }

    try {
      const existing = await getMe(db, caller);
      if (!existing) {
        sendApiError(
          req,
          res,
          404,
          'USER_NOT_FOUND',
          'User profile does not exist. Call POST /v1/auth/register.',
        );
        return;
      }
      if (!existing.isActive || existing.banned) {
        sendApiError(
          req,
          res,
          403,
          'ACCOUNT_DISABLED',
          'This account is disabled.',
        );
        return;
      }

      const profile = await updateProfile(
        db,
        caller,
        (req.body as { displayName?: unknown }).displayName,
        new Date(),
      );
      logSafe('profile_update_ok', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'patch_profile',
        profileComplete: profile.profileComplete,
      });
      res.status(200).json(profile);
    } catch (err) {
      if (err instanceof DisplayNameValidationError) {
        sendApiError(req, res, 400, err.code, err.message);
        return;
      }
      if (err instanceof UserNotFoundError) {
        sendApiError(
          req,
          res,
          404,
          'USER_NOT_FOUND',
          'User profile does not exist. Call POST /v1/auth/register.',
        );
        return;
      }
      logSafe('profile_update_failed', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'patch_profile',
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      sendApiError(req, res, 500, 'INTERNAL', 'Failed to update profile.');
    }
  });

  return router;
}
