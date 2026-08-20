import type { NextFunction, Request, Response } from 'express';
import type { Auth } from 'firebase-admin/auth';
import type { AuthenticatedCaller } from '../types';

export type AuthedRequest = Request & { caller?: AuthenticatedCaller };

export function createAuthMiddleware(auth: Auth, options: {
  requireAppCheck: boolean;
  verifyAppCheck?: (token: string) => Promise<void>;
}) {
  return async (req: AuthedRequest, res: Response, next: NextFunction) => {
    try {
      if (options.requireAppCheck) {
        const appCheck = req.header('X-Firebase-AppCheck');
        if (!appCheck) {
          res.status(401).json({
            error: {
              code: 'APP_CHECK_REQUIRED',
              message: 'Missing App Check token.',
            },
          });
          return;
        }
        if (options.verifyAppCheck) {
          try {
            await options.verifyAppCheck(appCheck);
          } catch {
            res.status(401).json({
              error: {
                code: 'APP_CHECK_INVALID',
                message: 'Invalid App Check token.',
              },
            });
            return;
          }
        }
      }

      const header = req.header('Authorization');
      if (!header?.startsWith('Bearer ')) {
        res.status(401).json({
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Missing or malformed Authorization bearer token.',
          },
        });
        return;
      }

      const idToken = header.slice('Bearer '.length).trim();
      if (!idToken) {
        res.status(401).json({
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Empty Authorization bearer token.',
          },
        });
        return;
      }

      const decoded = await auth.verifyIdToken(idToken, true);
      if (decoded.uid == null || decoded.uid === '') {
        res.status(401).json({
          error: {
            code: 'UNAUTHENTICATED',
            message: 'Token did not contain a uid.',
          },
        });
        return;
      }

      // Disabled Firebase accounts are rejected here (checkRevoked=true above
      // also rejects revoked sessions).
      req.caller = {
        uid: decoded.uid,
        phoneNumber: typeof decoded.phone_number === 'string'
          ? decoded.phone_number
          : null,
        email: typeof decoded.email === 'string' ? decoded.email : null,
        disabled: false,
      };
      next();
    } catch (err) {
      // Never leak Firebase internals, hostnames, or stack traces to clients.
      res.status(401).json({
        error: {
          code: 'UNAUTHENTICATED',
          message: 'Invalid or expired Firebase ID token.',
        },
      });
      void err;
    }
  };
}
