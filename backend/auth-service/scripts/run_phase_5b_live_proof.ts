/**
 * Phase 4B/5B LIVE proof — real Google Routes + MemoryDb estimate path.
 *
 * Requires: GOOGLE_MAPS_SERVER_KEY
 * Does NOT create rides. Does NOT call N3/N4.
 *
 * Usage:
 *   set -a && source .env && set +a
 *   npm run test:phase-5b-live-proof
 */
import request from 'supertest';
import { createApp } from '../src/app';
import { calculateFare } from '../src/pricing/fare_calculator';
import { PRICING_SNAPSHOTS_COLLECTION } from '../src/pricing/estimate_service';
import { buildPricingRuleSeed } from '../src/pricing/pricing_rules_repository';
import { PRICING_RULES_COLLECTION } from '../src/pricing/types';
import {
  createGoogleRoutesProviderFromEnv,
  GoogleRoutesProvider,
} from '../src/routing/google_routes_provider';
import { memoryDb } from '../src/__tests__/helpers/memory_db';

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
  if (!process.env.GOOGLE_MAPS_SERVER_KEY?.trim()) {
    console.error(
      'MANUAL ACTION REQUIRED: set GOOGLE_MAPS_SERVER_KEY (server Routes key).',
    );
    process.exit(2);
  }

  // Lahore — Liberty Market area (Phase 4A device coords neighborhood).
  const origin = { lat: 31.5204, lng: 74.3587 };
  const destination = { lat: 31.51058, lng: 74.34445 };

  const provider = createGoogleRoutesProviderFromEnv(process.env);
  assert(provider instanceof GoogleRoutesProvider, 'provider type');

  let liveDistanceKm = 0;
  let liveDurationMin = 0;

  await test('1. Live Google Routes computeDriveRoute succeeds', async () => {
    const route = await provider.computeDriveRoute({ origin, destination });
    assert(route.provider === 'google_routes', 'provider');
    assert(route.distanceKm > 0, `distanceKm=${route.distanceKm}`);
    assert(route.durationMin > 0, `durationMin=${route.durationMin}`);
    liveDistanceKm = route.distanceKm;
    liveDurationMin = route.durationMin;
    console.log(
      JSON.stringify({
        msg: 'live_route_ok',
        distanceKm: route.distanceKm,
        durationMin: route.durationMin,
      }),
    );
  });

  const db = memoryDb();
  const seed = buildPricingRuleSeed({
    city: 'lahore',
    category: 'easy',
    version: '2026-09-22:v5b-live',
    baseFare: 100,
    ratePerKm: 20,
    ratePerMin: 5,
    minFare: 150,
    maxFare: 5000,
  });
  db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed });

  const app = createApp({
    auth: {
      verifyIdToken: async () => ({ uid: 'p5b-live', phone_number: '+1' }),
    } as never,
    db: db as never,
    requireAppCheck: false,
    rateLimit: { windowMs: 60_000, max: 50_000 },
    pricingEstimateRateLimit: { windowMs: 60_000, max: 50_000 },
    routingProvider: provider,
  });

  await test('2. POST /v1/pricing/estimate → 200 + snapshot', async () => {
    const res = await request(app)
      .post('/v1/pricing/estimate')
      .set('Authorization', 'Bearer t')
      .send({
        pickup: { ...origin, address: 'Current location' },
        destination: { ...destination, address: 'Liberty Market' },
        category: 'easy',
        city: 'lahore',
        serviceType: 'ride',
      });
    assert(res.status === 200, `status=${res.status} body=${JSON.stringify(res.body)}`);
    const data = res.body.data;
    assert(typeof data.pricingSnapshotId === 'string', 'snapshot id');
    assert(data.pricingSnapshotId.startsWith('ps_'), 'ps_ prefix');
    assert(data.currency === 'PKR', 'currency');
    assert(data.pricingRulesVersion === seed.version, 'version');
    assert(typeof data.distanceKm === 'number' && data.distanceKm > 0, 'distance');
    assert(typeof data.durationMin === 'number' && data.durationMin > 0, 'duration');

    const computed = Date.parse(data.computedAt);
    const expires = Date.parse(data.expiresAt);
    assert(expires - computed === 10 * 60 * 1000, '10m expiry');

    const stored = db.getDoc(PRICING_SNAPSHOTS_COLLECTION, data.pricingSnapshotId);
    assert(!!stored, 'snapshot doc missing');
    assert(stored!.recommendedFareMinor === data.recommendedFareMinor, 'fare persist');

    const expected = calculateFare({
      distanceKm: data.distanceKm,
      durationMin: data.durationMin,
      category: 'easy',
      city: 'lahore',
      rules: seed,
    });
    assert(
      data.recommendedFareMinor === expected.recommendedFareMinor,
      'calculator match',
    );
    assert(
      data.offerBoundMinMinor === expected.offerBoundMinMinor,
      'bound min',
    );
    assert(
      data.offerBoundMaxMinor === expected.offerBoundMaxMinor,
      'bound max',
    );

    // Live route from step 1 should be in the same ballpark as estimate D/T
    // (traffic can differ slightly between sequential calls).
    assert(
      Math.abs(data.distanceKm - liveDistanceKm) / liveDistanceKm < 0.25 ||
        liveDistanceKm === 0,
      'distance drift vs direct Routes call',
    );
    void liveDurationMin;
  });

  await test('3. no rides created by live estimate', async () => {
    assert(
      [...db.store.keys()].every((k) => !k.startsWith('rides/')),
      'rides leaked',
    );
  });

  console.log(`\n5B live proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
