import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../app';
import { calculateFare } from '../pricing/fare_calculator';
import {
  PRICING_SNAPSHOTS_COLLECTION,
  PricingEstimateService,
} from '../pricing/estimate_service';
import { buildPricingRuleSeed } from '../pricing/pricing_rules_repository';
import { PRICING_RULES_COLLECTION } from '../pricing/types';
import type { RoutingProvider } from '../routing/types';
import { RoutingError } from '../routing/types';
import { memoryDb } from './helpers/memory_db';

function seedEasy(db: ReturnType<typeof memoryDb>) {
  const seed = buildPricingRuleSeed({
    city: 'lahore',
    category: 'easy',
    version: '2026-09-22:v5b-test',
    baseFare: 100,
    ratePerKm: 20,
    ratePerMin: 5,
    categoryMultiplier: 1,
    minFare: 150,
    maxFare: 5000,
    offerMinRatio: 0.7,
    offerMaxRatio: 2.5,
  });
  db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed });
  return seed;
}

function mockRouting(
  result: { distanceKm: number; durationMin: number } | 'fail' | 'noroute',
): RoutingProvider {
  return {
    async computeDriveRoute() {
      if (result === 'fail') {
        throw new RoutingError(
          'PRICING_UNAVAILABLE',
          503,
          'Pricing isn\'t available right now.',
        );
      }
      if (result === 'noroute') {
        throw new RoutingError(
          'ROUTE_UNAVAILABLE',
          422,
          'Unable to determine a route for those points.',
        );
      }
      return {
        distanceKm: result.distanceKm,
        durationMin: result.durationMin,
        provider: 'google_routes',
      };
    },
  };
}

function appWith(
  db: ReturnType<typeof memoryDb>,
  routing: RoutingProvider | null,
) {
  return createApp({
    auth: {
      verifyIdToken: async () => ({
        uid: 'passenger-1',
        phone_number: '+923001234567',
      }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    pricingEstimateRateLimit: { windowMs: 60_000, max: 50_000 },
    routingProvider: routing,
  });
}

const validBody = {
  pickup: { lat: 31.5204, lng: 74.3587, address: 'Pickup' },
  destination: { lat: 31.51058, lng: 74.34445, address: 'Liberty' },
  category: 'easy',
  city: 'lahore',
  serviceType: 'ride',
};

describe('POST /v1/pricing/estimate', () => {
  it('1. authenticated valid request succeeds', async () => {
    const db = memoryDb();
    const rules = seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5.8, durationMin: 14 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(validBody);
    expect(res.status).toBe(200);
    expect(res.body.requestId).toBeTruthy();
    expect(res.body.timestamp).toBeTruthy();
    expect(res.body.data.pricingSnapshotId).toMatch(/^ps_/);
    expect(res.body.data.currency).toBe('PKR');
    expect(res.body.data.pricingRulesVersion).toBe(rules.version);
    expect(res.body.data.category).toBe('easy');
    expect(res.body.data.distanceKm).toBe(5.8);
    expect(res.body.data.durationMin).toBe(14);

    const expected = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: 'easy',
      city: 'lahore',
      rules,
    });
    expect(res.body.data.recommendedFareMinor).toBe(
      expected.recommendedFareMinor,
    );
    expect(res.body.data.offerBoundMinMinor).toBe(expected.offerBoundMinMinor);
    expect(res.body.data.offerBoundMaxMinor).toBe(expected.offerBoundMaxMinor);
  });

  it('2. unauthenticated request rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = createApp({
      auth: {
        verifyIdToken: async () => {
          throw Object.assign(new Error('bad'), { code: 'auth/invalid' });
        },
      } as never,
      db: db as never,
      requireAppCheck: false,
      routingProvider: mockRouting({ distanceKm: 5, durationMin: 10 }),
    });
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .send(validBody);
    expect(res.status).toBe(401);
  });

  it('3. invalid pickup rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({ ...validBody, pickup: { lat: 999, lng: 74 } });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('4. invalid destination rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({ ...validBody, destination: { lat: NaN, lng: 74 } });
    expect(res.status).toBe(400);
  });

  it('5. invalid category rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({ ...validBody, category: '' });
    expect(res.status).toBe(400);
  });

  it('6. missing city rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const { city: _c, ...noCity } = validBody;
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(noCity);
    expect(res.status).toBe(400);
    expect(res.body.error.message).toMatch(/city/i);
  });

  it('7–8. missing pricing rule fails closed', async () => {
    const db = memoryDb();
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(validBody);
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('PRICING_UNAVAILABLE');
  });

  it('9. Google route failure → PRICING_UNAVAILABLE', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting('fail'));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(validBody);
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('PRICING_UNAVAILABLE');
  });

  it('route unavailable → 422 ROUTE_UNAVAILABLE', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting('noroute'));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(validBody);
    expect(res.status).toBe(422);
    expect(res.body.error.code).toBe('ROUTE_UNAVAILABLE');
  });

  it('10–18. snapshot created with correct fields + 10 min expiry', async () => {
    const db = memoryDb();
    const rules = seedEasy(db);
    const fixedNow = new Date('2026-09-22T10:00:00.000Z');
    const service = new PricingEstimateService(
      db as never,
      mockRouting({ distanceKm: 5.8, durationMin: 14 }),
    );
    const data = await service.estimate({ body: validBody, now: fixedNow });
    expect(data.computedAt).toBe('2026-09-22T10:00:00.000Z');
    expect(data.expiresAt).toBe('2026-09-22T10:10:00.000Z');

    const stored = db.getDoc(PRICING_SNAPSHOTS_COLLECTION, data.pricingSnapshotId);
    expect(stored).toBeTruthy();
    expect(stored?.snapshotId).toBe(data.pricingSnapshotId);
    expect(stored?.recommendedFareMinor).toBe(data.recommendedFareMinor);
    expect(stored?.offerBoundMinMinor).toBe(data.offerBoundMinMinor);
    expect(stored?.offerBoundMaxMinor).toBe(data.offerBoundMaxMinor);
    expect(stored?.currency).toBe('PKR');
    expect(stored?.pricingRulesVersion).toBe(rules.version);
    expect((stored?.inputs as { distanceKm: number }).distanceKm).toBe(5.8);
    expect((stored?.inputs as { durationMin: number }).durationMin).toBe(14);
    expect((stored?.inputs as { categoryId: string }).categoryId).toBe('easy');
  });

  it('19–20. client fare/distance fields rejected', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        ...validBody,
        distanceKm: 1,
        recommendedFareMinor: 1,
        pricingSnapshotId: 'ps_fake',
      });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_ERROR');
    expect(res.body.error.message).toMatch(/forbidden|Unknown/i);
  });

  it('rejects invalid serviceType', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, mockRouting({ distanceKm: 5, durationMin: 10 }));
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({ ...validBody, serviceType: 'cargo' });
    expect(res.status).toBe(400);
  });

  it('without routing provider configured → 503', async () => {
    const db = memoryDb();
    seedEasy(db);
    const app = appWith(db, null);
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send(validBody);
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('PRICING_UNAVAILABLE');
  });
});
