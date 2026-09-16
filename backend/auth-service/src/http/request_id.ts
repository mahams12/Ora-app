import { randomUUID } from 'node:crypto';
import type { NextFunction, Request, Response } from 'express';

const REQUEST_ID_HEADER = 'X-Request-Id';
const MAX_LEN = 128;
const VALID = /^[A-Za-z0-9._-]{8,128}$/;

export type RequestWithId = Request & { requestId: string };

export function resolveRequestId(raw: string | undefined): string {
  const value = raw?.trim() ?? '';
  if (value.length >= 8 && value.length <= MAX_LEN && VALID.test(value)) {
    return value;
  }
  return randomUUID();
}

export function createRequestIdMiddleware() {
  return (req: Request, res: Response, next: NextFunction) => {
    const requestId = resolveRequestId(
      req.header(REQUEST_ID_HEADER) ?? undefined,
    );
    (req as RequestWithId).requestId = requestId;
    res.setHeader(REQUEST_ID_HEADER, requestId);
    next();
  };
}

export function getRequestId(req: Request): string {
  return (req as RequestWithId).requestId ?? resolveRequestId(undefined);
}
