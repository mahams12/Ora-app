import type { Request, Response, NextFunction } from 'express';
import { sendApiError } from '../http/errors';

/**
 * Service-authenticated internal worker boundary (Phase 2J).
 * Not a passenger/driver Firebase JWT path.
 */
export function createInternalWorkerMiddleware(
  expectedToken: string | undefined,
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!expectedToken || expectedToken.length < 16) {
      sendApiError(
        req,
        res,
        503,
        'INTERNAL',
        'Internal worker authentication is not configured.',
      );
      return;
    }
    const provided = req.header('X-Ora-Worker-Token') ?? '';
    if (provided !== expectedToken) {
      sendApiError(req, res, 403, 'FORBIDDEN', 'Invalid worker credentials.');
      return;
    }
    next();
  };
}
