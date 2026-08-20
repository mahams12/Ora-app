import { Router } from 'express';
import type { Firestore } from 'firebase-admin/firestore';
import type { AuthedRequest } from '../middleware/auth';
import { getMe, registerUser } from '../services/users';

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
      res.status(401).json({
        error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' },
      });
      return;
    }

    const idempotencyKey = req.header('Idempotency-Key');
    if (!idempotencyKey || idempotencyKey.trim() === '') {
      res.status(400).json({
        error: {
          code: 'IDEMPOTENCY_KEY_REQUIRED',
          message: 'Idempotency-Key header is required for registration.',
        },
      });
      return;
    }

    // Client may send register_{uid}; we only accept keys bound to THIS token.
    const expected = `register_${caller.uid}`;
    if (idempotencyKey !== expected) {
      res.status(403).json({
        error: {
          code: 'FORBIDDEN',
          message: 'Idempotency key must match the authenticated identity.',
        },
      });
      return;
    }

    try {
      const profile = await registerUser(db, caller, new Date());
      if (!profile.isActive || profile.banned) {
        res.status(403).json({
          error: {
            code: 'ACCOUNT_DISABLED',
            message: 'This account is disabled.',
          },
        });
        return;
      }
      res.status(200).json(profile);
    } catch {
      res.status(500).json({
        error: {
          code: 'INTERNAL',
          message: 'Registration failed.',
        },
      });
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
      res.status(401).json({
        error: { code: 'UNAUTHENTICATED', message: 'Not authenticated.' },
      });
      return;
    }

    // Explicitly ignore any client-supplied identity knobs.
    void req.query.userId;
    void req.body?.uid;

    try {
      const profile = await getMe(db, caller);
      if (!profile) {
        res.status(404).json({
          error: {
            code: 'USER_NOT_FOUND',
            message: 'User profile does not exist. Call POST /v1/auth/register.',
          },
        });
        return;
      }
      if (!profile.isActive || profile.banned) {
        res.status(403).json({
          error: {
            code: 'ACCOUNT_DISABLED',
            message: 'This account is disabled.',
          },
        });
        return;
      }
      res.status(200).json(profile);
    } catch {
      res.status(500).json({
        error: {
          code: 'INTERNAL',
          message: 'Failed to load profile.',
        },
      });
    }
  });

  return router;
}
