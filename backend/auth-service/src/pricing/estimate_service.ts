/**
 * Phase 5B — pricing estimate orchestration.
 *
 * Flow: validate → load rules → Google Routes → 5A calculateFare → write snapshot → respond.
 */

import { randomUUID } from 'crypto';
import type { Firestore } from 'firebase-admin/firestore';
import { calculateFare } from './fare_calculator';
import { PricingRulesRepository } from './pricing_rules_repository';
import {
  PRICING_CURRENCY_PKR,
  PricingError,
} from './types';
import type { PricingSnapshotDoc } from '../rides/types';
import type { RoutingProvider } from '../routing/types';
import { RoutingError } from '../routing/types';
import { RIDE_LIST_SERVICE_TYPES } from '../rides/list_query';

export const PRICING_SNAPSHOTS_COLLECTION = 'pricingSnapshots';
export const PRICING_SNAPSHOT_TTL_MS = 10 * 60 * 1000;

const ESTIMATE_ALLOWED_KEYS = new Set([
  'pickup',
  'destination',
  'city',
  'category',
  'serviceType',
  'stops',
]);

export interface EstimateLatLng {
  lat: number;
  lng: number;
  address?: string;
}

export interface PricingEstimateResult {
  pricingSnapshotId: string;
  recommendedFareMinor: number;
  offerBoundMinMinor: number;
  offerBoundMaxMinor: number;
  currency: typeof PRICING_CURRENCY_PKR;
  pricingRulesVersion: string;
  computedAt: string;
  expiresAt: string;
  distanceKm: number;
  durationMin: number;
  category: string;
  /** Ora Courier v2 — per-leg metrics when stops were supplied. */
  legs?: { distanceKm: number; durationMin: number }[];
  /** Ora Courier v2 — fixed surcharges included in recommendedFareMinor. */
  stopFeesMinor?: number;
  serviceFeeMinor?: number;
  /**
   * Optional Google encoded polyline for map preview only (MAP-1).
   * Not pricing authority — never used in fare calculation or snapshot inputs.
   */
  encodedPolyline?: string;
}

function rejectUnknownKeys(
  body: unknown,
  allowed: Set<string>,
): Record<string, unknown> {
  if (body == null || typeof body !== 'object' || Array.isArray(body)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      'Request body must be a JSON object.',
    );
  }
  const obj = body as Record<string, unknown>;
  const extra = Object.keys(obj).filter((k) => !allowed.has(k));
  if (extra.length > 0) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `Unknown or forbidden fields: ${extra.join(', ')}.`,
    );
  }
  return obj;
}

function parseEstimateLatLng(raw: unknown, field: string): EstimateLatLng {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field} must be an object with lat/lng.`,
    );
  }
  const obj = raw as Record<string, unknown>;
  const lat = obj.lat;
  const lng = obj.lng;
  if (typeof lat !== 'number' || typeof lng !== 'number') {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field}.lat and ${field}.lng must be numbers.`,
    );
  }
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field} coordinates must be finite.`,
    );
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new PricingError(
      'VALIDATION_ERROR',
      400,
      `${field} coordinates are out of range.`,
    );
  }
  const point: EstimateLatLng = { lat, lng };
  if (typeof obj.address === 'string') {
    point.address = obj.address;
  }
  return point;
}

export class PricingEstimateService {
  private readonly rules: PricingRulesRepository;

  constructor(
    private readonly db: Firestore,
    private readonly routing: RoutingProvider,
    options?: { rulesCacheTtlMs?: number },
  ) {
    this.rules = new PricingRulesRepository(db, {
      cacheTtlMs: options?.rulesCacheTtlMs,
    });
  }

  async estimate(input: {
    body: unknown;
    now?: Date;
  }): Promise<PricingEstimateResult> {
    const body = rejectUnknownKeys(input.body, ESTIMATE_ALLOWED_KEYS);
    const pickup = parseEstimateLatLng(body.pickup, 'pickup');
    const destination = parseEstimateLatLng(body.destination, 'destination');

    const categoryRaw = body.category;
    if (typeof categoryRaw !== 'string' || !categoryRaw.trim()) {
      throw new PricingError(
        'VALIDATION_ERROR',
        400,
        'category is required.',
      );
    }

    if (body.city === undefined || body.city === null || body.city === '') {
      throw new PricingError(
        'VALIDATION_ERROR',
        400,
        'city is required.',
      );
    }

    let serviceType = 'ride';
    if (body.serviceType !== undefined) {
      if (
        typeof body.serviceType !== 'string' ||
        !(RIDE_LIST_SERVICE_TYPES as readonly string[]).includes(
          body.serviceType.trim(),
        )
      ) {
        throw new PricingError(
          'VALIDATION_ERROR',
          400,
          'serviceType must be one of: ride, courier, buy_deliver, intercity, move.',
        );
      }
      serviceType = body.serviceType.trim();
    }

    // Ora Courier v2 — optional ordered stop waypoints (2–10). When present
    // they ARE the route: pickup/destination must match first/last.
    let waypoints: { lat: number; lng: number; address?: string }[] | null =
      null;
    if (body.stops !== undefined) {
      if (!Array.isArray(body.stops)) {
        throw new PricingError(
          'VALIDATION_ERROR',
          400,
          'stops must be an array of 2–10 waypoints.',
        );
      }
      if (body.stops.length < 2 || body.stops.length > 10) {
        throw new PricingError(
          'VALIDATION_ERROR',
          400,
          'stops must contain between 2 and 10 waypoints.',
        );
      }
      waypoints = body.stops.map((s, i) =>
        parseEstimateLatLng(s, `stops[${i}]`),
      );
      if (
        waypoints[0].lat !== pickup.lat ||
        waypoints[0].lng !== pickup.lng ||
        waypoints[waypoints.length - 1].lat !== destination.lat ||
        waypoints[waypoints.length - 1].lng !== destination.lng
      ) {
        throw new PricingError(
          'VALIDATION_ERROR',
          400,
          'stops must begin at pickup and end at destination.',
        );
      }
    }

    // Fail closed before calling Google if rules are missing.
    const rules = await this.rules.loadActiveRule({
      city: body.city,
      category: categoryRaw,
    });

    let route;
    let legs: { distanceKm: number; durationMin: number }[] | undefined;
    try {
      if (waypoints && this.routing.computeRoute) {
        route = await this.routing.computeRoute({ waypoints });
        legs = route.legs;
      } else if (waypoints) {
        // Providers without multi-leg support: sum consecutive legs.
        const legResults = [] as {
          distanceKm: number;
          durationMin: number;
        }[];
        for (let i = 0; i + 1 < waypoints.length; i++) {
          legResults.push(
            await this.routing.computeDriveRoute({
              origin: waypoints[i],
              destination: waypoints[i + 1],
            }),
          );
        }
        legs = legResults;
        route = {
          distanceKm: legResults.reduce((s, l) => s + l.distanceKm, 0),
          durationMin: legResults.reduce((s, l) => s + l.durationMin, 0),
          provider: 'haversine' as const,
        };
      } else {
        route = await this.routing.computeDriveRoute({
          origin: { lat: pickup.lat, lng: pickup.lng },
          destination: { lat: destination.lat, lng: destination.lng },
        });
      }
    } catch (err) {
      if (err instanceof RoutingError) {
        throw new PricingError(err.code, err.httpStatus, err.message);
      }
      throw new PricingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    const fare = calculateFare({
      distanceKm: route.distanceKm,
      durationMin: route.durationMin,
      category: rules.category,
      city: rules.city,
      rules,
    });

    // Ora Courier v2 — fixed surcharges on top of the distance/duration fare.
    // Added to recommended AND both bounds so negotiation spans the full due.
    const extraStops = Math.max(0, (waypoints?.length ?? 2) - 2);
    const stopFeesMinor = extraStops * (rules.perStopFeeMinor ?? 0);
    const serviceFeeMinor =
      serviceType === 'buy_deliver' ? (rules.shoppingServiceFeeMinor ?? 0) : 0;
    const surchargeMinor = stopFeesMinor + serviceFeeMinor;

    const now = input.now ?? new Date();
    const computedAt = now.toISOString();
    const expiresAt = new Date(
      now.getTime() + PRICING_SNAPSHOT_TTL_MS,
    ).toISOString();
    const snapshotId = `ps_${randomUUID()}`;

    const snapshot: PricingSnapshotDoc = {
      snapshotId,
      recommendedFareMinor: fare.recommendedFareMinor + surchargeMinor,
      offerBoundMinMinor: fare.offerBoundMinMinor + surchargeMinor,
      offerBoundMaxMinor: fare.offerBoundMaxMinor + surchargeMinor,
      currency: PRICING_CURRENCY_PKR,
      pricingRulesVersion: fare.pricingRulesVersion,
      computedAt,
      expiresAt,
      inputs: {
        ...fare.inputs,
        category: rules.category,
        serviceType,
        pickup: {
          lat: pickup.lat,
          lng: pickup.lng,
          ...(pickup.address != null ? { address: pickup.address } : {}),
        },
        destination: {
          lat: destination.lat,
          lng: destination.lng,
          ...(destination.address != null
            ? { address: destination.address }
            : {}),
        },
        ...(waypoints
          ? {
              stops: waypoints.map((w) => ({ lat: w.lat, lng: w.lng })),
              legs,
              stopFeesMinor,
              serviceFeeMinor,
            }
          : {}),
        routeProvider: route.provider,
        ...('rawRequestId' in route && route.rawRequestId
          ? { routeRequestId: route.rawRequestId }
          : {}),
      },
    };

    try {
      await this.db
        .collection(PRICING_SNAPSHOTS_COLLECTION)
        .doc(snapshotId)
        .set({ ...snapshot });
    } catch {
      throw new PricingError(
        'PRICING_UNAVAILABLE',
        503,
        'Pricing isn\'t available right now.',
      );
    }

    return {
      pricingSnapshotId: snapshotId,
      recommendedFareMinor: fare.recommendedFareMinor + surchargeMinor,
      offerBoundMinMinor: fare.offerBoundMinMinor + surchargeMinor,
      offerBoundMaxMinor: fare.offerBoundMaxMinor + surchargeMinor,
      currency: PRICING_CURRENCY_PKR,
      pricingRulesVersion: fare.pricingRulesVersion,
      computedAt,
      expiresAt,
      distanceKm: route.distanceKm,
      durationMin: route.durationMin,
      category: rules.category,
      ...(legs ? { legs } : {}),
      ...(surchargeMinor > 0
        ? { stopFeesMinor, serviceFeeMinor }
        : {}),
      ...(typeof route.encodedPolyline === 'string' &&
      route.encodedPolyline.trim().length > 0
        ? { encodedPolyline: route.encodedPolyline.trim() }
        : {}),
    };
  }
}
