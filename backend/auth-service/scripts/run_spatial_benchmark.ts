/**
 * Spatial-indexing benchmark: bounding-box (current) vs geohash vs H3.
 *
 * LOCAL PROTOTYPE — models Firestore query semantics in-memory:
 *   billed reads = docs returned by the range/IN queries a scheme issues
 *   (index entries scanned inside a range are NOT billed; only matched
 *   documents are). Latency = in-process scan wall time — a RELATIVE proxy
 *   for index-side work, not a production latency prediction.
 *
 * For every scheme × fleet-size × radius × distribution it reports:
 *   - queries issued (RPC fan-out; IN-clauses chunked at 30 like Firestore)
 *   - billed reads (docs in queried ranges/cells)
 *   - candidates (drivers inside the circle after Haversine filter)
 *   - misses vs the bounding-box truth (correctness — must be 0)
 *   - p50 scan latency and estimated $/1M queries at $0.036/100k reads
 *
 * Driver layouts: `uniform` (even spread) and `clustered` (60% in a 3 km
 * core, 40% outer — realistic Lahore-style density, where read
 * amplification actually shows up).
 */
import { performance } from 'node:perf_hooks';
import * as h3 from 'h3-js';
import {
  geohashCovering,
  geohashEncode,
  haversineKm,
} from './spatial/geohash';

const CENTER = { lat: 31.55, lng: 74.35 };
const FLEET_SIZES = [100, 500, 1000, 2000, 5000];
const RADII_KM = [5, 10, 25];
const QUERY_SAMPLES = 40;
const READ_COST_PER_DOC = 0.036 / 100_000;

interface Driver {
  id: string;
  lat: number;
  lng: number;
  gh: Record<number, string>;
  h3c: Record<number, string>;
}

interface SchemeResult {
  queries: number;
  reads: number;
  candidates: number;
  misses: number;
  p50ms: number;
  costPer1MQueries: number;
}

function seededRand(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function makeFleet(n: number, mode: 'uniform' | 'clustered'): Driver[] {
  const rand = seededRand(n * 7 + (mode === 'uniform' ? 1 : 2));
  const drivers: Driver[] = [];
  for (let i = 0; i < n; i += 1) {
    let r: number;
    if (mode === 'clustered' && rand() < 0.6) {
      r = Math.sqrt(rand()) * 0.027; // ~3 km core
    } else {
      r = 0.027 + Math.sqrt(rand()) * 0.11; // ring out to ~15 km
    }
    const a = rand() * Math.PI * 2;
    const lat = CENTER.lat + r * Math.cos(a);
    const lng = CENTER.lng + r * Math.sin(a);
    drivers.push({
      id: `d${i}`,
      lat,
      lng,
      gh: {
        4: geohashEncode(lat, lng, 4),
        5: geohashEncode(lat, lng, 5),
        6: geohashEncode(lat, lng, 6),
      },
      h3c: {
        7: h3.latLngToCell(lat, lng, 7),
        8: h3.latLngToCell(lat, lng, 8),
        9: h3.latLngToCell(lat, lng, 9),
      },
    });
  }
  return drivers;
}

function circlePolygon(lat: number, lng: number, radiusKm: number): number[][] {
  const pts: number[][] = [];
  for (let i = 0; i <= 32; i += 1) {
    const a = (i / 32) * Math.PI * 2;
    pts.push([
      lat + (radiusKm / 110.574) * Math.cos(a),
      lng +
        (radiusKm / (111.32 * Math.cos((lat * Math.PI) / 180))) *
          Math.sin(a),
    ]);
  }
  return pts;
}

function runScheme(
  drivers: Driver[],
  index: Map<string, Driver[]>,
  cells: string[],
  centerLat: number,
  centerLng: number,
  radiusKm: number,
): { reads: number; candidates: number; correct: Set<string>; ms: number } {
  const t0 = performance.now();
  const correct = new Set<string>();
  let reads = 0;
  for (const cell of cells) {
    const bucket = index.get(cell);
    if (!bucket) continue;
    reads += bucket.length;
    for (const d of bucket) {
      if (haversineKm(centerLat, centerLng, d.lat, d.lng) <= radiusKm) {
        correct.add(d.id);
      }
    }
  }
  return {
    reads,
    candidates: correct.size,
    correct,
    ms: performance.now() - t0,
  };
}

function bench(
  fleet: Driver[],
  centerLat: number,
  centerLng: number,
  radiusKm: number,
): Record<string, SchemeResult> {
  const results: Record<string, SchemeResult> = {};
  const truth: Set<string> = new Set();
  for (const d of fleet) {
    if (haversineKm(centerLat, centerLng, d.lat, d.lng) <= radiusKm) {
      truth.add(d.id);
    }
  }
  const push = (name: string, r: ReturnType<typeof runScheme>, queries: number) => {
    const misses = [...truth].filter((id) => !r.correct.has(id)).length;
    const prev = results[name];
    if (!prev) {
      results[name] = {
        queries,
        reads: r.reads,
        candidates: r.candidates,
        misses,
        p50ms: r.ms,
        costPer1MQueries: r.reads * READ_COST_PER_DOC * 1e6,
      };
    } else {
      prev.queries += queries;
      prev.reads += r.reads;
      prev.candidates += r.candidates;
      prev.misses += misses;
      prev.p50ms += r.ms;
      prev.costPer1MQueries += r.reads * READ_COST_PER_DOC * 1e6;
    }
  };

  // 1. bounding box (current N3) — one composite range scan.
  {
    const latD = radiusKm / 110.574;
    // Pole-edge latitude + geodesic bound — mirrors the corrected
    // production box so the benchmark measures the same geometry.
    const edgeLat = Math.min(89.9, Math.abs(centerLat) + latD);
    const cosE = Math.cos((edgeLat * Math.PI) / 180);
    const ratio = Math.sin(radiusKm / 6371) / cosE;
    const lngD =
      ratio >= 1
        ? 180
        : (Math.asin(ratio) * 180) / Math.PI + 1e-4;
    const t0 = performance.now();
    let reads = 0;
    const found = new Set<string>();
    for (const d of fleet) {
      if (
        d.lat >= centerLat - latD &&
        d.lat <= centerLat + latD &&
        d.lng >= centerLng - lngD &&
        d.lng <= centerLng + lngD
      ) {
        reads += 1;
        if (haversineKm(centerLat, centerLng, d.lat, d.lng) <= radiusKm) {
          found.add(d.id);
        }
      }
    }
    push('bbox', {
      reads,
      candidates: found.size,
      correct: found,
      ms: performance.now() - t0,
    }, 1);
  }

  // 2. geohash prefix covering at precision 4/5/6.
  for (const p of [4, 5, 6]) {
    const idx = new Map<string, Driver[]>();
    for (const d of fleet) {
      const c = d.gh[p];
      const arr = idx.get(c) ?? [];
      arr.push(d);
      idx.set(c, arr);
    }
    const cells = geohashCovering(centerLat, centerLng, radiusKm, p);
    push(`geohash-p${p}`, runScheme(fleet, idx, cells, centerLat, centerLng, radiusKm), cells.length);
  }

  // 3. H3 covering at res 7/8/9 — polygonToCells on an inflated circle,
  // then Firestore `IN` chunks of 30 cells per query.
  for (const res of [7, 8, 9]) {
    const idx = new Map<string, Driver[]>();
    for (const d of fleet) {
      const c = d.h3c[res];
      const arr = idx.get(c) ?? [];
      arr.push(d);
      idx.set(c, arr);
    }
    const edgeKm = h3.getHexagonEdgeLengthAvg(res, h3.UNITS.km);
    const inflated = circlePolygon(centerLat, centerLng, radiusKm + edgeKm * 2);
    let cells: string[] = [];
    try {
      cells = h3.polygonToCells(inflated, res);
    } catch {
      cells = [];
    }
    const queries = Math.max(1, Math.ceil(cells.length / 30));
    push(`h3-r${res}`, runScheme(fleet, idx, cells, centerLat, centerLng, radiusKm), queries);
  }

  // Normalize accumulation → averages.
  for (const [k, v] of Object.entries(results)) {
    results[k] = {
      queries: v.queries,
      reads: v.reads,
      candidates: v.candidates,
      misses: v.misses,
      p50ms: v.p50ms,
      costPer1MQueries: v.costPer1MQueries,
    };
  }
  return results;
}

async function main(): Promise<void> {
  const rand = seededRand(42);
  const rows: Array<Record<string, unknown>> = [];
  for (const mode of ['uniform', 'clustered'] as const) {
    for (const n of FLEET_SIZES) {
      const fleet = makeFleet(n, mode);
      for (const radiusKm of RADII_KM) {
        const acc: Record<string, SchemeResult[]> = {};
        for (let s = 0; s < QUERY_SAMPLES; s += 1) {
          const qLat = CENTER.lat + (rand() - 0.5) * 0.12;
          const qLng = CENTER.lng + (rand() - 0.5) * 0.12;
          const r = bench(fleet, qLat, qLng, radiusKm);
          for (const [name, res] of Object.entries(r)) {
            (acc[name] ??= []).push(res);
          }
        }
        for (const [name, samples] of Object.entries(acc)) {
          const reads = samples.map((x) => x.reads).sort((a, b) => a - b);
          const queries = samples.map((x) => x.queries).sort((a, b) => a - b);
          const ms = samples.map((x) => x.p50ms).sort((a, b) => a - b);
          const misses = samples.reduce((s, x) => s + x.misses, 0);
          const mid = Math.floor(samples.length / 2);
          rows.push({
            dist: mode,
            fleet: n,
            radiusKm,
            scheme: name,
            queries: queries[mid],
            reads: reads[mid],
            readsP95: reads[Math.floor(reads.length * 0.95)],
            candidates: samples[mid].candidates,
            misses,
            scanMs: ms[mid].toFixed(2),
            usdPer1MQ: (reads[mid] * READ_COST_PER_DOC * 1e6).toFixed(2),
          });
        }
      }
    }
  }

  console.log('scheme,fleet,dist,radiusKm,queries,reads,readsP95,candidates,misses,scanMs,usdPer1MQ');
  for (const r of rows) {
    console.log(
      `${r.scheme},${r.fleet},${r.dist},${r.radiusKm},${r.queries},${r.reads},${r.readsP95},${r.candidates},${r.misses},${r.scanMs},${r.usdPer1MQ}`,
    );
  }
}

main().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
