import type { Request, Response } from 'express';
import { getRequestId } from '../http/request_id';
import { sendApiError } from '../http/errors';
import { DriverDomainError } from './types';

export function sendDriverData(
  req: Request,
  res: Response,
  httpStatus: number,
  data: unknown,
): void {
  res.status(httpStatus).json({
    data,
    requestId: getRequestId(req),
    timestamp: new Date().toISOString(),
  });
}

export function sendDriverDomainError(
  req: Request,
  res: Response,
  err: unknown,
): void {
  if (err instanceof DriverDomainError) {
    sendApiError(req, res, err.httpStatus, err.code, err.message);
    return;
  }
  sendApiError(req, res, 500, 'INTERNAL', 'Unexpected server error.');
}
