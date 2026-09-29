/**
 * Phase 5A — pricing domain types.
 *
 * Authority: docs/algorithms/fare-engine.md +
 * docs/implementation/phase-4-5-location-pricing-decision.md
 *
 * Money: fare-engine major units are PKR rupees; persisted results are
 * integer paisas (minor units). Rs 1 = 100 paisas.
 */

export const PRICING_RULES_COLLECTION = 'pricingRules';
export const PRICING_CURRENCY_PKR = 'PKR';

/** MVP demand / night / extras — deferred live signals stay fixed. */
export const MVP_DEMAND_MULT = 1.0;
export const MVP_NIGHT_ADJ = 1.0;
export const MVP_TOLLS_RUPEES = 0;
export const MVP_AIRPORT_FEE_RUPEES = 0;

/** fare-engine demandMult clamp range. */
export const DEMAND_MULT_MIN = 1.0;
export const DEMAND_MULT_MAX = 1.8;

/** Default OfferBoundPolicy ratios (anti-abuse, not the product price). */
export const DEFAULT_OFFER_MIN_RATIO = 0.7;
export const DEFAULT_OFFER_MAX_RATIO = 2.5;

/**
 * Authoritative pricing rule stored at `pricingRules/{city}_{category}`.
 * Major-unit fields are PKR rupees (not paisas), matching fare-engine.md.
 */
export interface PricingRuleDoc {
  /** Document id — `${city}_${category}`. */
  ruleId: string;
  city: string;
  category: string;
  /** Stamped onto every calculation / future snapshot. */
  version: string;
  active: boolean;
  /** Base fare B (PKR rupees). */
  baseFare: number;
  /** Rate per km rKm (PKR rupees). */
  ratePerKm: number;
  /** Rate per minute rMin (PKR rupees). */
  ratePerMin: number;
  /** Category multiplier catMult. */
  categoryMultiplier: number;
  /** Recommendation floor (PKR rupees). */
  minFare: number;
  /** Recommendation ceiling (PKR rupees). */
  maxFare: number;
  /** OfferBoundPolicy min ratio vs recommendedFareMinor. */
  offerMinRatio: number;
  /** OfferBoundPolicy max ratio vs recommendedFareMinor. */
  offerMaxRatio: number;
}

/** Pure calculator inputs (storage-independent). */
export interface FareCalculationInput {
  distanceKm: number;
  durationMin: number;
  category: string;
  city: string;
  rules: PricingRuleDoc;
  /**
   * Optional override; MVP callers pass 1.0 / omit.
   * Always clamped to [1.0, 1.8] per fare-engine.
   */
  demandMult?: number;
}

/** Inputs retained for later pricingSnapshot persistence (5B). */
export interface FareCalculationSnapshotInputs {
  distanceKm: number;
  durationMin: number;
  categoryId: string;
  city: string;
  demandMult: number;
  nightAdj: number;
  tollsMinor: number;
  airportFeeMinor: number;
  ruleId: string;
}

export interface FareCalculationResult {
  recommendedFareMinor: number;
  offerBoundMinMinor: number;
  offerBoundMaxMinor: number;
  currency: typeof PRICING_CURRENCY_PKR;
  pricingRulesVersion: string;
  inputs: FareCalculationSnapshotInputs;
  /** Intermediate major-unit values (debug / tests; not a client API). */
  debug: {
    rawRupees: number;
    roundedRupees: number;
    finalRupees: number;
    appliedDemandMult: number;
    appliedNightAdj: number;
  };
}

export class PricingError extends Error {
  constructor(
    readonly code: string,
    readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'PricingError';
  }
}
