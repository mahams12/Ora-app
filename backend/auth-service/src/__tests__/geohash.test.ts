import { describe, expect, it } from 'vitest';
import {
  choosePrecision,
  coveringCells,
  geohashBounds,
  geohashEncode,
  cellSizeDegrees,
} from '../rtdb/geohash';

const LAHORE = { lat: 31.52, lng: 74.35 };

describe('geohash', () => {
  it('encodes known coordinates to the canonical geohash', () => {
    // Known reference: (57.64911, 10.40744) -> 'u4pruydqqvj' (Wikipedia).
    expect(geohashEncode(57.64911, 10.40744, 11)).toBe('u4pruydqqvj');
    expect(geohashEncode(57.64911, 10.40744, 5)).toBe('u4pru');
  });

  it('encode→bounds round-trips to a cell containing the point', () => {
    for (const p of [4, 5, 8]) {
      const hash = geohashEncode(LAHORE.lat, LAHORE.lng, p);
      expect(hash).toHaveLength(p);
      const b = geohashBounds(hash);
      expect(LAHORE.lat).toBeGreaterThanOrEqual(b.minLat - 1e-9);
      expect(LAHORE.lat).toBeLessThanOrEqual(b.maxLat + 1e-9);
      expect(LAHORE.lng).toBeGreaterThanOrEqual(b.minLng - 1e-9);
      expect(LAHORE.lng).toBeLessThanOrEqual(b.maxLng + 1e-9);
    }
  });

  it('nearby points share a long prefix; distant points do not', () => {
    const a = geohashEncode(LAHORE.lat, LAHORE.lng);
    const b = geohashEncode(LAHORE.lat + 0.001, LAHORE.lng + 0.001);
    const c = geohashEncode(24.86, 67.0); // Karachi
    const shared = (x: string, y: string) => {
      let i = 0;
      while (i < x.length && x[i] === y[i]) i += 1;
      return i;
    };
    expect(shared(a, b)).toBeGreaterThanOrEqual(5);
    expect(shared(a, c)).toBeLessThanOrEqual(3);
  });

  it('cell size decreases with precision', () => {
    const p4 = cellSizeDegrees(4);
    const p5 = cellSizeDegrees(5);
    expect(p5.heightDeg).toBeLessThan(p4.heightDeg);
    expect(p5.widthDeg).toBeLessThan(p4.widthDeg);
  });

  it('coveringCells covers every corner + center of the bbox', () => {
    const box = {
      minLat: LAHORE.lat - 0.1,
      maxLat: LAHORE.lat + 0.1,
      minLng: LAHORE.lng - 0.1,
      maxLng: LAHORE.lng + 0.1,
    };
    const cells = new Set(coveringCells(box, 5));
    const points = [
      [box.minLat, box.minLng],
      [box.minLat, box.maxLng],
      [box.maxLat, box.minLng],
      [box.maxLat, box.maxLng],
      [LAHORE.lat, LAHORE.lng],
      [LAHORE.lat + 0.05, LAHORE.lng],
      [LAHORE.lat, LAHORE.lng - 0.05],
    ];
    for (const [lat, lng] of points) {
      const p = geohashEncode(lat, lng, 5);
      expect(cells.has(p)).toBe(true);
    }
  });

  it('coveringCells includes adjacent cells across a cell boundary', () => {
    // A bbox centered exactly on a cell edge must return both cells.
    const b = geohashBounds(geohashEncode(LAHORE.lat, LAHORE.lng, 5));
    const edgeLat = b.minLat;
    const box = {
      minLat: edgeLat - 0.001,
      maxLat: edgeLat + 0.001,
      minLng: LAHORE.lng - 0.001,
      maxLng: LAHORE.lng + 0.001,
    };
    const cells = coveringCells(box, 5);
    const below = geohashEncode(edgeLat - 0.0005, LAHORE.lng, 5);
    const above = geohashEncode(edgeLat + 0.0005, LAHORE.lng, 5);
    expect(cells).toContain(below);
    expect(cells).toContain(above);
  });

  it('choosePrecision stays under the query cap for dispatch radii', () => {
    for (const radiusKm of [10, 15, 25]) {
      const box = {
        minLat: LAHORE.lat - radiusKm / 111.32,
        maxLat: LAHORE.lat + radiusKm / 111.32,
        minLng: LAHORE.lng - radiusKm / 111.32,
        maxLng: LAHORE.lng + radiusKm / 111.32,
      };
      const p = choosePrecision(box, 32);
      const cells = coveringCells(box, p);
      expect(cells.length).toBeLessThanOrEqual(32);
      expect(cells.length).toBeGreaterThan(0);
    }
  });
});
