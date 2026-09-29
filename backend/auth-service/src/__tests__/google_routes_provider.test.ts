import { describe, expect, it, vi } from 'vitest';
import {
  GOOGLE_ROUTES_FIELD_MASK,
  GoogleRoutesProvider,
  metersToKm,
  parseGoogleDurationToMinutes,
} from '../routing/google_routes_provider';
import { RoutingError } from '../routing/types';

function jsonResponse(status: number, body: unknown): Response {
  return {
    status,
    ok: status >= 200 && status < 300,
    json: async () => body,
  } as Response;
}

describe('google routes provider — conversion helpers', () => {
  it('1–2. converts meters and duration', () => {
    expect(metersToKm(5800)).toBe(5.8);
    expect(parseGoogleDurationToMinutes('840s')).toBe(14);
    expect(parseGoogleDurationToMinutes(120)).toBe(2);
  });

  it('rejects zero/negative distance', () => {
    expect(() => metersToKm(0)).toThrow(RoutingError);
    expect(() => metersToKm(-1)).toThrow(RoutingError);
  });

  it('rejects invalid duration', () => {
    expect(() => parseGoogleDurationToMinutes('nope')).toThrow(RoutingError);
    expect(() => parseGoogleDurationToMinutes('0s')).toThrow(RoutingError);
  });
});

describe('google routes provider — HTTP boundary', () => {
  it('3. valid Google route response', async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      const headers = init?.headers as Record<string, string>;
      expect(headers['X-Goog-FieldMask']).toBe(GOOGLE_ROUTES_FIELD_MASK);
      expect(headers['X-Goog-Api-Key']).toBe('test-key');
      expect(String(headers['X-Goog-Api-Key'])).not.toContain('AIza');
      const body = JSON.parse(String(init?.body));
      expect(body.travelMode).toBe('DRIVE');
      return jsonResponse(200, {
        routes: [{ distanceMeters: 5800, duration: '840s' }],
      });
    });

    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    const result = await provider.computeDriveRoute({
      origin: { lat: 31.52, lng: 74.35 },
      destination: { lat: 31.51, lng: 74.34 },
    });
    expect(result).toEqual({
      distanceKm: 5.8,
      durationMin: 14,
      provider: 'google_routes',
    });
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it('4. missing routes → ROUTE_UNAVAILABLE', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        jsonResponse(200, { routes: [] })) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'ROUTE_UNAVAILABLE', httpStatus: 422 });
  });

  it('5. malformed response → PRICING_UNAVAILABLE', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        jsonResponse(200, {
          routes: [{ distanceMeters: 'x', duration: '10s' }],
        })) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });

  it('6. provider 4xx → ROUTE_UNAVAILABLE (or PRICING for auth)', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        jsonResponse(400, { error: { message: 'bad' } })) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'ROUTE_UNAVAILABLE' });

    const forbidden = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        jsonResponse(403, { error: { message: 'denied' } })) as unknown as typeof fetch,
    });
    await expect(
      forbidden.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE', httpStatus: 503 });
  });

  it('7. provider 5xx → PRICING_UNAVAILABLE', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        jsonResponse(503, { error: { message: 'down' } })) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE', httpStatus: 503 });
  });

  it('8. timeout / abort → PRICING_UNAVAILABLE', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      timeoutMs: 5,
      fetchImpl: (async (_url, init) => {
        await new Promise((_, reject) => {
          init?.signal?.addEventListener('abort', () => {
            const err = new Error('aborted');
            err.name = 'AbortError';
            reject(err);
          });
        });
        return jsonResponse(200, {});
      }) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });

  it('9. invalid provider JSON body → PRICING_UNAVAILABLE', async () => {
    const provider = new GoogleRoutesProvider({
      apiKey: 'test-key',
      fetchImpl: (async () =>
        ({
          status: 200,
          json: async () => {
            throw new Error('bad json');
          },
        }) as Response) as unknown as typeof fetch,
    });
    await expect(
      provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      }),
    ).rejects.toMatchObject({ code: 'PRICING_UNAVAILABLE' });
  });

  it('10. no secret leakage in thrown errors', async () => {
    const secret = 'super-secret-routes-key-xyz';
    const provider = new GoogleRoutesProvider({
      apiKey: secret,
      fetchImpl: (async () =>
        jsonResponse(500, { error: { message: 'boom' } })) as unknown as typeof fetch,
    });
    try {
      await provider.computeDriveRoute({
        origin: { lat: 31.52, lng: 74.35 },
        destination: { lat: 31.51, lng: 74.34 },
      });
      expect.unreachable();
    } catch (err) {
      expect(String(err)).not.toContain(secret);
      expect(JSON.stringify(err)).not.toContain(secret);
    }
  });

  it('11. field mask constant is minimal D/T only', () => {
    expect(GOOGLE_ROUTES_FIELD_MASK).toBe(
      'routes.distanceMeters,routes.duration',
    );
  });
});
