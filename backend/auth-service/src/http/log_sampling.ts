/**
 * Deterministic steady-state log sampling for high-frequency paths
 * (location packets, geo projections).
 *
 * Only SUCCESS-path repetitive logs go through this — error, failure,
 * and skip logs must always be emitted and never routed here.
 * Slow-path events (durationMs >= slowMs) always emit regardless of
 * sampling. Sampling is per-operation-key and per-process; it reduces
 * volume, not correctness.
 */

export const STEADY_STATE_LOG_INTERVAL = 10;
export const STEADY_STATE_SLOW_MS = 1_000;

export class LogSampler {
  private readonly counts = new Map<string, number>();

  constructor(private readonly interval = STEADY_STATE_LOG_INTERVAL) {
    if (!Number.isInteger(interval) || interval < 1) {
      throw new Error('LogSampler interval must be a positive integer');
    }
  }

  /** True for the first event per key, then every `interval`-th. */
  shouldLog(key: string): boolean {
    const next = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, next);
    return next === 1 || next % this.interval === 0;
  }
}

/**
 * Steady-state emission rule: emit when sampled OR slow.
 * `shouldLog` is not consulted on the slow path (short-circuit), so
 * slow events neither consume nor shift the sampling sequence.
 */
export function shouldEmitSteadyStateLog(
  sampler: LogSampler,
  key: string,
  durationMs: number,
  slowMs = STEADY_STATE_SLOW_MS,
): boolean {
  return durationMs >= slowMs || sampler.shouldLog(key);
}
