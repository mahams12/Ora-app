import type { Firestore } from 'firebase-admin/firestore';
import { RideDomainError, type PricingSnapshotDoc } from './types';

export async function loadPricingSnapshot(
  db: Firestore,
  snapshotId: string,
  now: Date,
): Promise<PricingSnapshotDoc> {
  if (!snapshotId || typeof snapshotId !== 'string') {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'pricingSnapshotId is required.',
    );
  }

  const snap = await db.collection('pricingSnapshots').doc(snapshotId).get();
  if (!snap.exists) {
    throw new RideDomainError(
      'PRICING_SNAPSHOT_EXPIRED',
      422,
      'Pricing snapshot not found or expired.',
    );
  }

  const data = snap.data() as PricingSnapshotDoc;
  const expiresAt = Date.parse(data.expiresAt);
  if (!Number.isFinite(expiresAt) || expiresAt <= now.getTime()) {
    throw new RideDomainError(
      'PRICING_SNAPSHOT_EXPIRED',
      422,
      'Pricing snapshot has expired.',
    );
  }

  if (
    typeof data.recommendedFareMinor !== 'number' ||
    typeof data.offerBoundMinMinor !== 'number' ||
    typeof data.offerBoundMaxMinor !== 'number' ||
    data.currency !== 'PKR'
  ) {
    throw new RideDomainError(
      'VALIDATION_ERROR',
      400,
      'Pricing snapshot is malformed.',
    );
  }

  return { ...data, snapshotId };
}

export function assertOfferWithinBounds(
  amountMinor: number,
  snapshot: PricingSnapshotDoc,
): void {
  if (
    amountMinor < snapshot.offerBoundMinMinor ||
    amountMinor > snapshot.offerBoundMaxMinor
  ) {
    throw new RideDomainError(
      'FARE_OUT_OF_BOUNDS',
      422,
      'Offer amount is outside allowed bounds for this pricing snapshot.',
    );
  }
}
