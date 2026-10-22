/**
 * Driver payout derivation — launch policy (2026-10-19).
 *
 * Launch rule (owner-approved): platform fee is NONE — platformFeeMinor = 0,
 * driverPayoutMinor = agreedFareMinor, only when fare/currency data is valid.
 * Non-zero policy shapes (PERCENT_BPS / FLAT_MINOR) are supported by the
 * resolver but NOT activated: no non-zero policy docs are created, and
 * invalid/inconsistent data resolves to UNAVAILABLE with null payout fields.
 *
 * Derived atomically inside the offer-select transaction; completion never
 * recomputes. See docs/design/DRIVER_PAYOUT_MODEL_PLAN.md.
 */

export const FEE_POLICIES_COLLECTION = 'feePolicies';
export const GLOBAL_FEE_POLICY_ID = '_global';
export const LAUNCH_POLICY_VERSION = 'launch-2026-10-19';

export type PlatformFeeType = 'NONE' | 'PERCENT_BPS' | 'FLAT_MINOR';
export type FeePolicyResolution =
  | 'APPLIED' // a feePolicies doc resolved and was applied
  | 'LAUNCH_DEFAULT' // no policy doc — launch rule (fee NONE) applied
  | 'UNAVAILABLE'; // invalid/missing fare or currency — fields null

export interface FeePolicyDoc {
  policyId: string;
  version: string;
  platformFeeType: PlatformFeeType;
  /** Integer basis points (0–10000) when type is PERCENT_BPS. */
  percentBps?: number;
  /** Integer minor units when type is FLAT_MINOR. */
  flatMinor?: number;
  currency: string;
}

export interface FeePolicySnapshot {
  policyId: string;
  policyVersion: string;
  platformFeeType: PlatformFeeType;
  percentBps?: number;
  flatMinor?: number;
  currency: string;
  capturedAt: string;
  resolution: FeePolicyResolution;
}

export interface DerivedPayout {
  driverPayoutMinor: number | null;
  platformFeeMinor: number | null;
  payoutCurrency: string | null;
  feePolicySnapshot: FeePolicySnapshot;
}

function isValidCurrency(code: unknown): code is string {
  return typeof code === 'string' && /^[A-Z]{3}$/.test(code);
}

function isNonNegInt(n: unknown): n is number {
  return typeof n === 'number' && Number.isInteger(n) && n >= 0;
}

/**
 * Platform fee in integer minor units. PERCENT uses floor(fare × bps / 10000)
 * (deterministic, favors driver); result clamped to [0, fareMinor] — a fee
 * can never exceed the fare or produce a negative payout.
 */
export function computePlatformFeeMinor(
  fareMinor: number,
  policy: { platformFeeType: PlatformFeeType; percentBps?: number; flatMinor?: number },
): number {
  let fee: number;
  switch (policy.platformFeeType) {
    case 'PERCENT_BPS':
      if (!isNonNegInt(policy.percentBps) || policy.percentBps > 10_000) {
        return Number.NaN; // invalid policy → caller records UNAVAILABLE
      }
      fee = Math.floor((fareMinor * policy.percentBps) / 10_000);
      break;
    case 'FLAT_MINOR':
      if (!isNonNegInt(policy.flatMinor)) return Number.NaN;
      fee = policy.flatMinor;
      break;
    case 'NONE':
    default:
      fee = 0;
  }
  return Math.min(Math.max(fee, 0), fareMinor);
}

function unavailable(currency: string | null, capturedAt: string): DerivedPayout {
  return {
    driverPayoutMinor: null,
    platformFeeMinor: null,
    payoutCurrency: currency,
    feePolicySnapshot: {
      policyId: 'none',
      policyVersion: LAUNCH_POLICY_VERSION,
      platformFeeType: 'NONE',
      currency: currency ?? 'UNKNOWN',
      capturedAt,
      resolution: 'UNAVAILABLE',
    },
  };
}

/**
 * Derive the immutable payout snapshot. `policy` is the validated
 * FeePolicyDoc or null when no policy doc exists.
 */
export function derivePayoutSnapshot(input: {
  fareMinor: number | null;
  currency: string | null;
  policy: FeePolicyDoc | null;
  capturedAt: string;
}): DerivedPayout {
  const { fareMinor, currency, policy, capturedAt } = input;

  // Fare/currency must be valid before any payout value is recorded.
  if (!isNonNegInt(fareMinor) || !isValidCurrency(currency)) {
    return unavailable(isValidCurrency(currency) ? currency : null, capturedAt);
  }

  if (policy == null) {
    // Launch default — no policy doc: fee NONE, driver receives the fare.
    return {
      driverPayoutMinor: fareMinor,
      platformFeeMinor: 0,
      payoutCurrency: currency,
      feePolicySnapshot: {
        policyId: LAUNCH_POLICY_VERSION,
        policyVersion: LAUNCH_POLICY_VERSION,
        platformFeeType: 'NONE',
        currency,
        capturedAt,
        resolution: 'LAUNCH_DEFAULT',
      },
    };
  }

  // Policy doc exists — its currency must match the offer's currency.
  if (!isValidCurrency(policy.currency) || policy.currency !== currency) {
    return unavailable(currency, capturedAt);
  }

  const fee = computePlatformFeeMinor(fareMinor, policy);
  if (!Number.isFinite(fee)) {
    return unavailable(currency, capturedAt);
  }

  return {
    driverPayoutMinor: fareMinor - fee,
    platformFeeMinor: fee,
    payoutCurrency: currency,
    feePolicySnapshot: {
      policyId: policy.policyId,
      policyVersion: policy.version,
      platformFeeType: policy.platformFeeType,
      ...(policy.percentBps != null ? { percentBps: policy.percentBps } : {}),
      ...(policy.flatMinor != null ? { flatMinor: policy.flatMinor } : {}),
      currency,
      capturedAt,
      resolution: 'APPLIED',
    },
  };
}

/** Validate a raw Firestore doc into a FeePolicyDoc; null if malformed. */
export function parseFeePolicyDoc(
  policyId: string,
  raw: unknown,
): FeePolicyDoc | null {
  if (raw == null || typeof raw !== 'object') return null;
  const doc = raw as Record<string, unknown>;
  const type = doc.platformFeeType;
  if (type !== 'NONE' && type !== 'PERCENT_BPS' && type !== 'FLAT_MINOR') {
    return null;
  }
  if (typeof doc.version !== 'string' || doc.version.length === 0) return null;
  if (!isValidCurrency(doc.currency)) return null;
  return {
    policyId,
    version: doc.version,
    platformFeeType: type,
    ...(typeof doc.percentBps === 'number'
      ? { percentBps: doc.percentBps }
      : {}),
    ...(typeof doc.flatMinor === 'number' ? { flatMinor: doc.flatMinor } : {}),
    currency: doc.currency,
  };
}
