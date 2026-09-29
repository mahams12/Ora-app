/**
 * D1 — driver FCM device-token registration (server-authoritative).
 */

import type { Firestore } from 'firebase-admin/firestore';
import type { AuthenticatedCaller } from '../types';
import { loadActor } from '../rides/eligibility';
import { DriverDomainError } from '../drivers/types';
import {
  DRIVER_DEVICE_TOKENS,
  deviceTokenDocId,
  type DriverDeviceTokenDoc,
} from './d1_types';

const MAX_TOKEN_LEN = 4096;
const MIN_TOKEN_LEN = 16;

function parseToken(body: unknown): string {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new DriverDomainError(
      'VALIDATION_ERROR',
      400,
      'Request body must be an object.',
    );
  }
  const raw = (body as Record<string, unknown>).token;
  if (typeof raw !== 'string') {
    throw new DriverDomainError(
      'VALIDATION_ERROR',
      400,
      'token must be a string.',
    );
  }
  const token = raw.trim();
  if (token.length < MIN_TOKEN_LEN || token.length > MAX_TOKEN_LEN) {
    throw new DriverDomainError(
      'VALIDATION_ERROR',
      400,
      `token length must be between ${MIN_TOKEN_LEN} and ${MAX_TOKEN_LEN}.`,
    );
  }
  const extra = Object.keys(body as object).filter((k) => k !== 'token');
  if (extra.length > 0) {
    throw new DriverDomainError(
      'VALIDATION_ERROR',
      400,
      `Unknown fields: ${extra.join(', ')}.`,
    );
  }
  return token;
}

export class DeviceTokenService {
  constructor(private readonly db: Firestore) {}

  async register(input: {
    caller: AuthenticatedCaller;
    body: unknown;
  }): Promise<{ httpStatus: number; data: { driverId: string; tokenId: string } }> {
    const actor = await loadActor(this.db, input.caller.uid);
    if (actor.role !== 'driver' || actor.driverStatus !== 'approved') {
      throw new DriverDomainError(
        'FORBIDDEN',
        403,
        'Only approved drivers may register device tokens.',
      );
    }
    const token = parseToken(input.body);
    const driverId = input.caller.uid;
    const tokenId = deviceTokenDocId(driverId, token);
    const nowIso = new Date().toISOString();
    const ref = this.db.collection(DRIVER_DEVICE_TOKENS).doc(tokenId);
    const existing = await ref.get();
    const doc: DriverDeviceTokenDoc = {
      tokenId,
      driverId,
      token,
      createdAt: existing.exists
        ? String((existing.data() as DriverDeviceTokenDoc).createdAt ?? nowIso)
        : nowIso,
      updatedAt: nowIso,
    };
    await ref.set(doc);
    return {
      httpStatus: existing.exists ? 200 : 201,
      data: { driverId, tokenId },
    };
  }

  async clear(input: {
    caller: AuthenticatedCaller;
    body: unknown;
  }): Promise<{ httpStatus: number; data: { driverId: string; cleared: boolean } }> {
    const actor = await loadActor(this.db, input.caller.uid);
    if (actor.role !== 'driver' || actor.driverStatus !== 'approved') {
      throw new DriverDomainError(
        'FORBIDDEN',
        403,
        'Only approved drivers may clear device tokens.',
      );
    }
    const token = parseToken(input.body);
    const driverId = input.caller.uid;
    const tokenId = deviceTokenDocId(driverId, token);
    const ref = this.db.collection(DRIVER_DEVICE_TOKENS).doc(tokenId);
    const snap = await ref.get();
    if (!snap.exists) {
      return { httpStatus: 200, data: { driverId, cleared: false } };
    }
    const data = snap.data() as DriverDeviceTokenDoc;
    if (data.driverId !== driverId) {
      throw new DriverDomainError('FORBIDDEN', 403, 'Token ownership mismatch.');
    }
    await ref.delete();
    return { httpStatus: 200, data: { driverId, cleared: true } };
  }

  async listTokensForDriver(driverId: string): Promise<string[]> {
    const snap = await this.db
      .collection(DRIVER_DEVICE_TOKENS)
      .where('driverId', '==', driverId)
      .get();
    return snap.docs
      .map((d) => (d.data() as DriverDeviceTokenDoc).token)
      .filter((t) => typeof t === 'string' && t.length > 0);
  }

  async deleteTokenByValue(driverId: string, token: string): Promise<void> {
    const tokenId = deviceTokenDocId(driverId, token);
    const ref = this.db.collection(DRIVER_DEVICE_TOKENS).doc(tokenId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const data = snap.data() as DriverDeviceTokenDoc;
    if (data.driverId !== driverId) return;
    await ref.delete();
  }
}
