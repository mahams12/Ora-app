import { describe, expect, it } from 'vitest';
import {
  assertOfferSelectableForAssignment,
  assertOfferWithdrawable,
  effectiveOfferStatus,
  isOfferSelectable,
} from '../rides/offer_lifecycle';
import { RideDomainError } from '../rides/types';

describe('offer lifecycle', () => {
  const now = Date.parse('2026-09-09T12:00:00.000Z');

  it('treats pending past expiresAt as EXPIRED at read boundary', () => {
    expect(
      effectiveOfferStatus(
        {
          status: 'PENDING',
          expiresAt: '2026-09-09T11:59:00.000Z',
        },
        now,
      ),
    ).toBe('EXPIRED');
    expect(
      isOfferSelectable(
        {
          status: 'PENDING',
          expiresAt: '2026-09-09T11:59:00.000Z',
        },
        now,
      ),
    ).toBe(false);
  });

  it('allows withdraw only for live PENDING', () => {
    assertOfferWithdrawable(
      { status: 'PENDING', expiresAt: '2026-09-09T12:01:00.000Z' },
      now,
    );
    expect(() =>
      assertOfferWithdrawable(
        { status: 'SELECTED', expiresAt: '2026-09-09T12:01:00.000Z' },
        now,
      ),
    ).toThrow(RideDomainError);
    expect(() =>
      assertOfferWithdrawable(
        { status: 'PENDING', expiresAt: '2026-09-09T11:00:00.000Z' },
        now,
      ),
    ).toThrow(RideDomainError);
  });

  it('blocks assignment of terminal offer statuses', () => {
    expect(() =>
      assertOfferSelectableForAssignment(
        { status: 'WITHDRAWN', expiresAt: '2026-09-09T12:01:00.000Z' },
        now,
      ),
    ).toThrow(RideDomainError);
    expect(() =>
      assertOfferSelectableForAssignment(
        { status: 'SUPERSEDED', expiresAt: '2026-09-09T12:01:00.000Z' },
        now,
      ),
    ).toThrow(RideDomainError);
    expect(() =>
      assertOfferSelectableForAssignment(
        { status: 'EXPIRED', expiresAt: '2026-09-09T11:00:00.000Z' },
        now,
      ),
    ).toThrow(RideDomainError);
  });
});
