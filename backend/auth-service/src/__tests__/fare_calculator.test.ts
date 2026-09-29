import { describe, expect, it } from 'vitest';
import {
  calculateFare,
  clampDemandMult,
  computeOfferBoundsMinor,
  roundToRs10,
  rupeesToMinor,
} from '../pricing/fare_calculator';
import { buildPricingRuleSeed } from '../pricing/pricing_rules_repository';
import { PricingError, type PricingRuleDoc } from '../pricing/types';

function easyLahore(overrides: Partial<PricingRuleDoc> = {}): PricingRuleDoc {
  return {
    ...buildPricingRuleSeed({
      city: 'lahore',
      category: 'easy',
      version: '2026-09-22:v5a-test',
      baseFare: 100,
      ratePerKm: 20,
      ratePerMin: 5,
      categoryMultiplier: 1,
      minFare: 150,
      maxFare: 5000,
      offerMinRatio: 0.7,
      offerMaxRatio: 2.5,
    }),
    ...overrides,
  };
}

describe('fare calculator — helpers', () => {
  it('rounds to nearest Rs 10', () => {
    expect(roundToRs10(0)).toBe(0);
    expect(roundToRs10(344)).toBe(340);
    expect(roundToRs10(345)).toBe(350);
    expect(roundToRs10(349.9)).toBe(350);
    expect(roundToRs10(5)).toBe(10);
    expect(roundToRs10(4.9)).toBe(0);
  });

  it('converts rupees to integer paisas', () => {
    expect(rupeesToMinor(340)).toBe(34000);
    expect(rupeesToMinor(1)).toBe(100);
    expect(rupeesToMinor(0)).toBe(0);
  });

  it('clamps demandMult to [1.0, 1.8]', () => {
    expect(clampDemandMult(0.5)).toBe(1.0);
    expect(clampDemandMult(1.0)).toBe(1.0);
    expect(clampDemandMult(1.2)).toBe(1.2);
    expect(clampDemandMult(2.0)).toBe(1.8);
  });
});

describe('fare calculator — calculateFare', () => {
  it('1. normal distance/time calculation (worked example)', () => {
    // B=100, D=5.8, rKm=20, T=14, rMin=5 → 100+116+70=286
    // ×1 ×1 ×1 = 286 → round 290 → clamp 290 → 29000 minor
    // bounds: 20300 .. 72500
    const result = calculateFare({
      distanceKm: 5.8,
      durationMin: 14,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore(),
    });
    expect(result.recommendedFareMinor).toBe(29000);
    expect(result.offerBoundMinMinor).toBe(20300);
    expect(result.offerBoundMaxMinor).toBe(72500);
    expect(result.currency).toBe('PKR');
    expect(result.pricingRulesVersion).toBe('2026-09-22:v5a-test');
    expect(result.inputs).toMatchObject({
      distanceKm: 5.8,
      durationMin: 14,
      categoryId: 'easy',
      city: 'lahore',
      demandMult: 1.0,
      nightAdj: 1.0,
      tollsMinor: 0,
      airportFeeMinor: 0,
    });
    expect(result.debug.finalRupees).toBe(290);
  });

  it('2. zero distance rejected', () => {
    expect(() =>
      calculateFare({
        distanceKm: 0,
        durationMin: 10,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
    try {
      calculateFare({
        distanceKm: 0,
        durationMin: 10,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore(),
      });
    } catch (e) {
      expect(e).toMatchObject({ code: 'VALIDATION_ERROR' });
    }
  });

  it('3. negative distance rejected', () => {
    expect(() =>
      calculateFare({
        distanceKm: -1,
        durationMin: 10,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
  });

  it('4. negative duration rejected', () => {
    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: -2,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
  });

  it('5. category multiplier applied', () => {
    const base = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ categoryMultiplier: 1 }),
    });
    const boosted = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ categoryMultiplier: 1.5 }),
    });
    // raw 1x: 100+100+50=250 → 250; 1.5x: 375 → 380
    expect(base.debug.finalRupees).toBe(250);
    expect(boosted.debug.finalRupees).toBe(380);
    expect(boosted.recommendedFareMinor).toBeGreaterThan(base.recommendedFareMinor);
  });

  it('6. minimum fare clamp', () => {
    const result = calculateFare({
      distanceKm: 0.1,
      durationMin: 0.1,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ minFare: 200, maxFare: 5000 }),
    });
    // raw ≈ 100+2+0.5=102.5 → round 100 → clamp to 200
    expect(result.debug.roundedRupees).toBe(100);
    expect(result.debug.finalRupees).toBe(200);
    expect(result.recommendedFareMinor).toBe(20000);
  });

  it('7. maximum fare clamp', () => {
    const result = calculateFare({
      distanceKm: 100,
      durationMin: 120,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ maxFare: 400 }),
    });
    // raw 100+2000+600=2700 → round 2700 → clamp 400
    expect(result.debug.finalRupees).toBe(400);
    expect(result.recommendedFareMinor).toBe(40000);
  });

  it('8. demand multiplier defaults to 1.0 and clamps', () => {
    const mvp = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore(),
    });
    expect(mvp.debug.appliedDemandMult).toBe(1.0);

    const high = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore(),
      demandMult: 9,
    });
    expect(high.debug.appliedDemandMult).toBe(1.8);
    expect(high.recommendedFareMinor).toBeGreaterThan(mvp.recommendedFareMinor);

    const low = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore(),
      demandMult: 0.2,
    });
    expect(low.debug.appliedDemandMult).toBe(1.0);
    expect(low.recommendedFareMinor).toBe(mvp.recommendedFareMinor);
  });

  it('9. Rs-10 rounding boundary', () => {
    // Craft raw to land near .5 Rs-10 boundary via known inputs.
    // B=100, D=1, rKm=20, T=1, rMin=5 → 125 → round 130
    const a = calculateFare({
      distanceKm: 1,
      durationMin: 1,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ minFare: 0, maxFare: 5000 }),
    });
    expect(a.debug.rawRupees).toBe(125);
    expect(a.debug.roundedRupees).toBe(130);

    // 124 → 120
    const b = calculateFare({
      distanceKm: 1,
      durationMin: 0.8,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ minFare: 0, maxFare: 5000 }),
    });
    expect(b.debug.rawRupees).toBe(124);
    expect(b.debug.roundedRupees).toBe(120);
  });

  it('10. PKR minor-unit conversion (Rs 340 → 34000)', () => {
    expect(rupeesToMinor(340)).toBe(34000);
    const result = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({
        baseFare: 200,
        ratePerKm: 20,
        ratePerMin: 4,
        minFare: 0,
        maxFare: 10000,
      }),
    });
    // 200+100+40=340 → 34000
    expect(result.debug.finalRupees).toBe(340);
    expect(result.recommendedFareMinor).toBe(34000);
  });

  it('11–12. OfferBoundPolicy min/max ratios', () => {
    const result = calculateFare({
      distanceKm: 5,
      durationMin: 10,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({
        baseFare: 200,
        ratePerKm: 20,
        ratePerMin: 4,
        minFare: 0,
        maxFare: 10000,
        offerMinRatio: 0.7,
        offerMaxRatio: 2.5,
      }),
    });
    expect(result.recommendedFareMinor).toBe(34000);
    expect(result.offerBoundMinMinor).toBe(23800);
    expect(result.offerBoundMaxMinor).toBe(85000);

    const bounds = computeOfferBoundsMinor(34000, 0.7, 2.5);
    expect(bounds).toEqual({
      offerBoundMinMinor: 23800,
      offerBoundMaxMinor: 85000,
    });
  });

  it('13. rules version propagation', () => {
    const result = calculateFare({
      distanceKm: 3,
      durationMin: 8,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ version: 'rules-v9' }),
    });
    expect(result.pricingRulesVersion).toBe('rules-v9');
  });

  it('14. missing / empty category rejected', () => {
    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: '',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
  });

  it('15. missing rules / inactive fail closed', () => {
    try {
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore({ active: false }),
      });
      expect.unreachable();
    } catch (e) {
      expect(e).toMatchObject({ code: 'PRICING_UNAVAILABLE', httpStatus: 503 });
    }
  });

  it('16. invalid rules fail closed', () => {
    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore({ minFare: 900, maxFare: 100 }),
      }),
    ).toThrow(PricingError);

    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore({ categoryMultiplier: 0 }),
      }),
    ).toThrow(PricingError);

    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore({ version: '' }),
      }),
    ).toThrow(PricingError);
  });

  it('17. very small route still produces positive fare via minFare', () => {
    const result = calculateFare({
      distanceKm: 0.01,
      durationMin: 0.01,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ minFare: 150 }),
    });
    expect(result.recommendedFareMinor).toBe(15000);
    expect(result.offerBoundMinMinor).toBeLessThanOrEqual(
      result.recommendedFareMinor,
    );
    expect(result.offerBoundMaxMinor).toBeGreaterThanOrEqual(
      result.recommendedFareMinor,
    );
  });

  it('18. long route', () => {
    const result = calculateFare({
      distanceKm: 80,
      durationMin: 100,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ maxFare: 10000 }),
    });
    // 100+1600+500=2200
    expect(result.debug.finalRupees).toBe(2200);
    expect(result.recommendedFareMinor).toBe(220000);
  });

  it('19. large duration', () => {
    const result = calculateFare({
      distanceKm: 10,
      durationMin: 300,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore({ maxFare: 20000 }),
    });
    // 100+200+1500=1800
    expect(result.debug.finalRupees).toBe(1800);
    expect(result.recommendedFareMinor).toBe(180000);
  });

  it('20. determinism — same input → identical result', () => {
    const input = {
      distanceKm: 7.25,
      durationMin: 18.5,
      category: 'easy',
      city: 'lahore',
      rules: easyLahore(),
    };
    const a = calculateFare(input);
    const b = calculateFare(input);
    expect(a).toEqual(b);
  });

  it('category mismatch vs rules fails', () => {
    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 8,
        category: 'zip',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
  });

  it('zero duration rejected', () => {
    expect(() =>
      calculateFare({
        distanceKm: 3,
        durationMin: 0,
        category: 'easy',
        city: 'lahore',
        rules: easyLahore(),
      }),
    ).toThrow(PricingError);
  });
});
