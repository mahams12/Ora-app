import { describe, expect, it, beforeEach } from 'vitest';
import { memoryRtdb } from './helpers/memory_rtdb';
import { createRtdbLocationStreamStore } from '../rtdb/rtdb_stream_store';
import { LocationDomainError } from '../location/types';
import type { ParsedLocationUpdate } from '../location/types';

function parsed(overrides: Partial<ParsedLocationUpdate> = {}): ParsedLocationUpdate {
  return {
    locationSeq: 1,
    locationStreamId: 'stream-a',
    lat: 31.5,
    lng: 74.3,
    accuracy: 8,
    heading: 0,
    speed: 0,
    timestampMs: Date.now(),
    provider: 'gps',
    rideId: null,
    ...overrides,
  } as ParsedLocationUpdate;
}

const ACCEPTED_AT = '2026-10-24T12:00:00.000Z';
const ACCEPTED_MS = Date.parse(ACCEPTED_AT);

describe('RtdbLocationStreamStore', () => {
  let root: Record<string, unknown>;
  let store: ReturnType<typeof createRtdbLocationStreamStore>;

  beforeEach(() => {
    const rtdb = memoryRtdb();
    root = rtdb._root;
    store = createRtdbLocationStreamStore(rtdb.ref('/'));
  });

  function accept(
    docId: string,
    p: ParsedLocationUpdate,
    mode: 'idle' | 'trip' = 'idle',
  ) {
    return store.accept({
      docId,
      driverId: 'd1',
      mode,
      parsed: p,
      acceptedAt: ACCEPTED_AT,
    });
  }

  it('creates a cursor on first packet and returns the snapshot', async () => {
    const snap = await accept('d1', parsed());
    expect(snap.locationSeq).toBe(1);
    const node = (root.locationStreams as Record<string, unknown>).d1 as Record<
      string,
      unknown
    >;
    expect(node.activeStreamId).toBe('stream-a');
    expect(node.lastAcceptedSeq).toBe(1);
    expect(node.streamState).toBe('ACTIVE');
    expect(node.expiresAtMs).toBe(ACCEPTED_MS + 24 * 60 * 60 * 1000);
  });

  it('accepts strictly increasing same-stream sequences', async () => {
    await accept('d1', parsed({ locationSeq: 1 }));
    await accept('d1', parsed({ locationSeq: 2 }));
    await accept('d1', parsed({ locationSeq: 10 }));
    const node = (root.locationStreams as Record<string, unknown>).d1 as Record<
      string,
      unknown
    >;
    expect(node.lastAcceptedSeq).toBe(10);
  });

  it('rejects duplicate and out-of-order same-stream sequences', async () => {
    await accept('d1', parsed({ locationSeq: 5 }));
    await expect(accept('d1', parsed({ locationSeq: 5 }))).rejects.toMatchObject({
      code: 'SEQUENCE_VIOLATION',
      httpStatus: 422,
    });
    await expect(accept('d1', parsed({ locationSeq: 2 }))).rejects.toMatchObject(
      { code: 'SEQUENCE_VIOLATION' },
    );
    // Cursor must not regress after rejected packets.
    const node = (root.locationStreams as Record<string, unknown>).d1 as Record<
      string,
      unknown
    >;
    expect(node.lastAcceptedSeq).toBe(5);
  });

  it('new streamId replaces the active stream and resets seq', async () => {
    await accept('d1', parsed({ locationSeq: 9, locationStreamId: 'old' }));
    const snap = await accept(
      'd1',
      parsed({ locationSeq: 1, locationStreamId: 'new' }),
    );
    expect(snap.locationSeq).toBe(1);
    const node = (root.locationStreams as Record<string, unknown>).d1 as Record<
      string,
      unknown
    >;
    expect(node.activeStreamId).toBe('new');
    expect(node.lastAcceptedSeq).toBe(1);
    expect(node.previousStreamIds).toEqual(['old']);
  });

  it('rejects packets from a replaced (previous) stream', async () => {
    await accept('d1', parsed({ locationSeq: 9, locationStreamId: 'old' }));
    await accept('d1', parsed({ locationSeq: 1, locationStreamId: 'new' }));
    // 'old' is now in previousStreamIds — late packet must reject even with
    // a higher seq than the active stream's last.
    await expect(
      accept('d1', parsed({ locationSeq: 100, locationStreamId: 'old' })),
    ).rejects.toMatchObject({
      code: 'SEQUENCE_VIOLATION',
      message: 'Location stream is no longer active.',
    });
  });

  it('rejects packets on a CLOSED stream', async () => {
    await accept('ride-1_d1', parsed({ rideId: 'ride-1' }), 'trip');
    const closed = await store.close({
      docId: 'ride-1_d1',
      updatedAtIso: ACCEPTED_AT,
      expiresAtIso: ACCEPTED_AT,
    });
    expect(closed).toBe(true);
    await expect(
      accept('ride-1_d1', parsed({ locationSeq: 2, rideId: 'ride-1' }), 'trip'),
    ).rejects.toMatchObject({
      code: 'SEQUENCE_VIOLATION',
      message: 'Location stream is closed.',
    });
    // Same-stream violation is checked after CLOSED — closed wins.
  });

  it('close is idempotent and missing docs are a no-op', async () => {
    await expect(
      store.close({
        docId: 'missing',
        updatedAtIso: ACCEPTED_AT,
        expiresAtIso: ACCEPTED_AT,
      }),
    ).resolves.toBe(false);
    await accept('d1', parsed());
    await store.close({
      docId: 'd1',
      updatedAtIso: ACCEPTED_AT,
      expiresAtIso: ACCEPTED_AT,
    });
    await expect(
      store.close({
        docId: 'd1',
        updatedAtIso: ACCEPTED_AT,
        expiresAtIso: ACCEPTED_AT,
      }),
    ).resolves.toBe(false);
  });

  it('keeps idle and trip cursors independent per docId', async () => {
    await accept('d1', parsed({ locationSeq: 7 }), 'idle');
    await accept('ride-1_d1', parsed({ locationSeq: 1, rideId: 'ride-1' }), 'trip');
    const nodes = root.locationStreams as Record<string, Record<string, unknown>>;
    expect(nodes['d1'].lastAcceptedSeq).toBe(7);
    expect(nodes['ride-1_d1'].lastAcceptedSeq).toBe(1);
    expect(nodes['ride-1_d1'].rideId).toBe('ride-1');
  });

  it('trip cursors expire in 7 days, idle in 24h', async () => {
    await accept('d1', parsed(), 'idle');
    await accept('ride-1_d1', parsed({ rideId: 'ride-1' }), 'trip');
    const nodes = root.locationStreams as Record<string, Record<string, unknown>>;
    expect(nodes['d1'].expiresAtMs).toBe(ACCEPTED_MS + 24 * 3600 * 1000);
    expect(nodes['ride-1_d1'].expiresAtMs).toBe(ACCEPTED_MS + 7 * 24 * 3600 * 1000);
  });

  it('sweepExpired removes only expired cursors', async () => {
    await accept('expired', parsed());
    await accept('fresh', parsed());
    // Age 'expired' past 24h manually.
    const nodes = root.locationStreams as Record<string, Record<string, unknown>>;
    nodes.expired.expiresAtMs = ACCEPTED_MS - 1;
    const res = await store.sweepExpired({
      limit: 100,
      nowMs: ACCEPTED_MS + 1000,
    });
    expect(res.deleted).toBe(1);
    expect(res.scanned).toBe(1);
    expect((root.locationStreams as Record<string, unknown>).expired).toBeUndefined();
    expect((root.locationStreams as Record<string, unknown>).fresh).toBeDefined();
  });

  it('sweepExpired honors the limit', async () => {
    for (let i = 0; i < 5; i += 1) {
      await accept(`d${i}`, parsed());
      const nodes = root.locationStreams as Record<
        string,
        Record<string, unknown>
      >;
      nodes[`d${i}`].expiresAtMs = 1;
    }
    const res = await store.sweepExpired({ limit: 2, nowMs: ACCEPTED_MS });
    expect(res.deleted).toBe(2);
    expect(Object.keys(root.locationStreams as object).length).toBe(3);
  });

  it('concurrent same-stream accepts serialize — one wins', async () => {
    // Memory fake serializes tx updates deterministically; both packets target
    // the same seq — exactly one may advance the cursor.
    await accept('d1', parsed({ locationSeq: 1 }));
    const results = await Promise.allSettled([
      accept('d1', parsed({ locationSeq: 2 })),
      accept('d1', parsed({ locationSeq: 2 })),
    ]);
    const ok = results.filter((r) => r.status === 'fulfilled').length;
    const failed = results.filter((r) => r.status === 'rejected').length;
    expect(ok).toBe(1);
    expect(failed).toBe(1);
    const node = (root.locationStreams as Record<string, unknown>).d1 as Record<
      string,
      unknown
    >;
    expect(node.lastAcceptedSeq).toBe(2);
  });

  it('LocationDomainError type on rejections', async () => {
    await accept('d1', parsed({ locationSeq: 3 }));
    await expect(accept('d1', parsed({ locationSeq: 3 }))).rejects.toBeInstanceOf(
      LocationDomainError,
    );
  });
});
