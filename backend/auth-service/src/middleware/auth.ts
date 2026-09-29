import type { NextFunction, Request, Response } from 'express';
import type { Auth } from 'firebase-admin/auth';
import type { AuthenticatedCaller } from '../types';
import { logSafe, sendApiError } from '../http/errors';

function isPricingEstimatePath(req: Request): boolean {
  const url = req.originalUrl ?? req.url ?? '';
  return url.includes('/pricing/estimate');
}

function logPricingAuthDiagnostic(
  req: Request,
  reason: string,
): void {
  if (!isPricingEstimatePath(req)) return;
  logSafe('pricing_estimate_auth', {
    result: 'rejected',
    reason,
    hasAuthorizationHeader: Boolean(req.header('Authorization')?.trim()),
  });
}

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
          sendApiError(
            req,
            res,
            401,
            'APP_CHECK_REQUIRED',
            'Missing App Check token.',
          );
          return;
        }
        if (options.verifyAppCheck) {
          try {
            await options.verifyAppCheck(appCheck);
          } catch {
            sendApiError(
              req,
              res,
              401,
              'APP_CHECK_INVALID',
              'Invalid App Check token.',
            );
            return;
          }
        }
      }

      const header = req.header('Authorization');
      if (!header?.startsWith('Bearer ')) {
        logPricingAuthDiagnostic(req, 'missing_or_malformed_bearer');
        sendApiError(
          req,
          res,
          401,
          'UNAUTHENTICATED',
          'Missing or malformed Authorization bearer token.',
        );
        return;
      }

      const idToken = header.slice('Bearer '.length).trim();
      if (!idToken) {
        logPricingAuthDiagnostic(req, 'empty_bearer');
        sendApiError(
          req,
          res,
          401,
          'UNAUTHENTICATED',
          'Empty Authorization bearer token.',
        );
        return;
      }

      const decoded = await auth.verifyIdToken(idToken, true);
      if (decoded.uid == null || decoded.uid === '') {
        sendApiError(
          req,
          res,
          401,
          'UNAUTHENTICATED',
          'Token did not contain a uid.',
        );
        return;
      }

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
      logPricingAuthDiagnostic(req, 'invalid_or_expired_token');
      sendApiError(
        req,
        res,
        401,
        'UNAUTHENTICATED',
        'Invalid or expired Firebase ID token.',
      );
      void err;
    }
  };
}
