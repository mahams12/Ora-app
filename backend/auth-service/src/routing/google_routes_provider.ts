/**
 * Google Routes API (computeRoutes) — Phase 4B production RoutingProvider.
 *
 * Credential: GOOGLE_MAPS_SERVER_KEY (server only; never log or return).
 * Field mask (minimum authoritative): routes.distanceMeters,routes.duration
 */

import {
  RoutingError,
  type ComputeDriveRouteInput,
  type DriveRouteResult,
  type RoutingProvider,
} from './types';

export const GOOGLE_ROUTES_COMPUTE_URL =
  'https://routes.googleapis.com/directions/v2:computeRoutes';

/** Minimum field mask for authoritative D/T. Polyline intentionally omitted. */
export const GOOGLE_ROUTES_FIELD_MASK =
  'routes.distanceMeters,routes.duration';

const DEFAULT_TIMEOUT_MS = 12_000;

export interface GoogleRoutesProviderOptions {
  apiKey: string;
  /** Injectable for tests. */
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  computeUrl?: string;
}

function assertFiniteCoordinate(value: number, field: string): void {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new RoutingError(
      'VALIDATION_ERROR',
      400,
      `${field} must be a finite number.`,
    );
  }
}

/** Parse Routes API duration string ("123s") or numeric seconds. */
export function parseGoogleDurationToMinutes(raw: unknown): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    if (raw <= 0) {
      throw new RoutingError(
        'ROUTE_UNAVAILABLE',
        422,
        'Unable to determine a route for those points.',
      );
    }
    return raw / 60;
  }
  if (typeof raw === 'string') {
    const m = /^(\d+(?:\.\d+)?)s$/.exec(raw.trim());
    if (!m) {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }
    const seconds = Number(m[1]);
    if (!Number.isFinite(seconds) || seconds <= 0) {
      throw new RoutingError(
        'ROUTE_UNAVAILABLE',
        422,
        'Unable to determine a route for those points.',
      );
    }
    return seconds / 60;
  }
  throw new RoutingError(
    'PRICING_UNAVAILABLE',
    503,
    'Pricing isn\'t available right now.',
  );
}

export function metersToKm(meters: number): number {
  if (!Number.isFinite(meters) || meters <= 0) {
    throw new RoutingError(
      'ROUTE_UNAVAILABLE',
      422,
      'Unable to determine a route for those points.',
    );
  }
  return meters / 1000;
}

export function createGoogleRoutesProviderFromEnv(
  env: NodeJS.ProcessEnv = process.env,
  options?: Omit<GoogleRoutesProviderOptions, 'apiKey'>,
): GoogleRoutesProvider {
  const apiKey = env.GOOGLE_MAPS_SERVER_KEY?.trim() ?? '';
  if (!apiKey) {
    throw new Error(
      'Missing required environment variable: GOOGLE_MAPS_SERVER_KEY',
    );
  }
  return new GoogleRoutesProvider({ ...options, apiKey });
}

export class GoogleRoutesProvider implements RoutingProvider {
  private readonly apiKey: string;
  private readonly fetchImpl: typeof fetch;
  private readonly timeoutMs: number;
  private readonly computeUrl: string;

  constructor(options: GoogleRoutesProviderOptions) {
    const key = options.apiKey?.trim() ?? '';
    if (!key) {
      throw new Error('GOOGLE_MAPS_SERVER_KEY is required for GoogleRoutesProvider.');
    }
    this.apiKey = key;
    this.fetchImpl = options.fetchImpl ?? fetch;
    this.timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.computeUrl = options.computeUrl ?? GOOGLE_ROUTES_COMPUTE_URL;
  }

  async computeDriveRoute(
    input: ComputeDriveRouteInput,
  ): Promise<DriveRouteResult> {
    assertFiniteCoordinate(input.origin.lat, 'origin.lat');
    assertFiniteCoordinate(input.origin.lng, 'origin.lng');
    assertFiniteCoordinate(input.destination.lat, 'destination.lat');
    assertFiniteCoordinate(input.destination.lng, 'destination.lng');

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let response: Response;
    try {
      response = await this.fetchImpl(this.computeUrl, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': this.apiKey,
          'X-Goog-FieldMask': GOOGLE_ROUTES_FIELD_MASK,
        },
        body: JSON.stringify({
          origin: {
            location: {
              latLng: {
                latitude: input.origin.lat,
                longitude: input.origin.lng,
              },
            },
          },
          destination: {
            location: {
              latLng: {
                latitude: input.destination.lat,
                longitude: input.destination.lng,
              },
            },
          },
          travelMode: 'DRIVE',
        }),
      });
    } catch (err) {
      const aborted =
        err instanceof Error &&
        (err.name === 'AbortError' || /aborted/i.test(err.message));
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        aborted
          ? 'Pricing isn\'t available right now.'
          : 'Pricing isn\'t available right now.',
      );
    } finally {
      clearTimeout(timer);
    }

    if (response.status >= 500) {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    let payload: unknown;
    try {
      payload = await response.json();
    } catch {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    if (response.status >= 400) {
      // Client/provider rejection of the route request — do not invent a fare.
      // Prefer ROUTE_UNAVAILABLE for unroutable; config/auth → PRICING_UNAVAILABLE.
      const status = response.status;
      if (status === 403 || status === 401 || status === 429) {
        throw new RoutingError(
          'PRICING_UNAVAILABLE',
          503,
          'Pricing isn\'t available right now.',
        );
      }
      throw new RoutingError(
        'ROUTE_UNAVAILABLE',
        422,
        'Unable to determine a route for those points.',
      );
    }

    if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    const routes = (payload as { routes?: unknown }).routes;
    if (!Array.isArray(routes) || routes.length === 0) {
      throw new RoutingError(
        'ROUTE_UNAVAILABLE',
        422,
        'Unable to determine a route for those points.',
      );
    }

    const first = routes[0];
    if (first == null || typeof first !== 'object' || Array.isArray(first)) {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    const distanceMeters = (first as { distanceMeters?: unknown }).distanceMeters;
    const duration = (first as { duration?: unknown }).duration;
    if (typeof distanceMeters !== 'number' || !Number.isFinite(distanceMeters)) {
      throw new RoutingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    const distanceKm = metersToKm(distanceMeters);
    const durationMin = parseGoogleDurationToMinutes(duration);

    return {
      distanceKm,
      durationMin,
      provider: 'google_routes',
    };
  }
}
