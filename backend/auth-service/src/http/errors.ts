import type { Request, Response } from 'express';
import { getRequestId } from './request_id';

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
  };
  requestId: string;
}

export function sendApiError(
  req: Request,
  res: Response,
  status: number,
  code: string,
  message: string,
): void {
  const requestId = getRequestId(req);
  const body: ApiErrorBody = {
    error: { code, message },
    requestId,
  };
  res.status(status).json(body);
}

export function logSafe(message: string, meta: Record<string, unknown>): void {
  // Never log tokens, OTPs, secrets, or raw Authorization values.
  // eslint-disable-next-line no-console
  console.log(JSON.stringify({ msg: message, ...meta }));
}
