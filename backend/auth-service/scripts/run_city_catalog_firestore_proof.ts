/**
 * LIVE Firestore emulator proof for Slice 1 city catalog data model.
 *
 * Requires FIRESTORE_EMULATOR_HOST.
 *
 * Usage:
 *   npm run test:city-catalog-firestore   (from repo root via emulators:exec)
 *   or: npm --prefix backend/auth-service run test:city-catalog-firestore
 */
import { initializeApp, getApps, deleteApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { CityCatalogService } from '../src/cities/city_catalog_service';

let passed = 0;
let failed = 0;

async function test(name: string, fn: () => Promise<void>): Promise<void> {
  try {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
  } catch (err) {
    failed += 1;
    console.error(`FAIL ${name}`);
    console.error(err);
  }
}

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

function requireEmulator(): void {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      'FIRESTORE_EMULATOR_HOST is not set. Run via firebase emulators:exec.',
    );
  }
}

async function main(): Promise<void> {
  requireEmulator();

  const appName = `city-catalog-${Date.now()}`;
  const fbApp = initializeApp({ projectId: 'ora-city-catalog' }, appName);
  const db: Firestore = getFirestore(fbApp);
  db.settings({ ignoreUndefinedProperties: true });

  const catalog = new CityCatalogService(db);
  const cityId = `slice1-proof-${Date.now()}`;

  await test('1. create/write temporary city', async () => {
    const record = await catalog.upsertCity({
      id: cityId,
      displayName: 'Slice1 Proof City',
      countryCode: 'PK',
      active: true,
    });
    assert(record.id === cityId, 'id mismatch');
    assert(record.displayName === 'Slice1 Proof City', 'displayName');
    assert(record.countryCode === 'PK', 'countryCode');
    assert(record.active === true, 'active');
  });

  await test('2–4. read back exact fields + active=true', async () => {
    const read = await catalog.getCity(cityId);
    assert(read != null, 'expected city');
    assert(read!.id === cityId, 'id');
    assert(read!.displayName === 'Slice1 Proof City', 'displayName');
    assert(read!.countryCode === 'PK', 'countryCode');
    assert(read!.active === true, 'active');
    assert(typeof read!.createdAt === 'string' && read!.createdAt.length > 0, 'createdAt');
    assert(typeof read!.updatedAt === 'string' && read!.updatedAt.length > 0, 'updatedAt');
    assert(await catalog.cityExists(cityId), 'exists');
    assert(await catalog.isCityActive(cityId), 'isActive');
  });

  await test('5–7. set active=false and verify inactive', async () => {
    const updated = await catalog.upsertCity({
      id: cityId,
      displayName: 'Slice1 Proof City',
      countryCode: 'PK',
      active: false,
    });
    assert(updated.active === false, 'write active=false');
    const read = await catalog.getCity(cityId);
    assert(read != null && read.active === false, 'read inactive');
    assert((await catalog.isCityActive(cityId)) === false, 'isActive false');
    assert(await catalog.cityExists(cityId), 'still exists');
  });

  await test('8–9. clean up temporary city and verify', async () => {
    await db.collection('cities').doc(cityId).delete();
    const after = await catalog.getCity(cityId);
    assert(after === null, 'expected deleted');
    assert((await catalog.cityExists(cityId)) === false, 'exists false after delete');
    assert((await catalog.isCityActive(cityId)) === false, 'isActive false after delete');
  });

  await deleteApp(fbApp);
  // Avoid dangling apps if re-run in same process
  void getApps;

  console.log(`\nCity catalog Firestore proof: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
