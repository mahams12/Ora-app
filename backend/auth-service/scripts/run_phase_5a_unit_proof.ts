/**
 * Phase 5A unit proof — MemoryDb + pure calculator.
 * Does NOT create pricingSnapshots, rides, or HTTP estimate routes.
 *
 * Usage: npm run test:phase-5a-unit-proof
 */
import { calculateFare } from '../src/pricing/fare_calculator';
import {
  PricingRulesRepository,
  buildPricingRuleSeed,
} from '../src/pricing/pricing_rules_repository';
import { PRICING_RULES_COLLECTION } from '../src/pricing/types';
import { memoryDb } from '../src/__tests__/helpers/memory_db';

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void> | void): Promise<void> {
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
  const repo = new PricingRulesRepository(db as never);

  const seed = buildPricingRuleSeed({
    city: 'lahore',
    category: 'easy',
    version: '2026-09-22:v5a-proof',
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

  await test('1. Admin/server seed of pricingRules fixture', async () => {
    const loaded = await repo.loadActiveRule({
      city: 'lahore',
      category: 'easy',
    });
    assert(loaded.ruleId === 'lahore_easy', 'ruleId');
    assert(loaded.version === '2026-09-22:v5a-proof', 'version');
  });

  await test('2. Backend loads rule + calculator is deterministic', async () => {
    const rules = await repo.loadActiveRule({
      city: 'lahore',
      category: 'easy',
    });
    const a = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: rules.category,
      city: rules.city,
      rules,
    });
    const b = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: rules.category,
      city: rules.city,
      rules,
    });
    assert(a.recommendedFareMinor === 29000, `fare got ${a.recommendedFareMinor}`);
    assert(a.offerBoundMinMinor === 20300, 'bound min');
    assert(a.offerBoundMaxMinor === 72500, 'bound max');
    assert(JSON.stringify(a) === JSON.stringify(b), 'determinism');
  });

  await test('3. pricingRulesVersion stamped on result', async () => {
    const rules = await repo.loadActiveRule({
      city: 'lahore',
      category: 'easy',
    });
    const fare = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: rules.category,
      city: rules.city,
      rules,
    });
    assert(
      fare.pricingRulesVersion === '2026-09-22:v5a-proof',
      fare.pricingRulesVersion,
    );
  });

  await test('4. Missing rule fails closed', async () => {
    try {
      await repo.loadActiveRule({ city: 'lahore', category: 'missingcat' });
      throw new Error('expected throw');
    } catch (err) {
      assert(
        err instanceof Error &&
          'code' in err &&
          (err as { code: string }).code === 'PRICING_UNAVAILABLE',
        'expected PRICING_UNAVAILABLE',
      );
    }
  });

  await test('5. No pricingSnapshots / rides written by 5A proof', async () => {
    const keys = [...db.store.keys()];
    assert(
      keys.every((k) => !k.startsWith('pricingSnapshots/')),
      'pricingSnapshots must stay empty',
    );
    assert(
      keys.every((k) => !k.startsWith('rides/')),
      'rides must stay empty',
    );
    assert(
      keys.some((k) => k === 'pricingRules/lahore_easy'),
      'pricingRules fixture present',
    );
  });

  console.log(`\n5A unit proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
