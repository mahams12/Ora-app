/**
 * Minimal geohash implementation for the spatial benchmark — encode, cell
 * bounds, and circle covering. No external dependency; standard base32
 * geohash as used by geofire-common.
 */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export function geohashEncode(
  lat: number,
  lng: number,
  precision: number,
): string {
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let hash = '';
  let even = true;
  while (hash.length < precision) {
    let idx = 0;
    for (let bit = 4; bit >= 0; bit -= 1) {
      idx <<= 1;
      if (even) {
        const mid = (lngMin + lngMax) / 2;
        if (lng >= mid) {
          idx |= 1;
          lngMin = mid;
        } else {
          lngMax = mid;
        }
      } else {
        const mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          idx |= 1;
          latMin = mid;
        } else {
          latMax = mid;
        }
      }
      even = !even;
    }
    hash += BASE32[idx];
  }
  return hash;
}

export interface CellBounds {
  latMin: number;
  latMax: number;
  lngMin: number;
  lngMax: number;
}

export function geohashBounds(hash: string): CellBounds {
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let even = true;
  for (const ch of hash) {
    const idx = BASE32.indexOf(ch);
    for (let bit = 4; bit >= 0; bit -= 1) {
      const set = ((idx >> bit) & 1) === 1;
      if (even) {
        const mid = (lngMin + lngMax) / 2;
        if (set) lngMin = mid;
        else lngMax = mid;
      } else {
        const mid = (latMin + latMax) / 2;
        if (set) latMin = mid;
        else latMax = mid;
      }
      even = !even;
    }
  }
  return { latMin, latMax, lngMin, lngMax };
}

export function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const r = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(a));
}

/** Min distance from a point to a lat/lng rectangle (0 if inside). */
function pointRectKm(
  lat: number,
  lng: number,
  b: CellBounds,
): number {
  const latClamped = Math.min(Math.max(lat, b.latMin), b.latMax);
  const lngClamped = Math.min(Math.max(lng, b.lngMin), b.lngMax);
  return haversineKm(lat, lng, latClamped, lngClamped);
}

/**
 * Every precision-p cell intersecting the circle (center lat/lng, radiusKm).
 * Scan order is lexicographic — matches the Firestore prefix-range scan
 * `geohash >= cell AND geohash < cell + '~'` per covering cell.
 */
export function geohashCovering(
  lat: number,
  lng: number,
  radiusKm: number,
  precision: number,
): string[] {
  // Bounding box of the circle in degrees.
  const latDelta = radiusKm / 110.574;
  const lngDelta = radiusKm / (111.32 * Math.cos((lat * Math.PI) / 180));
  const box: CellBounds = {
    latMin: lat - latDelta,
    latMax: lat + latDelta,
    lngMin: lng - lngDelta,
    lngMax: lng + lngDelta,
  };
  // Grid step for one cell at this precision.
  const probe = geohashBounds(geohashEncode(lat, lng, precision));
  const latStep = probe.latMax - probe.latMin;
  const lngStep = probe.lngMax - probe.lngMin;
  const cells = new Set<string>();
  // Iterate the cell lattice anchored to -90/-180; enumerate every cell
  // whose bounds intersect the circle's bounding box, then keep those
  // within radius of the center (cell-circle overlap).
  const latCells =
    Math.ceil((box.latMax - box.latMin) / latStep) + 2;
  const lngCells =
    Math.ceil((box.lngMax - box.lngMin) / lngStep) + 2;
  const lat0 = Math.floor(box.latMin / latStep) * latStep;
  const lng0 = Math.floor(box.lngMin / lngStep) * lngStep;
  for (let i = -1; i <= latCells; i += 1) {
    for (let j = -1; j <= lngCells; j += 1) {
      const cLat = lat0 + (i + 0.5) * latStep;
      const cLng = lng0 + (j + 0.5) * lngStep;
      if (cLat < -90 || cLat > 90 || cLng < -180 || cLng > 180) continue;
      const hash = geohashEncode(cLat, cLng, precision);
      if (cells.has(hash)) continue;
      const bounds = geohashBounds(hash);
      if (pointRectKm(lat, lng, bounds) <= radiusKm) {
        cells.add(hash);
      }
    }
  }
  return [...cells].sort();
}
