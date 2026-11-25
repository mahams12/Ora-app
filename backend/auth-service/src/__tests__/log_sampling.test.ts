import { describe, expect, it, vi } from 'vitest';
import {
  LogSampler,
  STEADY_STATE_SLOW_MS,
  shouldEmitSteadyStateLog,
} from '../http/log_sampling';
import { GeoProjectionService } from '../geo/geo_projection';
import { createMemoryGeoStore } from '../geo/memory_geo_store';
import { driverOnlineKey } from '../geo/types';

describe('LogSampler', () => {
  it('emits the first event then every interval-th per key', () => {
    const sampler = new LogSampler(10);
    const emitted: number[] = [];
    for (let i = 1; i <= 25; i++) {
      if (sampler.shouldLog('op')) emitted.push(i);
    }
    expect(emitted).toEqual([1, 10, 20]);
  });

  it('tracks keys independently', () => {
    const sampler = new LogSampler(3);
    // 'a' call sequence → true(#1), false(#2), true(#3), false(#4)
    expect(sampler.shouldLog('a')).toBe(true);
    expect(sampler.shouldLog('b')).toBe(true);
    expect(sampler.shouldLog('a')).toBe(false);
    expect(sampler.shouldLog('a')).toBe(true);
    expect(sampler.shouldLog('a')).toBe(false);
    // 'b' unaffected by 'a' traffic: #2 → false, #3 → true.
    expect(sampler.shouldLog('b')).toBe(false);
    expect(sampler.shouldLog('b')).toBe(true);
  });

  it('rejects invalid intervals', () => {
    expect(() => new LogSampler(0)).toThrow();
    expect(() => new LogSampler(1.5)).toThrow();
  });
});

describe('shouldEmitSteadyStateLog', () => {
  it('emits on sample boundaries; slow paths emit without consuming slots', () => {
    const sampler = new LogSampler(10);
    expect(shouldEmitSteadyStateLog(sampler, 'op', 5)).toBe(true); // #1
    expect(shouldEmitSteadyStateLog(sampler, 'op', 5)).toBe(false); // #2
    for (let i = 0; i < 7; i++) {
      expect(shouldEmitSteadyStateLog(sampler, 'op', 5)).toBe(false); // #3-#9
    }
    // Slow path emits even though the sampler would skip — and does not
    // consume a sampling slot.
    expect(
      shouldEmitSteadyStateLog(sampler, 'op', STEADY_STATE_SLOW_MS),
    ).toBe(true);
    // Sequence unshifted: next sampled event is still #10.
    expect(shouldEmitSteadyStateLog(sampler, 'op', 5)).toBe(true); // #10
    expect(shouldEmitSteadyStateLog(sampler, 'op', 5)).toBe(false); // #11
  });

  it('honors a custom slow threshold', () => {
    const sampler = new LogSampler(10);
    sampler.shouldLog('op'); // consume #1 so next sampled is #10
    expect(shouldEmitSteadyStateLog(sampler, 'op', 500, 250)).toBe(true);
    expect(shouldEmitSteadyStateLog(sampler, 'op', 100, 250)).toBe(false);
  });
});

describe('GEO_STORE_PROJECTED sampling', () => {
  function baseInput(
    seq: number,
    lastLocationTs = Date.now(),
  ): Parameters<GeoProjectionService['projectAcceptedLocation']>[0] {
    return {
      driverId: 'd1',
      lat: 31.52,
      lng: 74.35,
      accuracy: 8,
      locationStreamId: 's1',
      locationSeq: seq,
      lastLocationTs,
      acceptedAt: new Date().toISOString(),
      homeCity: 'lahore',
    };
  }

  function countLogs(
    spy: ReturnType<typeof vi.spyOn>,
    fragment: string,
  ): number {
    return spy.mock.calls.filter(
      (c) => typeof c[0] === 'string' && c[0].includes(fragment),
    ).length;
  }

  it('samples steady-state projections: first + every 10th', async () => {
    const redis = createMemoryGeoStore();
    const geo = new GeoProjectionService(redis);
    const spy = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      for (let i = 1; i <= 25; i++) {
        await geo.projectAcceptedLocation(baseInput(i));
      }
      // Events 1, 10, 20 emit → 3 lines.
      expect(countLogs(spy, 'GEO_STORE_PROJECTED')).toBe(3);
      // Projection behavior unchanged — marker written on every call.
      expect(await redis.get(driverOnlineKey('d1'))).not.toBeNull();
    } finally {
      spy.mockRestore();
    }
  });

  it('SKIP diagnostics are never sampled away', async () => {
    const redis = createMemoryGeoStore();
    const geo = new GeoProjectionService(redis);
    const spy = vi.spyOn(console, 'log').mockImplementation(() => {});
    try {
      const fresh = Date.now();
      await geo.projectAcceptedLocation(baseInput(1, fresh));
      // Strictly older packets → monotonic guard skips every one.
      for (let i = 0; i < 12; i++) {
        await geo.projectAcceptedLocation(
          baseInput(1, fresh - 1_000 - i),
        );
      }
      // All 12 stale packets log GEO_STORE_SKIP — none suppressed.
      expect(countLogs(spy, 'GEO_STORE_SKIP')).toBe(12);
    } finally {
      spy.mockRestore();
    }
  });
});
