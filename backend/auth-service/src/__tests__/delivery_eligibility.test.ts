import { describe, expect, it, vi } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { memoryDb } from './helpers/memory_db';

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

function seedApprovedDriver(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  seedUser(db, uid, {
    role: 'driver',
    driverStatus: 'approved',
    ...overrides,
  });
}

function seedCargoPartner(
  db: ReturnType<typeof memoryDb>,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  seedUser(db, uid, {
    vendorApplications: { cargo: { status: 'approved' } },
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

function appFor(db: ReturnType<typeof memoryDb>, uid: string) {
  return createApp({
    auth: authFor(uid),
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 10_000 },
  });
}

const AUTH = { Authorization: 'Bearer t' };
const VALID_TOKEN = 'fcm-token-0123456789abcdef';

describe('delivery eligibility — cargo-approved partners share the pipeline', () => {
  it('approved cargo partner can go online', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv1');
    const res = await request(appFor(db, 'lgv1'))
      .post('/v1/drivers/go-online')
      .set(AUTH)
      .send({});
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual({
      driverId: 'lgv1',
      availabilityState: 'online',
    });
    // A cargo partner is never silently upgraded to role=driver.
    expect(db.getDoc('users', 'lgv1')?.['role']).toBe('passenger');
  });

  it('approved cargo partner can list open delivery requests', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv2');
    const res = await request(appFor(db, 'lgv2'))
      .get('/v1/rides/open')
      .set(AUTH);
    expect(res.status).toBe(200);
  });

  it('approved cargo partner can list invite waves', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv3');
    const res = await request(appFor(db, 'lgv3'))
      .get('/v1/rides/invited')
      .set(AUTH);
    expect(res.status).toBe(200);
  });

  it('approved cargo partner can register an FCM device token', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv4');
    const res = await request(appFor(db, 'lgv4'))
      .post('/v1/drivers/device-tokens')
      .set(AUTH)
      .send({ token: VALID_TOKEN });
    expect(res.status).toBe(201);
    expect(res.body.data.driverId).toBe('lgv4');
  });

  it('approved cargo partner can clear an FCM device token', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv5');
    const res = await request(appFor(db, 'lgv5'))
      .delete('/v1/drivers/device-tokens')
      .set(AUTH)
      .send({ token: VALID_TOKEN });
    expect(res.status).toBe(200);
    expect(res.body.data.cleared).toBe(false);
  });

  it('approved driver still passes every delivery gate', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd1');
    const app = appFor(db, 'd1');
    for (const hit of [
      request(app).get('/v1/rides/open').set(AUTH),
      request(app).get('/v1/rides/invited').set(AUTH),
      request(app).post('/v1/drivers/go-online').set(AUTH).send({}),
    ]) {
      const res = await hit;
      expect(res.status).toBe(200);
    }
  });
});

describe('delivery eligibility — denied actors are still rejected', () => {
  it('plain passenger cannot go online or see delivery work', async () => {
    const db = memoryDb();
    seedUser(db, 'p1');
    const app = appFor(db, 'p1');
    for (const hit of [
      request(app).get('/v1/rides/open').set(AUTH),
      request(app).get('/v1/rides/invited').set(AUTH),
      request(app).post('/v1/drivers/go-online').set(AUTH).send({}),
      request(app)
        .post('/v1/drivers/device-tokens')
        .set(AUTH)
        .send({ token: VALID_TOKEN }),
    ]) {
      const res = await hit;
      expect(res.status).toBe(403);
    }
  });

  it('pending cargo application is not eligible', async () => {
    const db = memoryDb();
    seedUser(db, 'lgv-pending', {
      vendorApplications: { cargo: { status: 'pending' } },
    });
    const res = await request(appFor(db, 'lgv-pending'))
      .post('/v1/drivers/go-online')
      .set(AUTH)
      .send({});
    expect(res.status).toBe(403);
  });

  it('suspended cargo application is not eligible', async () => {
    const db = memoryDb();
    seedUser(db, 'lgv-susp', {
      vendorApplications: { cargo: { status: 'suspended' } },
    });
    const res = await request(appFor(db, 'lgv-susp'))
      .post('/v1/drivers/go-online')
      .set(AUTH)
      .send({});
    expect(res.status).toBe(403);
  });

  it('banned cargo partner is rejected before eligibility', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv-banned', { banned: true });
    const res = await request(appFor(db, 'lgv-banned'))
      .post('/v1/drivers/go-online')
      .set(AUTH)
      .send({});
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('ACCOUNT_DISABLED');
  });

  it('inactive cargo partner is rejected before eligibility', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv-inactive', { isActive: false });
    const res = await request(appFor(db, 'lgv-inactive'))
      .get('/v1/rides/open')
      .set(AUTH);
    expect(res.status).toBe(403);
    expect(res.body.error.code).toBe('ACCOUNT_DISABLED');
  });
});

describe('delivery eligibility — cargo approval never grants driver privileges', () => {
  it('cargo partner cannot switch into driver mode', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv6');
    const res = await request(appFor(db, 'lgv6'))
      .post('/v1/auth/mode')
      .set(AUTH)
      .set('Idempotency-Key', 'mode-key-0001')
      .send({ mode: 'driver' });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe('DRIVER_ONBOARDING_REQUIRED');
  });

  it('approved driver can switch into driver mode', async () => {
    const db = memoryDb();
    seedApprovedDriver(db, 'd2', { activeMode: 'passenger' });
    const res = await request(appFor(db, 'd2'))
      .post('/v1/auth/mode')
      .set(AUTH)
      .set('Idempotency-Key', 'mode-key-0002')
      .send({ mode: 'driver' });
    expect(res.status).toBe(200);
    expect(res.body.activeMode).toBe('driver');
  });

  it('cargo partner can switch to passenger mode', async () => {
    const db = memoryDb();
    seedCargoPartner(db, 'lgv7', { activeMode: 'driver' });
    const res = await request(appFor(db, 'lgv7'))
      .post('/v1/auth/mode')
      .set(AUTH)
      .set('Idempotency-Key', 'mode-key-0003')
      .send({ mode: 'passenger' });
    expect(res.status).toBe(200);
    expect(res.body.activeMode).toBe('passenger');
  });
});
