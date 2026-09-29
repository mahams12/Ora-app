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
  ) {
    this.rules = new PricingRulesRepository(db);
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
          'serviceType must be one of: ride, courier, intercity, move.',
        );
      }
      serviceType = body.serviceType.trim();
    }

    // Fail closed before calling Google if rules are missing.
    const rules = await this.rules.loadActiveRule({
      city: body.city,
      category: categoryRaw,
    });

    let route;
    try {
      route = await this.routing.computeDriveRoute({
        origin: { lat: pickup.lat, lng: pickup.lng },
        destination: { lat: destination.lat, lng: destination.lng },
      });
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

    const now = input.now ?? new Date();
    const computedAt = now.toISOString();
    const expiresAt = new Date(
      now.getTime() + PRICING_SNAPSHOT_TTL_MS,
    ).toISOString();
    const snapshotId = `ps_${randomUUID()}`;

    const snapshot: PricingSnapshotDoc = {
      snapshotId,
      recommendedFareMinor: fare.recommendedFareMinor,
      offerBoundMinMinor: fare.offerBoundMinMinor,
      offerBoundMaxMinor: fare.offerBoundMaxMinor,
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
        routeProvider: route.provider,
        ...(route.rawRequestId ? { routeRequestId: route.rawRequestId } : {}),
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
      recommendedFareMinor: fare.recommendedFareMinor,
      offerBoundMinMinor: fare.offerBoundMinMinor,
      offerBoundMaxMinor: fare.offerBoundMaxMinor,
      currency: PRICING_CURRENCY_PKR,
      pricingRulesVersion: fare.pricingRulesVersion,
      computedAt,
      expiresAt,
      distanceKm: route.distanceKm,
      durationMin: route.durationMin,
      category: rules.category,
    };
  }
}
