import { describe, expect, it } from 'vitest';
import {
  CityCatalogService,
  resolveCanonicalCityId,
} from '../cities/city_catalog_service';
import { CityCatalogError } from '../cities/types';
import { memoryDb } from './helpers/memory_db';

function service() {
  const db = memoryDb();
  return { db, catalog: new CityCatalogService(db as never) };
}

describe('city catalog — resolveCanonicalCityId', () => {
  it('normalizes mixed case / padding via normalizeCitySlug', () => {
    expect(resolveCanonicalCityId('  Test-City ')).toBe('test-city');
  });

  it('rejects missing id', () => {
    expect(() => resolveCanonicalCityId(undefined)).toThrow(CityCatalogError);
    expect(() => resolveCanonicalCityId(null)).toThrow(CityCatalogError);
  });

  it('rejects empty / whitespace id', () => {
    expect(() => resolveCanonicalCityId('')).toThrow(CityCatalogError);
    expect(() => resolveCanonicalCityId('   ')).toThrow(CityCatalogError);
  });

  it('rejects non-slug shape after normalize', () => {
    expect(() => resolveCanonicalCityId('lahore city')).toThrow(CityCatalogError);
    expect(() => resolveCanonicalCityId('Lahore_City')).toThrow(CityCatalogError);
  });
});

describe('city catalog — upsert / read / active', () => {
  it('1. valid city record accepted', async () => {
    const { catalog } = service();
    const record = await catalog.upsertCity({
      id: 'proof-city-alpha',
      displayName: 'Proof City Alpha',
      countryCode: 'PK',
      active: true,
    });
    expect(record).toMatchObject({
      id: 'proof-city-alpha',
      displayName: 'Proof City Alpha',
      countryCode: 'PK',
      active: true,
    });
    expect(record.createdAt).toBeTruthy();
    expect(record.updatedAt).toBeTruthy();
  });

  it('2–3. missing / empty id rejected', async () => {
    const { catalog } = service();
    await expect(
      catalog.upsertCity({
        id: undefined,
        displayName: 'X',
        countryCode: 'PK',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    await expect(
      catalog.upsertCity({
        id: '',
        displayName: 'X',
        countryCode: 'PK',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('4. invalid / non-slug id rejected after normalize', async () => {
    const { catalog } = service();
    await expect(
      catalog.upsertCity({
        id: 'not a slug',
        displayName: 'X',
        countryCode: 'PK',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('5. missing displayName rejected', async () => {
    const { catalog } = service();
    await expect(
      catalog.upsertCity({
        id: 'proof-city',
        displayName: undefined,
        countryCode: 'PK',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
    await expect(
      catalog.upsertCity({
        id: 'proof-city',
        displayName: '  ',
        countryCode: 'PK',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('6. missing countryCode rejected', async () => {
    const { catalog } = service();
    await expect(
      catalog.upsertCity({
        id: 'proof-city',
        displayName: 'Proof',
        countryCode: undefined,
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('7. countryCode PK accepted; non-PK rejected', async () => {
    const { catalog } = service();
    const ok = await catalog.upsertCity({
      id: 'proof-pk',
      displayName: 'Proof PK',
      countryCode: 'PK',
      active: true,
    });
    expect(ok.countryCode).toBe('PK');
    await expect(
      catalog.upsertCity({
        id: 'proof-us',
        displayName: 'Proof US',
        countryCode: 'US',
        active: true,
      }),
    ).rejects.toMatchObject({ code: 'VALIDATION_ERROR' });
  });

  it('8–9. active true and false work', async () => {
    const { catalog } = service();
    const on = await catalog.upsertCity({
      id: 'proof-active',
      displayName: 'On',
      countryCode: 'PK',
      active: true,
    });
    expect(on.active).toBe(true);
    const off = await catalog.upsertCity({
      id: 'proof-inactive',
      displayName: 'Off',
      countryCode: 'PK',
      active: false,
    });
    expect(off.active).toBe(false);
  });

  it('10. read existing city', async () => {
    const { catalog, db } = service();
    await catalog.upsertCity({
      id: 'Proof-Read',
      displayName: 'Proof Read',
      countryCode: 'PK',
      active: true,
    });
    // Casing collapses to one doc id
    expect(db.getDoc('cities', 'proof-read')).toBeDefined();
    const read = await catalog.getCity('PROOF-READ');
    expect(read).toMatchObject({
      id: 'proof-read',
      displayName: 'Proof Read',
      countryCode: 'PK',
      active: true,
    });
  });

  it('11. missing city returns null / not found', async () => {
    const { catalog } = service();
    expect(await catalog.getCity('does-not-exist')).toBeNull();
    expect(await catalog.cityExists('does-not-exist')).toBe(false);
  });

  it('12. active status can be distinguished', async () => {
    const { catalog } = service();
    await catalog.upsertCity({
      id: 'proof-dist-on',
      displayName: 'On',
      countryCode: 'PK',
      active: true,
    });
    await catalog.upsertCity({
      id: 'proof-dist-off',
      displayName: 'Off',
      countryCode: 'PK',
      active: false,
    });
    expect(await catalog.isCityActive('proof-dist-on')).toBe(true);
    expect(await catalog.isCityActive('proof-dist-off')).toBe(false);
    expect(await catalog.isCityActive('missing-city')).toBe(false);

    await catalog.upsertCity({
      id: 'proof-dist-on',
      displayName: 'On',
      countryCode: 'PK',
      active: false,
    });
    expect(await catalog.isCityActive('proof-dist-on')).toBe(false);
  });
});
