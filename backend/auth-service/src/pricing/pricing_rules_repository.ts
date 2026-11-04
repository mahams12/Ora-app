/**
 * Firestore-backed pricingRules loader — Phase 5A.
 *
 * Collection: pricingRules/{city}_{category}
 * Client read/write: denied (firestore.rules). Admin SDK / backend only.
 *
 * Separated from the pure calculator: storage → validated PricingRuleDoc →
 * calculateFare(...).
 */

import type { Firestore } from 'firebase-admin/firestore';
import { normalizeCitySlug } from '../redis/types';
import {
  DEFAULT_OFFER_MAX_RATIO,
  DEFAULT_OFFER_MIN_RATIO,
  PRICING_RULES_COLLECTION,
  PricingError,
  type PricingRuleDoc,
} from './types';
import { assertPricingRuleUsable } from './fare_calculator';

export function normalizePricingCategory(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'category is required.',
    );
  }
  const category = raw.trim().toLowerCase();
  if (category.length === 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'category is required.',
    );
  }
  if (!/^[a-z0-9]+(?:[_-][a-z0-9]+)*$/.test(category)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'category must be a lowercase slug.',
    );
  }
  return category;
}

export function resolvePricingRuleCity(raw: unknown): string {
  const slug = normalizeCitySlug(raw);
  if (!slug) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'city is required.',
    );
  }
  return slug;
}

/** Document id: `{city}_{category}` e.g. `lahore_easy`. */
export function pricingRuleDocId(city: string, category: string): string {
  return `${city}_${category}`;
}

function requireFiniteNumber(
  data: Record<string, unknown>,
  field: string,
): number {
  const v = data[field];
  if (typeof v !== 'number' || !Number.isFinite(v)) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      `Pricing rule field ${field} is malformed.`,
    );
  }
  return v;
}

function requireString(data: Record<string, unknown>, field: string): string {
  const v = data[field];
  if (typeof v !== 'string' || v.trim().length === 0) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      `Pricing rule field ${field} is malformed.`,
    );
  }
  return v.trim();
}

/**
 * Parse + validate a Firestore document into PricingRuleDoc.
 * Missing/malformed/inactive → fail closed.
 */
export function parsePricingRuleDoc(
  ruleId: string,
  raw: Record<string, unknown> | undefined,
): PricingRuleDoc {
  if (!raw) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rules are unavailable for this city/category.',
    );
  }

  if (raw.active !== true) {
    throw new PricingError(
      'PRICING_UNAVAILABLE',
      503,
      'Pricing rules are inactive.',
    );
  }

  const city = requireString(raw, 'city');
  const category = requireString(raw, 'category');
  const version = requireString(raw, 'version');

  const doc: PricingRuleDoc = {
    ruleId,
    city,
    category,
    version,
    active: true,
    baseFare: requireFiniteNumber(raw, 'baseFare'),
    ratePerKm: requireFiniteNumber(raw, 'ratePerKm'),
    ratePerMin: requireFiniteNumber(raw, 'ratePerMin'),
    categoryMultiplier: requireFiniteNumber(raw, 'categoryMultiplier'),
    minFare: requireFiniteNumber(raw, 'minFare'),
    maxFare: requireFiniteNumber(raw, 'maxFare'),
    offerMinRatio:
      raw.offerMinRatio === undefined
        ? DEFAULT_OFFER_MIN_RATIO
        : requireFiniteNumber(raw, 'offerMinRatio'),
    offerMaxRatio:
      raw.offerMaxRatio === undefined
        ? DEFAULT_OFFER_MAX_RATIO
        : requireFiniteNumber(raw, 'offerMaxRatio'),
    perStopFeeMinor:
      raw.perStopFeeMinor === undefined
        ? undefined
        : requireFiniteNumber(raw, 'perStopFeeMinor'),
    shoppingServiceFeeMinor:
      raw.shoppingServiceFeeMinor === undefined
        ? undefined
        : requireFiniteNumber(raw, 'shoppingServiceFeeMinor'),
  };

  assertPricingRuleUsable(doc);
  return doc;
}

export class PricingRulesRepository {
  private readonly cacheTtlMs: number;
  private readonly cache = new Map<
    string,
    { rule: PricingRuleDoc; expiresAtMs: number }
  >();
  private hits = 0;
  private misses = 0;

  constructor(
    private readonly db: Firestore,
    options?: { cacheTtlMs?: number },
  ) {
    // Default 0 = uncached (legacy behavior). Rules are admin-seeded and
    // change rarely; a short TTL cuts one billed read per estimate.
    this.cacheTtlMs = options?.cacheTtlMs ?? 0;
  }

  cacheStats(): { hits: number; misses: number; size: number } {
    return { hits: this.hits, misses: this.misses, size: this.cache.size };
  }

  /**
   * Load the active rule for city + category.
   * Missing / inactive / malformed → PricingError (fail closed).
   */
  async loadActiveRule(input: {
    city: unknown;
    category: unknown;
  }): Promise<PricingRuleDoc> {
    const city = resolvePricingRuleCity(input.city);
    const category = normalizePricingCategory(input.category);
    const ruleId = pricingRuleDocId(city, category);

    const cached = this.cache.get(ruleId);
    if (cached && cached.expiresAtMs > Date.now()) {
      this.hits += 1;
      return cached.rule;
    }
    this.misses += 1;

    const snap = await this.db
      .collection(PRICING_RULES_COLLECTION)
      .doc(ruleId)
      .get();

    if (!snap.exists) {
      throw new PricingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing rules are unavailable for this city/category.',
      );
    }

    const data = snap.data() as Record<string, unknown> | undefined;
    const rule = parsePricingRuleDoc(ruleId, data);

    // Fail closed if stored city/category disagree with lookup key.
    if (rule.city !== city || rule.category !== category) {
      throw new PricingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing rule identity does not match document id.',
      );
    }

    if (this.cacheTtlMs > 0) {
      this.cache.set(ruleId, {
        rule,
        expiresAtMs: Date.now() + this.cacheTtlMs,
      });
    }
    return rule;
  }
}

/**
 * Server/admin seed helper for tests and ops — never exposed to clients.
 *
 * UNITS: baseFare, ratePerKm, ratePerMin, minFare and maxFare are whole-PKR
 * rupee values, NOT paisa/minor units. Seeding paisa-scale numbers (e.g.
 * ratePerKm: 20000 meaning Rs 200) inflates fares ~100× — a past local test
 * seed produced Rs 136,470 for a 5.9 km ride this way. The calculator applies
 * the stored values verbatim as rupees.
 */
export function buildPricingRuleSeed(input: {
  city: string;
  category: string;
  version: string;
  baseFare: number;
  ratePerKm: number;
  ratePerMin: number;
  categoryMultiplier?: number;
  minFare: number;
  maxFare: number;
  offerMinRatio?: number;
  offerMaxRatio?: number;
  active?: boolean;
  /** Ora Courier v2 — fixed surcharge per stop beyond the first and last. */
  perStopFeeMinor?: number;
  /** Ora Courier v2 — fixed Buy & Deliver service surcharge. */
  shoppingServiceFeeMinor?: number;
}): PricingRuleDoc {
  const city = resolvePricingRuleCity(input.city);
  const category = normalizePricingCategory(input.category);
  const ruleId = pricingRuleDocId(city, category);
  const doc: PricingRuleDoc = {
    ruleId,
    city,
    category,
    version: input.version,
    active: input.active !== false,
    baseFare: input.baseFare,
    ratePerKm: input.ratePerKm,
    ratePerMin: input.ratePerMin,
    categoryMultiplier: input.categoryMultiplier ?? 1,
    minFare: input.minFare,
    maxFare: input.maxFare,
    offerMinRatio: input.offerMinRatio ?? DEFAULT_OFFER_MIN_RATIO,
    offerMaxRatio: input.offerMaxRatio ?? DEFAULT_OFFER_MAX_RATIO,
    ...(input.perStopFeeMinor !== undefined
      ? { perStopFeeMinor: input.perStopFeeMinor }
      : {}),
    ...(input.shoppingServiceFeeMinor !== undefined
      ? { shoppingServiceFeeMinor: input.shoppingServiceFeeMinor }
      : {}),
  };
  if (doc.active) {
    assertPricingRuleUsable(doc);
  }
  return doc;
}
