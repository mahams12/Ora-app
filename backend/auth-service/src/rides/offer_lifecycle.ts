import { RideDomainError, type OfferStatus, type RideOfferDoc } from './types';

/** Read-boundary expiry: PENDING past expiresAt is treated as EXPIRED. */
export function effectiveOfferStatus(
  offer: Pick<RideOfferDoc, 'status' | 'expiresAt'>,
  nowMs: number,
): OfferStatus {
  if (
    offer.status === 'PENDING' &&
    Date.parse(offer.expiresAt) <= nowMs
  ) {
    return 'EXPIRED';
  }
  return offer.status;
}

export function isOfferSelectable(
  offer: Pick<RideOfferDoc, 'status' | 'expiresAt'>,
  nowMs: number,
): boolean {
  return effectiveOfferStatus(offer, nowMs) === 'PENDING';
}

export function assertOfferWithdrawable(
  offer: Pick<RideOfferDoc, 'status' | 'expiresAt'>,
  nowMs: number,
): void {
  const status = effectiveOfferStatus(offer, nowMs);
  if (status === 'WITHDRAWN') {
    return;
  }
  if (status === 'EXPIRED') {
    throw new RideDomainError('OFFER_EXPIRED', 422, 'Offer has expired.');
  }
  if (status !== 'PENDING') {
    throw new RideDomainError(
      'OFFER_NOT_SELECTABLE',
      422,
      'Only pending offers can be withdrawn.',
    );
  }
}

export function assertOfferSelectableForAssignment(
  offer: Pick<RideOfferDoc, 'status' | 'expiresAt'>,
  nowMs: number,
): void {
  const status = effectiveOfferStatus(offer, nowMs);
  if (status === 'EXPIRED') {
    throw new RideDomainError('OFFER_EXPIRED', 422, 'Offer has expired.');
  }
  if (status !== 'PENDING') {
    throw new RideDomainError(
      'OFFER_NOT_SELECTABLE',
      422,
      'Offer is not selectable.',
    );
  }
}
