import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { sendApiError, logSafe } from '../http/errors';
import { getRequestId } from '../http/request_id';
import { DisplayNameValidationError } from '../services/display_name';
import {
  getMe,
  ModeSwitchBlockedError,
  registerUser,
  switchMode,
  updateProfile,
  UserNotFoundError,
} from '../services/users';
import type { DriverAvailabilityService } from '../drivers/driver_availability_service';
import { DriverDomainError } from '../drivers/types';

const PROFILE_ALLOWED_KEYS = new Set(['displayName']);
const MODE_ALLOWED_KEYS = new Set(['mode']);

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

export function createAuthRouter(
  db: Firestore,
  driverAvailability?: DriverAvailabilityService | null,
): Router {
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

  /**
   * POST /v1/auth/mode
   *
   * Switch to Driver / Switch to Passenger. Server-authoritative: guards
   * against unapproved drivers, live bookings on either side, and — on the
   * driver→passenger direction — durably takes the driver offline so a
   * passenger-mode session can never keep broadcasting driver presence.
   */
  router.post('/mode', async (req: AuthedRequest, res) => {
    const caller = req.caller;
    if (!caller) {
      sendApiError(req, res, 401, 'UNAUTHENTICATED', 'Not authenticated.');
      return;
    }
    const idempotencyKey = req.header('Idempotency-Key');
    if (!idempotencyKey || idempotencyKey.trim().length < 8) {
      sendApiError(
        req,
        res,
        400,
        'IDEMPOTENCY_KEY_REQUIRED',
        'Idempotency-Key header (min 8 chars) is required.',
      );
      return;
    }
    const body = req.body;
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Request body must be a JSON object.');
      return;
    }
    const extra = Object.keys(body).filter((k) => !MODE_ALLOWED_KEYS.has(k));
    if (extra.length > 0) {
      sendApiError(req, res, 400, 'VALIDATION_ERROR', 'Only mode may be set.');
      return;
    }

    try {
      const profile = await switchMode(
        db,
        caller,
        (body as { mode?: unknown }).mode,
        new Date(),
      );

      // Driver → passenger: take the driver offline durably so passenger mode
      // can never keep broadcasting presence. Missing drivers doc / already
      // offline are idempotent no-ops inside the availability service.
      if (
        profile.activeMode === 'passenger' &&
        profile.driverStatus === 'approved' &&
        driverAvailability
      ) {
        try {
          await driverAvailability.goOffline({
            caller,
            requestId: getRequestId(req),
          });
        } catch (err) {
          // Not an approved driver actor any more — nothing to take offline.
          if (!(err instanceof DriverDomainError)) throw err;
        }
      }

      logSafe('mode_switch_ok', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'switch_mode',
        activeMode: profile.activeMode,
      });
      res.status(200).json(profile);
    } catch (err) {
      if (err instanceof ModeSwitchBlockedError) {
        res.status(err.httpStatus).json({
          error: { code: err.code, message: err.message },
          requestId: getRequestId(req),
          ...(err.activeRideId ? { activeRideId: err.activeRideId } : {}),
        });
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
      logSafe('mode_switch_failed', {
        requestId: getRequestId(req),
        uid: caller.uid,
        op: 'switch_mode',
        errorType: err instanceof Error ? err.name : 'unknown',
      });
      sendApiError(req, res, 500, 'INTERNAL', 'Failed to switch mode.');
    }
  });

  return router;
}
