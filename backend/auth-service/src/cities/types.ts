/**
 * Server-managed city catalog (Slice 1).
 *
 * Document ID = canonical city id = rides.city = drivers.homeCity = Redis GEO shard.
 * Authority: docs/implementation/n-series/PAKISTAN-CITY-ARCHITECTURE.md
 */

/** Pakistan-only for current product coverage (D-PK-COVERAGE). */
export const CITY_COUNTRY_CODE_PK = 'PK' as const;

export type CityCountryCode = typeof CITY_COUNTRY_CODE_PK;

export interface CityCatalogRecord {
  /** Canonical slug; equals Firestore document id. */
  id: string;
  displayName: string;
  countryCode: CityCountryCode;
  /** When false, future catalog API must not expose for selection. */
  active: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CityCatalogWriteInput {
  id: unknown;
  displayName: unknown;
  countryCode: unknown;
  active: unknown;
}

export class CityCatalogError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'CityCatalogError';
  }
}
