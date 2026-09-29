import { describe, expect, it } from 'vitest';
import { resolve } from 'node:path';
import {
  PRODUCTION_IMPORT_STATUS,
  assertImportAllowed,
  importApprovedCatalogToFirestore,
  resolveLicensingGate,
  runCatalogImportDryRun,
  validateApprovedCatalog,
  type ApprovedCatalogFile,
} from '../cities/city_catalog_import';
import { CityCatalogError } from '../cities/types';
import { memoryDb } from './helpers/memory_db';

const repoRoot = resolve(__dirname, '../../../..');
const catalogPath = resolve(
  repoRoot,
  'docs/implementation/n-series/city-dataset/final/approved_city_catalog.json',
);
const provenancePath = resolve(
  repoRoot,
  'docs/implementation/n-series/city-dataset/final/approved_city_provenance.json',
);

describe('Slice 2E city catalog import gate', () => {
  it('hard-codes licensing as blocked', () => {
    expect(PRODUCTION_IMPORT_STATUS).toBe('BLOCKED_PENDING_LICENSING_REVIEW');
  });

  it('dry-run validates 565 cities and blocks Firestore writes', () => {
    const report = runCatalogImportDryRun({
      catalogPath,
      provenancePath,
    });
    expect(report.validationOk).toBe(true);
    expect(report.validationErrors).toEqual([]);
    expect(report.catalogCount).toBe(565);
    expect(report.manifestEntryCount).toBe(565);
    expect(report.FIRESTORE_WRITE_STATUS).toBe('BLOCKED');
    expect(report.REASON).toBe('LICENSING_GATE');
    expect(report.productionImportAllowed).toBe(false);
    expect(report.representativeIdsPresent.lahore).toBe(true);
    expect(report.representativeIdsPresent.sukkur).toBe(true);
    expect(report.duplicateQualifiedSamplesPresent['sahiwal-sargodha']).toBe(
      true,
    );
    expect(report.unresolvedCantonmentStandaloneAbsent).toBe(true);
    expect(report.provenanceLinkageOk).toBe(true);
    expect(report.policy.neverDeleteMissingCities).toBe(true);
    expect(report.policy.collection).toBe('cities');
  });

  it('assertImportAllowed throws IMPORT_BLOCKED under current gate', () => {
    const file = {
      _meta: {
        licensing: 'BLOCKED_PENDING_LICENSING_REVIEW',
        productionImportAllowed: false,
      },
      cities: [],
    } satisfies ApprovedCatalogFile;
    expect(() => assertImportAllowed(file)).toThrow(CityCatalogError);
    try {
      assertImportAllowed(file);
    } catch (err) {
      expect(err).toBeInstanceOf(CityCatalogError);
      expect((err as CityCatalogError).code).toBe('IMPORT_BLOCKED');
    }
  });

  it('importApprovedCatalogToFirestore refuses writes while blocked', async () => {
    const db = memoryDb();
    await expect(
      importApprovedCatalogToFirestore({
        db: db as never,
        catalogPath,
      }),
    ).rejects.toMatchObject({ code: 'IMPORT_BLOCKED' });
    // No cities collection docs written
    expect(db.getDoc('cities', 'lahore')).toBeUndefined();
    expect(db.getDoc('cities', 'karachi')).toBeUndefined();
  });

  it('validateApprovedCatalog rejects bad countryCode', () => {
    const { errors } = validateApprovedCatalog({
      cities: [
        {
          id: 'lahore',
          displayName: 'Lahore',
          countryCode: 'US',
          active: true,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        },
      ],
    });
    expect(errors.some((e) => e.includes('countryCode'))).toBe(true);
  });

  it('resolveLicensingGate cannot be bypassed by flipping meta alone while override blocked', () => {
    const gate = resolveLicensingGate(
      {
        _meta: { productionImportAllowed: true, licensing: 'CLEARED' },
        cities: [],
      },
      'BLOCKED_PENDING_LICENSING_REVIEW',
    );
    expect(gate.allowed).toBe(false);
    expect(gate.reason).toBe('LICENSING_GATE');
  });
});
