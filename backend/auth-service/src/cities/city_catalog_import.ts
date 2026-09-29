/**
 * Slice 2E — City catalog Firestore import gate.
 *
 * Admin-SDK-oriented import preparation. Refuses Firestore writes while
 * PRODUCTION_IMPORT_STATUS = BLOCKED_PENDING_LICENSING_REVIEW.
 *
 * Does not expose HTTP. Does not modify ride/N3/N4/Flutter behavior.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { Firestore } from 'firebase-admin/firestore';
import {
  CityCatalogService,
  CITIES_COLLECTION,
  resolveCanonicalCityId,
} from './city_catalog_service';
import {
  CITY_COUNTRY_CODE_PK,
  CityCatalogError,
  type CityCatalogRecord,
} from './types';

/** Authoritative gate status until counsel clears PBS derived-catalog use. */
export const PRODUCTION_IMPORT_STATUS = 'BLOCKED_PENDING_LICENSING_REVIEW' as const;

export type ProductionImportStatus =
  | typeof PRODUCTION_IMPORT_STATUS
  | 'CLEARED_FOR_IMPORT';

export interface ApprovedCatalogFile {
  _meta?: {
    licensing?: string;
    productionImportAllowed?: boolean;
    finalCatalogCount?: number;
    [key: string]: unknown;
  };
  cities: Array<Record<string, unknown>>;
}

export interface ImportManifestEntry {
  collection: typeof CITIES_COLLECTION;
  docId: string;
  fields: {
    id: string;
    displayName: string;
    countryCode: typeof CITY_COUNTRY_CODE_PK;
    active: boolean;
    createdAt: string;
    updatedAt: string;
  };
}

export interface CatalogImportDryRunReport {
  slice: '2E';
  generatedAtUtc: string;
  FIRESTORE_WRITE_STATUS: 'BLOCKED' | 'WOULD_WRITE';
  REASON: string;
  licensingStatus: ProductionImportStatus;
  productionImportAllowed: boolean;
  sourcePath: string;
  catalogCount: number;
  expectedCount: number;
  validationErrors: string[];
  validationOk: boolean;
  representativeIdsPresent: Record<string, boolean>;
  duplicateQualifiedSamplesPresent: Record<string, boolean>;
  unresolvedCantonmentStandaloneAbsent: boolean;
  provenanceLinkageOk: boolean;
  manifestSample: ImportManifestEntry[];
  manifestEntryCount: number;
  policy: {
    idempotentUpsert: true;
    neverDeleteMissingCities: true;
    adminSdkOnly: true;
    noHttpSurface: true;
    collection: typeof CITIES_COLLECTION;
  };
}

const EXPECTED_COUNT = 565;

const REPRESENTATIVE_IDS = [
  'lahore',
  'karachi',
  'hyderabad',
  'quetta',
  'sukkur',
  'peshawar',
] as const;

const DUPLICATE_SAMPLES = [
  'sahiwal',
  'sahiwal-sargodha',
  'khanpur',
  'khanpur-shikarpur',
  'hyderabad-bhakkar',
] as const;

/** Standalone ids that must NOT appear (ambiguous cantonments are unresolved, not cities). */
const FORBIDDEN_STANDALONE_IDS = [
  'cherat',
  'wah-cantonment',
  'malir-cantonment',
  'murree-gallies',
  'murree-gallies-cantonment',
  'korangi-creek',
  'korangi-creek-cantonment',
  'ormara-cantonment',
] as const;

function isIsoTimestamp(raw: unknown): raw is string {
  if (typeof raw !== 'string' || raw.trim().length === 0) return false;
  const t = Date.parse(raw);
  return Number.isFinite(t);
}

/**
 * Resolve import authorization from file meta + hard-coded gate.
 * File cannot override a hard block without an explicit CLEARED status in code/config.
 */
export function resolveLicensingGate(
  file: ApprovedCatalogFile,
  overrideStatus: ProductionImportStatus = PRODUCTION_IMPORT_STATUS,
): {
  status: ProductionImportStatus;
  allowed: boolean;
  reason: string;
} {
  const metaBlocked =
    file._meta?.licensing === 'BLOCKED_PENDING_LICENSING_REVIEW' ||
    file._meta?.productionImportAllowed === false;

  if (overrideStatus === 'BLOCKED_PENDING_LICENSING_REVIEW' || metaBlocked) {
    return {
      status: 'BLOCKED_PENDING_LICENSING_REVIEW',
      allowed: false,
      reason: 'LICENSING_GATE',
    };
  }

  if (overrideStatus === 'CLEARED_FOR_IMPORT' && file._meta?.productionImportAllowed === true) {
    return {
      status: 'CLEARED_FOR_IMPORT',
      allowed: true,
      reason: 'LICENSING_CLEARED_AND_AUTHORIZED',
    };
  }

  return {
    status: 'BLOCKED_PENDING_LICENSING_REVIEW',
    allowed: false,
    reason: 'LICENSING_GATE',
  };
}

export function assertImportAllowed(
  file: ApprovedCatalogFile,
  overrideStatus: ProductionImportStatus = PRODUCTION_IMPORT_STATUS,
): void {
  const gate = resolveLicensingGate(file, overrideStatus);
  if (!gate.allowed) {
    throw new CityCatalogError(
      'IMPORT_BLOCKED',
      403,
      `Firestore city catalog import blocked: ${gate.reason} (${gate.status}).`,
    );
  }
}

/**
 * Validate approved catalog records against CityCatalogRecord write contract.
 */
export function validateApprovedCatalog(
  file: ApprovedCatalogFile,
  provenanceIds?: Set<string>,
): { errors: string[]; records: CityCatalogRecord[] } {
  const errors: string[] = [];
  const records: CityCatalogRecord[] = [];
  const seen = new Set<string>();

  if (!Array.isArray(file.cities)) {
    return { errors: ['cities array missing'], records: [] };
  }

  if (file.cities.length !== EXPECTED_COUNT) {
    errors.push(
      `expected ${EXPECTED_COUNT} cities, found ${file.cities.length}`,
    );
  }

  for (const [idx, raw] of file.cities.entries()) {
    try {
      const id = resolveCanonicalCityId(raw.id);
      if (seen.has(id)) {
        errors.push(`duplicate id at index ${idx}: ${id}`);
        continue;
      }
      seen.add(id);

      if (raw.id !== id) {
        errors.push(`id not normalize-stable at ${idx}: ${String(raw.id)} → ${id}`);
      }

      if (typeof raw.displayName !== 'string' || raw.displayName.trim().length === 0) {
        errors.push(`missing displayName at ${idx} (${id})`);
        continue;
      }
      if (raw.countryCode !== CITY_COUNTRY_CODE_PK) {
        errors.push(`countryCode must be PK at ${idx} (${id})`);
        continue;
      }
      if (typeof raw.active !== 'boolean') {
        errors.push(`active must be boolean at ${idx} (${id})`);
        continue;
      }
      if (!isIsoTimestamp(raw.createdAt)) {
        errors.push(`createdAt must be ISO string at ${idx} (${id})`);
        continue;
      }
      if (!isIsoTimestamp(raw.updatedAt)) {
        errors.push(`updatedAt must be ISO string at ${idx} (${id})`);
        continue;
      }

      records.push({
        id,
        displayName: raw.displayName.trim(),
        countryCode: CITY_COUNTRY_CODE_PK,
        active: raw.active,
        createdAt: raw.createdAt,
        updatedAt: raw.updatedAt,
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      errors.push(`index ${idx}: ${msg}`);
    }
  }

  for (const id of REPRESENTATIVE_IDS) {
    if (!seen.has(id)) errors.push(`missing representative id: ${id}`);
  }
  for (const id of DUPLICATE_SAMPLES) {
    if (!seen.has(id)) errors.push(`missing duplicate-sample id: ${id}`);
  }
  for (const id of FORBIDDEN_STANDALONE_IDS) {
    if (seen.has(id)) {
      errors.push(`forbidden unresolved-cantonment standalone id present: ${id}`);
    }
  }

  if (provenanceIds) {
    for (const id of seen) {
      if (!provenanceIds.has(id)) {
        errors.push(`catalog id missing provenance linkage: ${id}`);
      }
    }
    for (const id of provenanceIds) {
      if (!seen.has(id)) {
        errors.push(`provenance id missing from catalog: ${id}`);
      }
    }
  }

  return { errors, records };
}

export function buildImportManifest(
  records: CityCatalogRecord[],
): ImportManifestEntry[] {
  return records.map((r) => ({
    collection: CITIES_COLLECTION,
    docId: r.id,
    fields: {
      id: r.id,
      displayName: r.displayName,
      countryCode: r.countryCode,
      active: r.active,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    },
  }));
}

export function loadApprovedCatalogFile(absolutePath: string): ApprovedCatalogFile {
  const raw = JSON.parse(readFileSync(absolutePath, 'utf8')) as ApprovedCatalogFile;
  return raw;
}

export function defaultApprovedCatalogPath(repoRoot: string): string {
  return resolve(
    repoRoot,
    'docs/implementation/n-series/city-dataset/final/approved_city_catalog.json',
  );
}

export function defaultProvenancePath(repoRoot: string): string {
  return resolve(
    repoRoot,
    'docs/implementation/n-series/city-dataset/final/approved_city_provenance.json',
  );
}

export function runCatalogImportDryRun(input: {
  catalogPath: string;
  provenancePath?: string;
  licensingOverride?: ProductionImportStatus;
}): CatalogImportDryRunReport {
  const file = loadApprovedCatalogFile(input.catalogPath);
  let provenanceIds: Set<string> | undefined;
  if (input.provenancePath) {
    const prov = JSON.parse(readFileSync(input.provenancePath, 'utf8')) as {
      cities?: Array<{ id: string }>;
    };
    provenanceIds = new Set((prov.cities ?? []).map((c) => c.id));
  }

  const { errors, records } = validateApprovedCatalog(file, provenanceIds);
  const gate = resolveLicensingGate(
    file,
    input.licensingOverride ?? PRODUCTION_IMPORT_STATUS,
  );
  const manifest = buildImportManifest(records);
  const idSet = new Set(records.map((r) => r.id));

  const writeBlocked = !gate.allowed || errors.length > 0;

  return {
    slice: '2E',
    generatedAtUtc: new Date().toISOString(),
    FIRESTORE_WRITE_STATUS: writeBlocked ? 'BLOCKED' : 'WOULD_WRITE',
    REASON: !gate.allowed
      ? 'LICENSING_GATE'
      : errors.length > 0
        ? 'VALIDATION_FAILED'
        : 'READY',
    licensingStatus: gate.status,
    productionImportAllowed: gate.allowed,
    sourcePath: input.catalogPath,
    catalogCount: file.cities?.length ?? 0,
    expectedCount: EXPECTED_COUNT,
    validationErrors: errors,
    validationOk: errors.length === 0,
    representativeIdsPresent: Object.fromEntries(
      REPRESENTATIVE_IDS.map((id) => [id, idSet.has(id)]),
    ),
    duplicateQualifiedSamplesPresent: Object.fromEntries(
      DUPLICATE_SAMPLES.map((id) => [id, idSet.has(id)]),
    ),
    unresolvedCantonmentStandaloneAbsent: FORBIDDEN_STANDALONE_IDS.every(
      (id) => !idSet.has(id),
    ),
    provenanceLinkageOk: provenanceIds
      ? errors.every((e) => !e.includes('provenance'))
      : true,
    manifestSample: manifest.slice(0, 5),
    manifestEntryCount: manifest.length,
    policy: {
      idempotentUpsert: true,
      neverDeleteMissingCities: true,
      adminSdkOnly: true,
      noHttpSurface: true,
      collection: CITIES_COLLECTION,
    },
  };
}

/**
 * Live Firestore import — HARD-GATED.
 * Throws IMPORT_BLOCKED while licensing remains blocked.
 * Never deletes documents. Upserts only via CityCatalogService.
 */
export async function importApprovedCatalogToFirestore(input: {
  db: Firestore;
  catalogPath: string;
  licensingOverride?: ProductionImportStatus;
}): Promise<{ written: number }> {
  const file = loadApprovedCatalogFile(input.catalogPath);
  assertImportAllowed(file, input.licensingOverride ?? PRODUCTION_IMPORT_STATUS);

  const { errors, records } = validateApprovedCatalog(file);
  if (errors.length > 0) {
    throw new CityCatalogError(
      'VALIDATION_ERROR',
      400,
      `Catalog validation failed (${errors.length} errors). First: ${errors[0]}`,
    );
  }

  const service = new CityCatalogService(input.db);
  // Bounded sequential upserts — no deletes, no batch delete of missing cities.
  let written = 0;
  for (const record of records) {
    await service.upsertCity({
      id: record.id,
      displayName: record.displayName,
      countryCode: record.countryCode,
      active: record.active,
    });
    written += 1;
  }
  return { written };
}
