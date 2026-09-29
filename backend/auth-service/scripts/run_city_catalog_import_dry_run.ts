/**
 * Slice 2E dry-run — validates approved catalog; never writes Firestore.
 *
 * Usage:
 *   npm --prefix backend/auth-service run test:city-catalog-import-dry-run
 */
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  buildImportManifest,
  defaultApprovedCatalogPath,
  defaultProvenancePath,
  loadApprovedCatalogFile,
  runCatalogImportDryRun,
  validateApprovedCatalog,
} from '../src/cities/city_catalog_import';

function main(): void {
  const repoRoot = resolve(__dirname, '../../..');
  const catalogPath = defaultApprovedCatalogPath(repoRoot);
  const provenancePath = defaultProvenancePath(repoRoot);
  const report = runCatalogImportDryRun({ catalogPath, provenancePath });

  const file = loadApprovedCatalogFile(catalogPath);
  const provenance = JSON.parse(readFileSync(provenancePath, 'utf8')) as {
    cities?: Array<{ id: string }>;
  };
  const provenanceIds = new Set((provenance.cities ?? []).map((c) => c.id));
  const { records } = validateApprovedCatalog(file, provenanceIds);
  const manifest = buildImportManifest(records);

  const outDir = resolve(
    repoRoot,
    'docs/implementation/n-series/city-dataset/final',
  );
  mkdirSync(outDir, { recursive: true });
  const outPath = resolve(outDir, 'slice2e_import_dry_run_report.json');
  const manifestPath = resolve(outDir, 'slice2e_import_manifest.json');
  writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  writeFileSync(
    manifestPath,
    `${JSON.stringify(
      {
        _meta: {
          slice: '2E',
          FIRESTORE_WRITE_STATUS: report.FIRESTORE_WRITE_STATUS,
          REASON: report.REASON,
          licensing: report.licensingStatus,
          entryCount: manifest.length,
          note: 'Deterministic import plan only — no Firestore writes performed.',
        },
        entries: manifest,
      },
      null,
      2,
    )}\n`,
    'utf8',
  );

  console.log(`FIRESTORE_WRITE_STATUS = ${report.FIRESTORE_WRITE_STATUS}`);
  console.log(`REASON = ${report.REASON}`);
  console.log(`validationOk = ${report.validationOk}`);
  console.log(`catalogCount = ${report.catalogCount}`);
  console.log(`wrote ${outPath}`);
  console.log(`wrote ${manifestPath}`);

  if (report.FIRESTORE_WRITE_STATUS !== 'BLOCKED') {
    console.error('Expected BLOCKED while licensing gate is active');
    process.exit(1);
  }
  if (!report.validationOk) {
    console.error('Validation failed', report.validationErrors.slice(0, 10));
    process.exit(1);
  }
}

main();
