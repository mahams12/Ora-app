import { describe, expect, it } from 'vitest';
import { calculateFare } from '../pricing/fare_calculator';
import {
  PricingRulesRepository,
  buildPricingRuleSeed,
  normalizePricingCategory,
  parsePricingRuleDoc,
  pricingRuleDocId,
  resolvePricingRuleCity,
} from '../pricing/pricing_rules_repository';
import { PricingError, PRICING_RULES_COLLECTION } from '../pricing/types';
import { memoryDb } from './helpers/memory_db';

function repo() {
  const db = memoryDb();
  return { db, rules: new PricingRulesRepository(db as never) };
}

describe('pricing rules — identity helpers', () => {
  it('builds {city}_{category} doc ids', () => {
    expect(pricingRuleDocId('lahore', 'easy')).toBe('lahore_easy');
  });

  it('normalizes city via normalizeCitySlug', () => {
    expect(resolvePricingRuleCity('  Lahore ')).toBe('lahore');
  });

  it('rejects missing city', () => {
    expect(() => resolvePricingRuleCity('')).toThrow(PricingError);
    expect(() => resolvePricingRuleCity(null)).toThrow(PricingError);
  });

  it('normalizes category to lowercase slug', () => {
    expect(normalizePricingCategory('Easy')).toBe('easy');
    expect(normalizePricingCategory('zip')).toBe('zip');
  });

  it('rejects unsupported category shapes', () => {
    expect(() => normalizePricingCategory('')).toThrow(PricingError);
    expect(() => normalizePricingCategory('Easy Ride')).toThrow(PricingError);
  });
});

describe('pricing rules repository', () => {
  it('loads valid active rule', async () => {
    const { db, rules } = repo();
    const seed = buildPricingRuleSeed({
      city: 'lahore',
      category: 'easy',
      version: '2026-09-22:v5a',
      baseFare: 100,
      ratePerKm: 20,
      ratePerMin: 5,
      minFare: 150,
      maxFare: 5000,
    });
    db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed });

    const loaded = await rules.loadActiveRule({
      city: 'Lahore',
      category: 'Easy',
    });
    expect(loaded).toMatchObject({
      ruleId: 'lahore_easy',
      city: 'lahore',
      category: 'easy',
      version: '2026-09-22:v5a',
      active: true,
      baseFare: 100,
    });
  });

  it('missing rule fails closed', async () => {
    const { rules } = repo();
    await expect(
      rules.loadActiveRule({ city: 'lahore', category: 'trio' }),
    ).rejects.toMatchObject({
      code: 'PRICING_UNAVAILABLE',
      httpStatus: 503,
    });
  });

  it('inactive rule fails closed', async () => {
    const { db, rules } = repo();
    const seed = buildPricingRuleSeed({
      city: 'lahore',
      category: 'zip',
      version: 'v1',
      baseFare: 80,
      ratePerKm: 15,
      ratePerMin: 4,
      minFare: 100,
      maxFare: 3000,
      active: false,
    });
    db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed, active: false });

    await expect(
      rules.loadActiveRule({ city: 'lahore', category: 'zip' }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });

  it('malformed rule fails closed', async () => {
    const { db, rules } = repo();
    db.seed(PRICING_RULES_COLLECTION, 'lahore_easy', {
      city: 'lahore',
      category: 'easy',
      version: 'v1',
      active: true,
      baseFare: 'nope',
      ratePerKm: 20,
      ratePerMin: 5,
      categoryMultiplier: 1,
      minFare: 100,
      maxFare: 1000,
    });

    await expect(
      rules.loadActiveRule({ city: 'lahore', category: 'easy' }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });

  it('unsupported category rejected before lookup', async () => {
    const { rules } = repo();
    await expect(
      rules.loadActiveRule({ city: 'lahore', category: 'not a cat' }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('version propagates into fare calculation', async () => {
    const { db, rules } = repo();
    const seed = buildPricingRuleSeed({
      city: 'karachi',
      category: 'trio',
      version: 'karachi-trio-v3',
      baseFare: 90,
      ratePerKm: 18,
      ratePerMin: 4,
      minFare: 120,
      maxFare: 4000,
      offerMinRatio: 0.7,
      offerMaxRatio: 2.5,
    });
    db.seed(PRICING_RULES_COLLECTION, seed.ruleId, { ...seed });

    const loaded = await rules.loadActiveRule({
      city: 'karachi',
      category: 'trio',
    });
    const fare = calculateFare({
      distanceKm: 4,
      durationMin: 12,
      category: loaded.category,
      city: loaded.city,
      rules: loaded,
    });
    expect(fare.pricingRulesVersion).toBe('karachi-trio-v3');
    expect(fare.recommendedFareMinor).toBeGreaterThan(0);
  });

  it('parsePricingRuleDoc applies default offer ratios when omitted', () => {
    const doc = parsePricingRuleDoc('lahore_easy', {
      city: 'lahore',
      category: 'easy',
      version: 'v1',
      active: true,
      baseFare: 100,
      ratePerKm: 20,
      ratePerMin: 5,
      categoryMultiplier: 1,
      minFare: 150,
      maxFare: 5000,
    });
    expect(doc.offerMinRatio).toBe(0.7);
    expect(doc.offerMaxRatio).toBe(2.5);
  });

  it('identity mismatch city/category vs fields fails', async () => {
    const { db, rules } = repo();
    db.seed(PRICING_RULES_COLLECTION, 'lahore_easy', {
      city: 'karachi',
      category: 'easy',
      version: 'v1',
      active: true,
      baseFare: 100,
      ratePerKm: 20,
      ratePerMin: 5,
      categoryMultiplier: 1,
      minFare: 150,
      maxFare: 5000,
      offerMinRatio: 0.7,
      offerMaxRatio: 2.5,
    });

    await expect(
      rules.loadActiveRule({ city: 'lahore', category: 'easy' }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });
});
