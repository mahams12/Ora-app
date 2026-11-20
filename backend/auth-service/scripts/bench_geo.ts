/**
 * Geo index benchmark — simulated Firestore read cost for nearby-driver
 * candidate queries. Compares the CURRENT bounding-box + haversine index
 * against H3 cell covering, geohash cell covering, and a progressive-ring
 * bbox variant, at fleet sizes 10 / 100 / 1,000 / 5,000 online drivers.
 *
 * "reads" = number of driver docs a real Firestore query would fetch
 * (the billing metric). "queries" = round-trips. Latency is in-process
 * simulation — relative comparison only; absolute Firestore latency is
 * measured in the deployed benchmark phase.
 *
 * Run: npx tsx scripts/bench_geo.ts
 */
import { latLngToCell, polygonToCells } from 'h3-js';

type Driver = { id: string; lat: number; lng: number };

const EARTH_KM = 6371;
const CITY_CENTER = { lat: 31.52, lng: 74.35 }; // Lahore
const QUERY_RADII_KM = [10, 25]; // wave-1 and wave-3 radii
const QUERIES_PER_CELL = 30; // Firestore `in` disjunction limit
const N_QUERIES = 200;
const NEAREST_K = 100; // N3_GEO_COUNT — geo result cap
const PROGRESSIVE_RINGS_KM = [2, 5];

function haversineKm(a: Driver, lat: number, lng: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat - a.lat);
  const dLng = toRad(lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.min(1, Math.sqrt(s)));
}

function kmToLatDeg(km: number): number {
  return km / 111.32;
}
function kmToLngDeg(km: number, atLat: number): number {
  const cos = Math.cos((atLat * Math.PI) / 180);
  const ratio = Math.sin(km / EARTH_KM) / cos;
  if (ratio >= 1) return 180;
  return (Math.asin(ratio) * 180) / Math.PI + 1e-4;
}

/** Realistic fleet: 65% clustered in central ~8km, rest spread over ~30km. */
function genFleet(n: number, rand: () => number): Driver[] {
  const drivers: Driver[] = [];
  for (let i = 0; i < n; i++) {
    const clustered = rand() < 0.65;
    const spanKm = clustered ? 8 : 30;
    drivers.push({
      id: `d${i}`,
      lat: CITY_CENTER.lat + (rand() - 0.5) * kmToLatDeg(spanKm) * 2,
      lng: CITY_CENTER.lng + (rand() - 0.5) * kmToLngDeg(spanKm, CITY_CENTER.lat) * 2,
    });
  }
  return drivers;
}

/** Sparse/rural fleet: uniform spread over ~60km (e.g. intercity/fringe). */
function genSparseFleet(n: number, rand: () => number): Driver[] {
  const drivers: Driver[] = [];
  for (let i = 0; i < n; i++) {
    drivers.push({
      id: `d${i}`,
      lat: CITY_CENTER.lat + (rand() - 0.5) * kmToLatDeg(60) * 2,
      lng: CITY_CENTER.lng + (rand() - 0.5) * kmToLngDeg(60, CITY_CENTER.lat) * 2,
    });
  }
  return drivers;
}

let seed = 42;
function rand(): number {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
}

// ---------------- geohash ----------------
const B32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohashEncode(lat: number, lng: number, precision: number): string {
  let latRange: [number, number] = [-90, 90];
  let lngRange: [number, number] = [-180, 180];
  let hash = '';
  let even = true;
  while (hash.length < precision) {
    let bits = 0;
    for (let i = 0; i < 5; i++) {
      bits <<= 1;
      if (even) {
        const mid = (lngRange[0] + lngRange[1]) / 2;
        if (lng >= mid) { bits |= 1; lngRange[0] = mid; } else lngRange[1] = mid;
      } else {
        const mid = (latRange[0] + latRange[1]) / 2;
        if (lat >= mid) { bits |= 1; latRange[0] = mid; } else latRange[1] = mid;
      }
      even = !even;
    }
    hash += B32[bits];
  }
  return hash;
}
function geohashBounds(hash: string): { minLat: number; maxLat: number; minLng: number; maxLng: number } {
  let latRange: [number, number] = [-90, 90];
  let lngRange: [number, number] = [-180, 180];
  let even = true;
  for (const ch of hash) {
    const v = B32.indexOf(ch);
    for (let i = 4; i >= 0; i--) {
      const bit = (v >> i) & 1;
      if (even) {
        const mid = (lngRange[0] + lngRange[1]) / 2;
        if (bit) lngRange[0] = mid; else lngRange[1] = mid;
      } else {
        const mid = (latRange[0] + latRange[1]) / 2;
        if (bit) latRange[0] = mid; else latRange[1] = mid;
      }
      even = !even;
    }
  }
  return { minLat: latRange[0], maxLat: latRange[1], minLng: lngRange[0], maxLng: lngRange[1] };
}
function geohashCover(lat: number, lng: number, radiusKm: number, precision: number): string[] {
  const latD = kmToLatDeg(radiusKm);
  const lngD = kmToLngDeg(radiusKm, Math.min(89.9, Math.abs(lat) + latD));
  const center = geohashEncode(lat, lng, precision);
  const cells = new Set<string>();
  // Frontier: center cell + neighbors until circle covered. Enumerate the
  // bbox at cell granularity and keep intersecting cells.
  const cb = geohashBounds(center);
  const cellLat = cb.maxLat - cb.minLat;
  const cellLng = cb.maxLng - cb.minLng;
  const latSteps = Math.ceil(latD / cellLat) + 1;
  const lngSteps = Math.ceil(lngD / cellLng) + 1;
  const cLat = (cb.minLat + cb.maxLat) / 2;
  const cLng = (cb.minLng + cb.maxLng) / 2;
  for (let i = -latSteps; i <= latSteps; i++) {
    for (let j = -lngSteps; j <= lngSteps; j++) {
      const testLat = cLat + i * cellLat;
      const testLng = cLng + j * cellLng;
      const h = geohashEncode(testLat, testLng, precision);
      const b = geohashBounds(h);
      // cell-circle intersection: closest point of cell to center within radius
      const nearLat = Math.max(b.minLat, Math.min(lat, b.maxLat));
      const nearLng = Math.max(b.minLng, Math.min(lng, b.maxLng));
      if (haversineKm({ id: '', lat: nearLat, lng: nearLng }, lat, lng) <= radiusKm) {
        cells.add(h);
      }
    }
  }
  return [...cells];
}

// ---------------- strategies ----------------
interface StratResult { reads: number; queries: number; hits: string[] }
type Strat = (drivers: Driver[], lat: number, lng: number, rKm: number) => StratResult;

const bbox: Strat = (drivers, lat, lng, rKm) => {
  const latD = kmToLatDeg(rKm);
  const lngD = kmToLngDeg(rKm, Math.min(89.9, Math.abs(lat) + latD));
  const inBox = drivers.filter(
    (d) =>
      Math.abs(d.lat - lat) <= latD && Math.abs(d.lng - lng) <= lngD,
  );
  const hits = inBox
    .filter((d) => haversineKm(d, lat, lng) <= rKm)
    .sort((a, b) => haversineKm(a, lat, lng) - haversineKm(b, lat, lng))
    .slice(0, NEAREST_K)
    .map((d) => d.id);
  return { reads: inBox.length, queries: 1, hits };
};

const bboxProgressive: Strat = (drivers, lat, lng, rKm) => {
  const rings = [...PROGRESSIVE_RINGS_KM.filter((r) => r < rKm), rKm];
  const inCircle: Driver[] = [];
  const seen = new Set<string>();
  let reads = 0;
  let queries = 0;
  for (const ring of rings) {
    const latD = kmToLatDeg(ring);
    const lngD = kmToLngDeg(ring, Math.min(89.9, Math.abs(lat) + latD));
    queries += 1;
    // Real Firestore re-bills inner-region docs on every expansion — count
    // all matched docs per query; dedupe only the result set.
    const boxDocs = drivers.filter(
      (d) => Math.abs(d.lat - lat) <= latD && Math.abs(d.lng - lng) <= lngD,
    );
    reads += boxDocs.length;
    let inRing = 0;
    for (const d of boxDocs) {
      const dist = haversineKm(d, lat, lng);
      if (dist <= rKm && !seen.has(d.id)) {
        seen.add(d.id);
        inCircle.push(d);
      }
      if (dist <= ring) inRing += 1;
    }
    // ≥K candidates with dist ≤ ring: every outside-box doc has dist > ring,
    // so the global nearest-K is fully contained — safe to stop.
    if (inRing >= NEAREST_K) break;
  }
  const hits = inCircle
    .sort((a, b) => haversineKm(a, lat, lng) - haversineKm(b, lat, lng))
    .slice(0, NEAREST_K)
    .map((d) => d.id);
  return { reads, queries, hits };
};

function makeH3(res: number): Strat {
  return (drivers, lat, lng, rKm) => {
    const cellByDriver = new Map<string, string>();
    for (const d of drivers) cellByDriver.set(d.id, latLngToCell(d.lat, d.lng, res));
    // exact circle covering via polygonToCells (GeoJSON order: [lng, lat])
    const verts: [number, number][] = [];
    const latD = kmToLatDeg(rKm);
    const lngD = kmToLngDeg(rKm, Math.min(89.9, Math.abs(lat) + latD));
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * 2 * Math.PI;
      verts.push([lng + lngD * Math.cos(a), lat + latD * Math.sin(a)]);
    }
    const cells = polygonToCells(verts, res, true);
    const cellSet = new Set(cells);
    const queries = Math.ceil(cells.length / QUERIES_PER_CELL) || 1;
    const matched = drivers.filter((d) => cellSet.has(cellByDriver.get(d.id)!));
    const hits = matched
      .filter((d) => haversineKm(d, lat, lng) <= rKm)
      .sort((a, b) => haversineKm(a, lat, lng) - haversineKm(b, lat, lng))
      .slice(0, NEAREST_K)
      .map((d) => d.id);
    return { reads: matched.length, queries, hits };
  };
}

function makeGeohash(precision: number): Strat {
  return (drivers, lat, lng, rKm) => {
    const cellByDriver = new Map<string, string>();
    for (const d of drivers) cellByDriver.set(d.id, geohashEncode(d.lat, d.lng, precision));
    const cells = geohashCover(lat, lng, rKm, precision);
    const cellSet = new Set(cells);
    const queries = Math.ceil(cells.length / QUERIES_PER_CELL) || 1;
    const matched = drivers.filter((d) => cellSet.has(cellByDriver.get(d.id)!));
    const hits = matched
      .filter((d) => haversineKm(d, lat, lng) <= rKm)
      .sort((a, b) => haversineKm(a, lat, lng) - haversineKm(b, lat, lng))
      .slice(0, NEAREST_K)
      .map((d) => d.id);
    return { reads: matched.length, queries, hits };
  };
}

// ---------------- runner ----------------
function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const i = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[i];
}

const FLEET_SIZES = [100, 1000, 5000, 10000];
const STRATS: [string, Strat][] = [
  ['bbox(cur)', bbox],
  ['bbox-rings', bboxProgressive],
  ['h3-res7', makeH3(7)],
  ['h3-res8', makeH3(8)],
  ['geohash-p5', makeGeohash(5)],
  ['geohash-p6', makeGeohash(6)],
];

console.log(
  'Geo index benchmark — reads = billed doc reads; queries = round-trips; ' +
  `${N_QUERIES} random pickups/cell; clustered fleet; NEAREST_K=${NEAREST_K}`,
);

function runScenario(label: string, gen: (n: number, r: () => number) => Driver[]) {
for (const n of FLEET_SIZES) {
  seed = 42;
  const fleet = gen(n, rand);
  for (const rKm of QUERY_RADII_KM) {
    console.log(`\n=== ${label} fleet=${n} radius=${rKm}km ===`);
    // ground truth per query = brute force nearest-K
    const truth: string[][] = [];
    const pickups: [number, number][] = [];
    for (let q = 0; q < N_QUERIES; q++) {
      const pLat = CITY_CENTER.lat + (rand() - 0.5) * kmToLatDeg(12) * 2;
      const pLng = CITY_CENTER.lng + (rand() - 0.5) * kmToLngDeg(12, CITY_CENTER.lat) * 2;
      pickups.push([pLat, pLng]);
      truth.push(
        fleet
          .filter((d) => haversineKm(d, pLat, pLng) <= rKm)
          .sort((a, b) => haversineKm(a, pLat, pLng) - haversineKm(b, pLat, pLng))
          .slice(0, NEAREST_K)
          .map((d) => d.id),
      );
    }
    console.log('strategy      reads/p50   reads/p95   queries   exact%   ms/q');
    for (const [name, strat] of STRATS) {
      const reads: number[] = [];
      const queries: number[] = [];
      const times: number[] = [];
      let exact = 0;
      for (let q = 0; q < N_QUERIES; q++) {
        const [pLat, pLng] = pickups[q];
        const t0 = performance.now();
        const r = strat(fleet, pLat, pLng, rKm);
        times.push(performance.now() - t0);
        reads.push(r.reads);
        queries.push(r.queries);
        if (JSON.stringify(r.hits) === JSON.stringify(truth[q])) exact += 1;
      }
      reads.sort((a, b) => a - b);
      times.sort((a, b) => a - b);
      const meanQ = queries.reduce((a, b) => a + b, 0) / queries.length;
      console.log(
        `${name.padEnd(12)} ${String(percentile(reads, 50)).padStart(9)} ${String(percentile(reads, 95)).padStart(11)} ${meanQ.toFixed(2).padStart(9)} ${((exact / N_QUERIES) * 100).toFixed(1).padStart(7)} ${percentile(times, 50).toFixed(2).padStart(7)}`,
      );
    }
  }
}
}

runScenario('dense-city', genFleet);
runScenario('sparse-area', genSparseFleet);
