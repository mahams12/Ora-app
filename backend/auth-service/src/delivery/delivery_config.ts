/**
 * Ora Courier v2 — server-side delivery configuration.
 *
 * Single Firestore doc `deliveryConfig/global` (server-only via rules);
 * safe built-in defaults when absent so local/emulator runs always work.
 * Values gate create-time limits — they are not pricing authority.
 */

import type { Firestore } from 'firebase-admin/firestore';
import {
  DELIVERY_CONFIG_COLLECTION,
  DELIVERY_CONFIG_DOC_ID,
} from '../rides/types';

export interface DeliveryConfig {
  /** Max itinerary stops (including first pickup and final dropoff). */
  maxStops: number;
  /** buy_deliver — hard per-booking shopping spend cap (PKR minor). */
  maxShoppingBudgetMinor: number;
  /** Hours after completion during which a dispute may be opened. */
  disputeWindowHours: number;
  /** Feature gates. */
  enableBuyDeliver: boolean;
  enableCourierV2: boolean;
  /** Server-enforced prohibited shopping items (lowercase substrings). */
  prohibitedList: string[];
}

export const DEFAULT_DELIVERY_CONFIG: DeliveryConfig = {
  maxStops: 5,
  maxShoppingBudgetMinor: 300000, // Rs 3,000
  disputeWindowHours: 48,
  enableBuyDeliver: true,
  enableCourierV2: true,
  prohibitedList: [
    'narcotic',
    'opioid',
    'morphine',
    'tramadol',
    'benzodiazepine',
    'xanax',
    'valium',
    'weapon',
    'ammunition',
    'explosive',
    'alcohol',
    'liquor',
    'tobacco',
    'cigarette',
    'vape',
  ],
};

function intInRange(v: unknown, min: number, max: number): number | null {
  if (typeof v !== 'number' || !Number.isInteger(v)) return null;
  if (v < min || v > max) return null;
  return v;
}

/** Load config; absent/malformed fields fall back to defaults (fail-open for limits already enforced elsewhere, fail-closed on shape). */
export async function loadDeliveryConfig(
  db: Firestore,
): Promise<DeliveryConfig> {
  let data: Record<string, unknown> | undefined;
  try {
    const snap = await db
      .collection(DELIVERY_CONFIG_COLLECTION)
      .doc(DELIVERY_CONFIG_DOC_ID)
      .get();
    data = snap.exists ? (snap.data() as Record<string, unknown>) : undefined;
  } catch {
    return { ...DEFAULT_DELIVERY_CONFIG };
  }
  if (!data) return { ...DEFAULT_DELIVERY_CONFIG };

  const cfg = { ...DEFAULT_DELIVERY_CONFIG };
  const maxStops = intInRange(data.maxStops, 2, 10);
  if (maxStops != null) cfg.maxStops = maxStops;
  const budget = intInRange(data.maxShoppingBudgetMinor, 1, 100000000);
  if (budget != null) cfg.maxShoppingBudgetMinor = budget;
  const hours = intInRange(data.disputeWindowHours, 1, 24 * 30);
  if (hours != null) cfg.disputeWindowHours = hours;
  if (typeof data.enableBuyDeliver === 'boolean') {
    cfg.enableBuyDeliver = data.enableBuyDeliver;
  }
  if (typeof data.enableCourierV2 === 'boolean') {
    cfg.enableCourierV2 = data.enableCourierV2;
  }
  if (
    Array.isArray(data.prohibitedList) &&
    data.prohibitedList.every((x) => typeof x === 'string')
  ) {
    cfg.prohibitedList = (data.prohibitedList as string[]).map((s) =>
      s.trim().toLowerCase(),
    );
  }
  return cfg;
}

/** True when a shopping-list item name matches the prohibited list. */
export function isProhibitedItem(
  name: string,
  cfg: DeliveryConfig,
): boolean {
  const n = name.trim().toLowerCase();
  if (!n) return false;
  return cfg.prohibitedList.some((p) => p && n.includes(p));
}
