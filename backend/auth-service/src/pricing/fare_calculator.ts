/**
 * Pure fare calculator — Phase 5A.
 *
 * Formula (docs/algorithms/fare-engine.md) — do not invent a different model:
 *
 *   R = (B + D×rKm + T×rMin + tolls + airportFee)
 *       × catMult
 *       × clamp(demandMult, 1.0, 1.8)
 *       × nightAdj
 *   R_rounded = round(R / 10) × 10
 *   R_final = clamp(R_rounded, minFare, maxFare)
 *   recommendedFareMinor = R_final × 100   // integer paisas
 *
 * OfferBoundPolicy (anti-abuse, not the product price):
 *   offerBoundMinMinor = round(recommendedFareMinor × offerMinRatio)
 *   offerBoundMaxMinor = round(recommendedFareMinor × offerMaxRatio)
 *
 * MVP fixed inputs (freeze): demandMult=1.0, nightAdj=1.0, tolls=0, airportFee=0.
 * No Firestore / Redis / HTTP / env access in this module.
 */

import {
  DEMAND_MULT_MAX,
  DEMAND_MULT_MIN,
  MVP_AIRPORT_FEE_RUPEES,
  MVP_DEMAND_MULT,
  MVP_NIGHT_ADJ,
  MVP_TOLLS_RUPEES,
  PRICING_CURRENCY_PKR,
  PricingError,
  type FareCalculationInput,
  type FareCalculationResult,
  type PricingRuleDoc,
} from './types';

function assertFiniteNumber(value: unknown, field: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field} must be a finite number.`,
    );
  }
  return value;
}

function assertPositiveRouteMetric(value: unknown, field: string): number {
  const n = assertFiniteNumber(value, field);
  if (n <= 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field} must be greater than zero.`,
    );
  }
  return n;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** Round PKR rupees to nearest Rs 10 (fare-engine). */
export function roundToRs10(rupees: number): number {
  return Math.round(rupees / 10) * 10;
}

/** PKR rupees → integer paisas (Rs 1 = 100). */
export function rupeesToMinor(rupees: number): number {
  if (!Number.isFinite(rupees)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'rupees amount must be finite.',
    );
  }
  return Math.round(rupees) * 100;
}

export function clampDemandMult(raw: number): number {
  return clamp(raw, DEMAND_MULT_MIN, DEMAND_MULT_MAX);
}

/**
 * Validate a rule object already loaded from storage.
 * Does not touch Firestore.
 */
export function assertPricingRuleUsable(rules: PricingRuleDoc): void {
  if (!rules || typeof rules !== 'object') {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rules are unavailable.',
    );
  }
  if (rules.active !== true) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rules are inactive.',
    );
  }
  if (typeof rules.version !== 'string' || rules.version.trim().length === 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rules version is missing.',
    );
  }

  const numericFields: Array<keyof PricingRuleDoc> = [
    'baseFare',
    'ratePerKm',
    'ratePerMin',
    'categoryMultiplier',
    'minFare',
    'maxFare',
    'offerMinRatio',
    'offerMaxRatio',
  ];
  for (const field of numericFields) {
    const v = rules[field];
    if (typeof v !== 'number' || !Number.isFinite(v)) {
      throw new PricingError(
        'PRICING_UNAVAILABLE',
        503,
        `Pricing rule field ${String(field)} is malformed.`,
      );
    }
  }

  if (rules.baseFare < 0 || rules.ratePerKm < 0 || rules.ratePerMin < 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rule rates must not be negative.',
    );
  }
  if (rules.categoryMultiplier <= 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'categoryMultiplier must be greater than zero.',
    );
  }
  if (rules.minFare < 0 || rules.maxFare < 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'minFare/maxFare must not be negative.',
    );
  }
  if (rules.minFare > rules.maxFare) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'minFare must not exceed maxFare.',
    );
  }
  if (rules.offerMinRatio <= 0 || rules.offerMaxRatio <= 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'OfferBoundPolicy ratios must be greater than zero.',
    );
  }
  if (rules.offerMinRatio > rules.offerMaxRatio) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'offerMinRatio must not exceed offerMaxRatio.',
    );
  }
}

export function computeOfferBoundsMinor(
  recommendedFareMinor: number,
  offerMinRatio: number,
  offerMaxRatio: number,
): { offerBoundMinMinor: number; offerBoundMaxMinor: number } {
  if (
    !Number.isInteger(recommendedFareMinor) ||
    recommendedFareMinor <= 0
  ) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'recommendedFareMinor must be a positive integer.',
    );
  }
  const offerBoundMinMinor = Math.round(recommendedFareMinor * offerMinRatio);
  const offerBoundMaxMinor = Math.round(recommendedFareMinor * offerMaxRatio);
  if (
    offerBoundMinMinor <= 0 ||
    offerBoundMaxMinor < offerBoundMinMinor ||
    offerBoundMinMinor > recommendedFareMinor ||
    offerBoundMaxMinor < recommendedFareMinor
  ) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'OfferBoundPolicy produced invalid bounds for recommended fare.',
    );
  }
  return { offerBoundMinMinor, offerBoundMaxMinor };
}

/**
 * Deterministic recommended-fare + offer bounds from explicit inputs + rules.
 */
export function calculateFare(
  input: FareCalculationInput,
): FareCalculationResult {
  const distanceKm = assertPositiveRouteMetric(input.distanceKm, 'distanceKm');
  const durationMin = assertPositiveRouteMetric(input.durationMin, 'durationMin');

  if (typeof input.category !== 'string' || input.category.trim().length === 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'category is required.',
    );
  }
  if (typeof input.city !== 'string' || input.city.trim().length === 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'city is required.',
    );
  }

  assertPricingRuleUsable(input.rules);

  const category = input.category.trim();
  const city = input.city.trim();
  if (input.rules.category !== category) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'category does not match loaded pricing rules.',
    );
  }
  if (input.rules.city !== city) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'city does not match loaded pricing rules.',
    );
  }

  const demandRaw =
    input.demandMult === undefined
      ? MVP_DEMAND_MULT
      : assertFiniteNumber(input.demandMult, 'demandMult');
  if (demandRaw <= 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'demandMult must be greater than zero.',
    );
  }
  const appliedDemandMult = clampDemandMult(demandRaw);
  const appliedNightAdj = MVP_NIGHT_ADJ;
  const tolls = MVP_TOLLS_RUPEES;
  const airportFee = MVP_AIRPORT_FEE_RUPEES;

  const { rules } = input;
  const rawRupees =
    (rules.baseFare +
      distanceKm * rules.ratePerKm +
      durationMin * rules.ratePerMin +
      tolls +
      airportFee) *
    rules.categoryMultiplier *
    appliedDemandMult *
    appliedNightAdj;

  const roundedRupees = roundToRs10(rawRupees);
  const finalRupees = clamp(roundedRupees, rules.minFare, rules.maxFare);
  const recommendedFareMinor = rupeesToMinor(finalRupees);

  if (recommendedFareMinor <= 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Calculated recommended fare is not positive.',
    );
  }

  const { offerBoundMinMinor, offerBoundMaxMinor } = computeOfferBoundsMinor(
    recommendedFareMinor,
    rules.offerMinRatio,
    rules.offerMaxRatio,
  );

  return {
    recommendedFareMinor,
    offerBoundMinMinor,
    offerBoundMaxMinor,
    currency: PRICING_CURRENCY_PKR,
    pricingRulesVersion: rules.version,
    inputs: {
      distanceKm,
      durationMin,
      categoryId: category,
      city,
      demandMult: appliedDemandMult,
      nightAdj: appliedNightAdj,
      tollsMinor: rupeesToMinor(tolls),
      airportFeeMinor: rupeesToMinor(airportFee),
      ruleId: rules.ruleId,
    },
    debug: {
      rawRupees,
      roundedRupees,
      finalRupees,
      appliedDemandMult,
      appliedNightAdj,
    },
  };
}
