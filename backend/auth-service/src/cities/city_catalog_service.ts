import type { Firestore } from 'firebase-admin/firestore';
import { normalizeCitySlug } from '../redis/types';
import {
  CITY_COUNTRY_CODE_PK,
  CityCatalogError,
  type CityCatalogRecord,
  type CityCatalogWriteInput,
  type CityCountryCode,
} from './types';

export const CITIES_COLLECTION = 'cities';

/**
 * After normalizeCitySlug: slug-shaped ids only (no spaces / mixed case leftovers).
 * Validation only — does not invent a second normalizer.
 */
const CANONICAL_CITY_ID_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

function assertCanonicalCityId(id: string): void {
  if (!CANONICAL_CITY_ID_RE.test(id)) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city id must be a lowercase slug (a-z, 0-9, hyphen).',
    );
  }
}

function parseDisplayName(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'displayName is required.',
    );
  }
  const displayName = raw.trim();
  if (displayName.length === 0) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'displayName is required.',
    );
  }
  return displayName;
}

function parseCountryCode(raw: unknown): CityCountryCode {
  if (raw !== CITY_COUNTRY_CODE_PK) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'countryCode must be PK.',
    );
  }
  return CITY_COUNTRY_CODE_PK;
}

function parseActive(raw: unknown): boolean {
  if (typeof raw !== 'boolean') {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'active must be a boolean.',
    );
  }
  return raw;
}

/**
 * Resolve write/read id: normalizeCitySlug first, then reject empty / non-slug shape.
 * Writers may pass mixed-case or padded ids; storage id is always normalized.
 */
export function resolveCanonicalCityId(raw: unknown): string {
  if (raw === undefined || raw === null) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city id is required.',
    );
  }
  const normalized = normalizeCitySlug(raw);
  if (normalized == null) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city id is required.',
    );
  }
  assertCanonicalCityId(normalized);
  return normalized;
}

function parseStored(data: Record<string, unknown>, id: string): CityCatalogRecord {
  if (typeof data.displayName !== 'string' || data.displayName.trim().length === 0) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city catalog record is malformed.',
    );
  }
  if (data.countryCode !== CITY_COUNTRY_CODE_PK) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city catalog record is malformed.',
    );
  }
  if (typeof data.active !== 'boolean') {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      'city catalog record is malformed.',
    );
  }
  return {
    id,
    displayName: data.displayName,
    countryCode: CITY_COUNTRY_CODE_PK,
    active: data.active,
    createdAt: typeof data.createdAt === 'string' ? data.createdAt : '',
    updatedAt: typeof data.updatedAt === 'string' ? data.updatedAt : '',
  };
}

/**
 * Admin-SDK-only city catalog repository.
 * No HTTP surface in Slice 1.
 */
export class CityCatalogService {
  constructor(private readonly db: Firestore) {}

  /**
   * Create or replace catalog fields for a city.
   * Document id is always normalizeCitySlug(input.id); duplicates from casing/whitespace collapse.
   */
  async upsertCity(input: CityCatalogWriteInput): Promise<CityCatalogRecord> {
    const id = resolveCanonicalCityId(input.id);
    const displayName = parseDisplayName(input.displayName);
    const countryCode = parseCountryCode(input.countryCode);
    const active = parseActive(input.active);
    const nowIso = new Date().toISOString();
    const ref = this.db.collection(CITIES_COLLECTION).doc(id);
    const existing = await ref.get();
    const createdAt =
      existing.exists && typeof existing.data()?.createdAt === 'string'
        ? (existing.data()!.createdAt as string)
        : nowIso;

    const record: CityCatalogRecord = {
      id,
      displayName,
      countryCode,
      active,
      createdAt,
      updatedAt: nowIso,
    };

    await ref.set({
      id: record.id,
      displayName: record.displayName,
      countryCode: record.countryCode,
      active: record.active,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    });

    return record;
  }

  async getCity(rawId: unknown): Promise<CityCatalogRecord | null> {
    const id = resolveCanonicalCityId(rawId);
    const snap = await this.db.collection(CITIES_COLLECTION).doc(id).get();
    if (!snap.exists) return null;
    return parseStored(snap.data() ?? {}, id);
  }

  async cityExists(rawId: unknown): Promise<boolean> {
    const city = await this.getCity(rawId);
    return city != null;
  }

  /**
   * true only when the document exists and active === true.
   * Missing or inactive → false (does not throw).
   */
  async isCityActive(rawId: unknown): Promise<boolean> {
    const city = await this.getCity(rawId);
    return city != null && city.active === true;
  }
}
