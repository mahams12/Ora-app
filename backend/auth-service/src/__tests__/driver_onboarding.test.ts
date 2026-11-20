import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { driverAutoApproveFromEnv } from '../config/driver_auto_approve';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

const VALID_APPLICATION = {
  fullName: 'Ayesha Khan',
  cnicNumber: '35202-1234567-8',
  homeCity: 'Lahore',
  licenseNumber: 'LHR-123456',
  licenseExpiry: '2099-12-31',
  vehicleCategory: 'zip',
  vehicleMake: 'Toyota',
  vehicleModel: 'Corolla',
  vehicleYear: 2024,
  vehicleColor: 'White',
  plateNumber: ' lea-1234 ',
};

function seedUser(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  db.seed('users', uid, {
    uid,
    phoneNumber: '+923001111111',
    displayName: uid,
    role: 'passenger',
    driverStatus: 'none',
    isActive: true,
    banned: false,
    ...overrides,
  });
}

function authFor(uid: string) {
  return {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid,
      phone_number: '+923001111111',
    }),
  } as never;
}

function appFor(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  driverAutoApprove = true,
) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    driverAutoApprove,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

async function submit(
  app: ReturnType<typeof appFor>,
  body: Record<string, unknown> = VALID_APPLICATION,
) {
  return request(app)
    .post('/v1/drivers/onboarding')
    .set('Authorization', 'Bearer t')
    .send(body);
}

describe('driver onboarding', () => {
  it.each([
    ['fullName', 'A'],
    ['cnicNumber', '12345-123-1'],
    ['homeCity', 'X'],
    ['licenseNumber', '12'],
    ['licenseExpiry', '2024-02-30'],
    ['vehicleCategory', 'car'],
    ['vehicleMake', ''],
    ['vehicleModel', ''],
    ['vehicleYear', 1979],
    ['vehicleColor', ''],
    ['plateNumber', ' '],
  ])('returns a field-specific validation error for %s', async (field, value) => {
    const db = memoryDb();
    seedUser(db, 'p1');
    const response = await submit(appFor(db, 'p1'), {
      ...VALID_APPLICATION,
      [field]: value,
    });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
    expect(response.body.error.message).toContain(field);
    expect(db.getDoc('users', 'p1')?.driverStatus).toBe('none');
    expect(db.getDoc('drivers', 'p1')).toBeUndefined();
  });

  it('rejects an expired license date using the UTC date', async () => {
    const db = memoryDb();
    seedUser(db, 'p1');
    const yesterday = new Date(Date.now() - 86_400_000)
      .toISOString()
      .slice(0, 10);

    const response = await submit(appFor(db, 'p1'), {
      ...VALID_APPLICATION,
      licenseExpiry: yesterday,
    });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
    expect(response.body.error.message).toContain('licenseExpiry');
  });

  it('defaults auto-approval on and disables only for false or zero', () => {
    expect(driverAutoApproveFromEnv({})).toBe(true);
    expect(driverAutoApproveFromEnv({ DRIVER_AUTO_APPROVE: 'false' })).toBe(
      false,
    );
    expect(driverAutoApproveFromEnv({ DRIVER_AUTO_APPROVE: 'FALSE' })).toBe(
      false,
    );
    expect(driverAutoApproveFromEnv({ DRIVER_AUTO_APPROVE: '0' })).toBe(false);
    expect(driverAutoApproveFromEnv({ DRIVER_AUTO_APPROVE: 'true' })).toBe(
      true,
    );
  });

  it('auto-approves a none-status account and stores normalized application data', async () => {
    const db = memoryDb();
    seedUser(db, 'p1');

    const response = await submit(appFor(db, 'p1'));

    expect(response.status).toBe(200);
    expect(response.body.data).toEqual({
      driverStatus: 'approved',
      approved: true,
    });
    expect(db.getDoc('users', 'p1')).toMatchObject({
      role: 'driver',
      driverStatus: 'approved',
      driverApprovalSource: 'auto',
      updatedAt: expect.any(String),
    });
    expect(db.getDoc('drivers', 'p1')).toMatchObject({
      driverId: 'p1',
      userId: 'p1',
      fullName: 'Ayesha Khan',
      homeCity: 'Lahore',
      vehicle: {
        category: 'zip',
        make: 'Toyota',
        model: 'Corolla',
        year: 2024,
        color: 'White',
        plateNumber: 'LEA-1234',
      },
      documents: {
        cnicNumber: '3520212345678',
        licenseNumber: 'LHR-123456',
        licenseExpiry: '2099-12-31',
      },
      onboardingSubmittedAt: expect.any(String),
      updatedAt: expect.any(String),
      approvedAt: expect.any(String),
      availabilityState: 'offline',
      createdAt: expect.any(String),
    });
  });

  it('leaves the role unchanged and marks the application pending when disabled', async () => {
    const db = memoryDb();
    seedUser(db, 'p1');

    const response = await submit(appFor(db, 'p1', false));

    expect(response.status).toBe(200);
    expect(response.body.data).toEqual({
      driverStatus: 'pending',
      approved: false,
    });
    expect(db.getDoc('users', 'p1')).toMatchObject({
      role: 'passenger',
      driverStatus: 'pending',
    });
    expect(db.getDoc('users', 'p1')).not.toHaveProperty('driverApprovalSource');
    expect(db.getDoc('drivers', 'p1')).toMatchObject({
      availabilityState: 'offline',
      createdAt: expect.any(String),
    });
    expect(db.getDoc('drivers', 'p1')).not.toHaveProperty('approvedAt');
  });

  it('approved replay returns without writing either document', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', {
      role: 'passenger',
      driverStatus: 'approved',
      updatedAt: 'user-before',
      driverApprovalSource: 'manual',
    });
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'online',
      updatedAt: 'driver-before',
      geo: { lat: 31.5, lng: 74.3 },
    });
    const userBefore = { ...db.getDoc('users', 'd1')! };
    const driverBefore = { ...db.getDoc('drivers', 'd1')! };

    const response = await submit(appFor(db, 'd1'));

    expect(response.status).toBe(200);
    expect(response.body.data).toEqual({
      driverStatus: 'approved',
      approved: true,
    });
    expect(db.getDoc('users', 'd1')).toEqual(userBefore);
    expect(db.getDoc('drivers', 'd1')).toEqual(driverBefore);
  });

  it('never lifts a suspended driver status', async () => {
    const db = memoryDb();
    seedUser(db, 'd1', {
      role: 'driver',
      driverStatus: 'suspended',
      updatedAt: 'before',
    });
    const userBefore = { ...db.getDoc('users', 'd1')! };

    const response = await submit(appFor(db, 'd1'));

    expect(response.status).toBe(403);
    expect(response.body.error.code).toBe('DRIVER_SUSPENDED');
    expect(db.getDoc('users', 'd1')).toEqual(userBefore);
    expect(db.getDoc('drivers', 'd1')).toBeUndefined();
  });

  it('rejects a banned account', async () => {
    const db = memoryDb();
    seedUser(db, 'p1', { banned: true });

    const response = await submit(appFor(db, 'p1'));

    expect(response.status).toBe(403);
    expect(response.body.error.code).toBe('ACCOUNT_DISABLED');
    expect(db.getDoc('drivers', 'p1')).toBeUndefined();
  });

  it('rejects an inactive account and a missing user document', async () => {
    const inactiveDb = memoryDb();
    seedUser(inactiveDb, 'p1', { isActive: false });
    const inactive = await submit(appFor(inactiveDb, 'p1'));
    expect(inactive.status).toBe(403);
    expect(inactive.body.error.code).toBe('ACCOUNT_DISABLED');

    const missingDb = memoryDb();
    const missing = await submit(appFor(missingDb, 'missing'));
    expect(missing.status).toBe(403);
    expect(missing.body.error.code).toBe('FORBIDDEN');
  });

  it('preserves availability and geo fields on an existing driver document', async () => {
    const db = memoryDb();
    seedUser(db, 'd1');
    db.seed('drivers', 'd1', {
      driverId: 'd1',
      availabilityState: 'online',
      geo: { lat: 31.5, lng: 74.3 },
      lastLocationTs: 123,
    });

    const response = await submit(appFor(db, 'd1'));

    expect(response.status).toBe(200);
    expect(db.getDoc('drivers', 'd1')).toMatchObject({
      availabilityState: 'online',
      geo: { lat: 31.5, lng: 74.3 },
      lastLocationTs: 123,
      vehicle: { plateNumber: 'LEA-1234' },
    });
  });

  it('allows an auto-approved applicant through the go-online gate', async () => {
    const db = memoryDb();
    seedUser(db, 'p1');
    const app = appFor(db, 'p1');

    const application = await submit(app);
    const online = await request(app)
      .post('/v1/drivers/go-online')
      .set('Authorization', 'Bearer t')
      .send({});

    expect(application.body.data.approved).toBe(true);
    expect(online.status).toBe(200);
    expect(online.body.data.availabilityState).toBe('online');
  });
});
