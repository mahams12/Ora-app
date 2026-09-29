/**
 * Phase 4B/5B unit proof — MemoryDb + stub RoutingProvider.
 * Does NOT call Google. Does NOT create rides.
 *
 * Usage: npm run test:phase-5b-unit-proof
 */
import { createApp } from '../src/app';
import { calculateFare } from '../src/pricing/fare_calculator';
import {
  PRICING_SNAPSHOTS_COLLECTION,
} from '../src/pricing/estimate_service';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';
import { PRICING_RULES_COLLECTION } from '../src/pricing/types';
import type { RoutingProvider } from '../src/routing/types';
import { memoryDb } from '../src/__tests__/helpers/memory_db';
import request from 'supertest';

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(err);
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

async function main(): Promise<void> {
  const db = memoryDb();
  const seed = buildPricingRuleSeed({
    city: 'lahore',
    category: 'easy',
    version: '2026-09-22:v5b-unit',
    baseFare: 100,
    ratePerKm: 20,
    ratePerMin: 5,
    minFare: 150,
    maxFare: 5000,
  });
  db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed });

  const routing: RoutingProvider = {
    async computeDriveRoute() {
      return {
        distanceKm: 5.8,
        durationMin: 14,
        provider: 'google_routes',
      };
    },
  };

  const app = createApp({
    auth: {
      verifyIdToken: async () => ({ uid: 'p5b', phone_number: '+1' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    pricingEstimateRateLimit: { windowMs: 60_000, max: 50_000 },
    routingProvider: routing,
  });

  await test('1. POST /v1/pricing/estimate returns 200', async () => {
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        pickup: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
        category: 'easy',
        city: 'lahore',
      });
    assert(res.status === 200, `status ${res.status}`);
    assert(typeof res.body.data.pricingSnapshotId === 'string', 'snapshot id');
    assert(res.body.data.currency === 'PKR', 'currency');
  });

  await test('2. snapshot persisted before response fields used', async () => {
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        pickup: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
        category: 'easy',
        city: 'lahore',
      });
    const id = res.body.data.pricingSnapshotId as string;
    const doc = db.getDoc(PRICING_SNAPSHOTS_COLLECTION, id);
    assert(!!doc, 'snapshot missing');
    assert(doc!.snapshotId === id, 'id match');
  });

  await test('3. fare matches Phase 5A calculator', async () => {
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        pickup: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
        category: 'easy',
        city: 'lahore',
      });
    const expected = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: 'easy',
      city: 'lahore',
      rules: seed,
    });
    assert(
      res.body.data.recommendedFareMinor === expected.recommendedFareMinor,
      'fare mismatch',
    );
  });

  await test('4. ~10 minute expiry window', async () => {
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        pickup: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
        category: 'easy',
        city: 'lahore',
      });
    const computed = Date.parse(res.body.data.computedAt);
    const expires = Date.parse(res.body.data.expiresAt);
    assert(Number.isFinite(computed) && Number.isFinite(expires), 'dates');
    assert(expires - computed === 10 * 60 * 1000, 'ttl');
  });

  await test('5. no rides created', async () => {
    assert(
      [...db.store.keys()].every((k) => !k.startsWith('rides/')),
      'rides leaked',
    );
  });

  console.log(`\n5B unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
