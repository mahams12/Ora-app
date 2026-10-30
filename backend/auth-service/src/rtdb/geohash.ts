/**
 * Minimal geohash implementation for the RTDB geo index — encode, cell
 * bounds, and bounding-box cell coverage. No external dependency.
 *
 * Standard geohash: base32 alphabet, longitude/latitude bit interleave.
 * Stored keys are full precision (GEO_KEY_PRECISION); queries cover a
 * bounding box with precision-P cell prefixes via lexicographic ranges.
 */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/** Stored geohash precision (~19m cells — finer than any query precision). */
export const GEO_KEY_PRECISION = 8;

/** Max cell queries issued per georadius (executed in parallel). */
export const GEO_MAX_CELL_QUERIES = 32;

export interface GeoBox {
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
}

/** Number of lat/lng bits at a given geohash precision. */
function bitCounts(precision: number): { latBits: number; lngBits: number } {
  const total = precision * 5;
  const lngBits = Math.ceil(total / 2);
  return { latBits: total - lngBits, lngBits };
}

/** Cell dimensions in degrees at a given precision. */
export function cellSizeDegrees(precision: number): {
  heightDeg: number;
  widthDeg: number;
} {
  const { latBits, lngBits } = bitCounts(precision);
  return {
    heightDeg: 180 / 2 ** latBits,
    widthDeg: 360 / 2 ** lngBits,
  };
}

export function geohashEncode(
  lat: number,
  lng: number,
  precision: number = GEO_KEY_PRECISION,
): string {
  const { latBits, lngBits } = bitCounts(precision);
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let hash = '';
  let latDone = 0;
  let lngDone = 0;

  // Interleave: geohash alternates lng,lat per bit starting with lng.
  while (lngDone < lngBits || latDone < latBits) {
    let value = 0;
    for (let i = 0; i < 5; i += 1) {
      value <<= 1;
      const useLng = (lngDone + latDone) % 2 === 0;
      if (useLng) {
        if (lngDone < lngBits) {
          const mid = (lngMin + lngMax) / 2;
          if (lng >= mid) {
            value |= 1;
            lngMin = mid;
          } else {
            lngMax = mid;
          }
          lngDone += 1;
        }
      } else if (latDone < latBits) {
        const mid = (latMin + latMax) / 2;
        if (lat >= mid) {
          value |= 1;
          latMin = mid;
        } else {
          latMax = mid;
        }
        latDone += 1;
      }
    }
    hash += BASE32[value];
    if (hash.length >= precision) break;
  }
  return hash.slice(0, precision);
}

/** Decode the exact cell bounds for a geohash prefix. */
export function geohashBounds(hash: string): GeoBox {
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let useLng = true;
  for (const ch of hash) {
    const idx = BASE32.indexOf(ch);
    if (idx < 0) throw new Error(`invalid geohash char: ${ch}`);
    for (let bit = 4; bit >= 0; bit -= 1) {
      const isSet = (idx >> bit) & 1;
      if (useLng) {
        const mid = (lngMin + lngMax) / 2;
        if (isSet) lngMin = mid;
        else lngMax = mid;
      } else {
        const mid = (latMin + latMax) / 2;
        if (isSet) latMin = mid;
        else latMax = mid;
      }
      useLng = !useLng;
    }
  }
  return { minLat: latMin, maxLat: latMax, minLng: lngMin, maxLng: lngMax };
}

/**
 * All precision-P cells intersecting a (non-wrapped) lng range.
 * Geohash cells are grid-aligned (boundaries at -90+k*H, -180+j*W), so
 * enumerating the row/column index range covers every touched cell exactly.
 */
function cellsForLngRange(
  minLat: number,
  maxLat: number,
  minLng: number,
  maxLng: number,
  precision: number,
  cells: Set<string>,
): void {
  const { heightDeg, widthDeg } = cellSizeDegrees(precision);
  const rowMin = Math.floor((minLat + 90) / heightDeg);
  const rowMax = Math.floor((maxLat + 90) / heightDeg);
  const colMin = Math.floor((minLng + 180) / widthDeg);
  const colMax = Math.floor((maxLng + 180) / widthDeg);
  for (let r = rowMin; r <= rowMax; r += 1) {
    const lat = -90 + (r + 0.5) * heightDeg;
    for (let c = colMin; c <= colMax; c += 1) {
      cells.add(geohashEncode(lat, -180 + (c + 0.5) * widthDeg, precision));
    }
  }
}

/**
 * Minimal cell set covering the box. Antimeridian wrap is split into the
 * two non-wrapped ranges — correctness preserved, extra cells harmless
 * (post-filtering removes out-of-radius hits anyway).
 */
export function coveringCells(box: GeoBox, precision: number): string[] {
  const cells = new Set<string>();
  if (box.minLng < -180 || box.maxLng > 180) {
    cellsForLngRange(
      box.minLat, box.maxLat,
      Math.max(box.minLng, -180), 180, precision, cells,
    );
    cellsForLngRange(
      box.minLat, box.maxLat,
      -180, Math.min(box.maxLng, 180), precision, cells,
    );
  } else {
    cellsForLngRange(box.minLat, box.maxLat, box.minLng, box.maxLng, precision, cells);
  }
  return [...cells].sort();
}

/** Estimated covering-cell count at precision (no enumeration needed). */
function estimateCellCount(box: GeoBox, precision: number): number {
  const { heightDeg, widthDeg } = cellSizeDegrees(precision);
  const rows = Math.floor((box.maxLat - box.minLat) / heightDeg) + 2;
  const cols = Math.floor((box.maxLng - box.minLng) / widthDeg) + 2;
  return rows * cols;
}

/**
 * Pick the finest precision (within [3, GEO_KEY_PRECISION]) whose covering
 * cell count stays under GEO_MAX_CELL_QUERIES; falls back to the coarsest
 * workable precision for very large boxes. Finer cells = less over-fetch
 * (fewer billed bytes), fewer cells = fewer queries.
 */
export function choosePrecision(
  box: GeoBox,
  maxQueries: number = GEO_MAX_CELL_QUERIES,
): number {
  for (let p = GEO_KEY_PRECISION; p >= 3; p -= 1) {
    if (estimateCellCount(box, p) <= maxQueries) return p;
  }
  return 3;
}
