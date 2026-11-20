import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/ports/pricing_estimate_port.dart';
import '../utils/encoded_polyline_decoder.dart';

/// MAP-1 preview surface state — display only; not pricing authority.
enum RideMapPreviewStatus {
  idle,
  loading,
  ready,
  routeUnavailable,
  invalidCoordinates,
}

/// Lightweight view model for [RideMapPreview].
class RideMapPreviewModel {
  const RideMapPreviewModel({
    required this.routeIdentity,
    required this.status,
    this.pickup,
    this.destination,
    this.encodedPolyline,
    this.polylinePoints = const <LatLng>[],
    this.statusLabel = '',
    this.pickupLabel = '',
    this.destinationLabel = '',
    this.distanceKm,
    this.durationMin,
  });

  final String routeIdentity;
  final RideMapPreviewStatus status;
  final LatLng? pickup;
  final LatLng? destination;
  final String? encodedPolyline;
  final List<LatLng> polylinePoints;
  final String statusLabel;

  /// Short place label for floating pickup callout (never raw coords).
  final String pickupLabel;

  /// Short place label for floating destination callout (never raw coords).
  final String destinationLabel;

  /// Optional estimate metrics for destination callout (display only).
  final double? distanceKm;
  final double? durationMin;

  bool get hasPickup => pickup != null;
  bool get hasDestination => destination != null;
  bool get hasRouteLine => polylinePoints.length >= 2;

  bool get hasTripMetrics =>
      distanceKm != null &&
      durationMin != null &&
      distanceKm! > 0 &&
      durationMin! > 0;

  String get tripMetricsLabel {
    if (!hasTripMetrics) return '';
    final km = distanceKm!;
    final mins = durationMin!.round();
    final kmText = km >= 10
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(1);
    return '$kmText km • $mins min';
  }

  static RideMapPreviewModel fromRideRequest({
    required ResolvedPassengerLocation? confirmedPickup,
    required ResolvedPassengerLocation? confirmedDestination,
    required ResolvedPassengerLocation? proposedPickup,
    required ResolvedPassengerLocation? proposedDestination,
    required PricingStatus pricingStatus,
    required PricingEstimate? pricingEstimate,
    required bool hasUsablePricing,
  }) {
    final pickupLoc = _preferValid(confirmedPickup, proposedPickup);
    final destLoc = _preferValid(confirmedDestination, proposedDestination);
    final pickup = _toLatLng(pickupLoc);
    final destination = _toLatLng(destLoc);

    if (pickup == null && destination == null) {
      return const RideMapPreviewModel(
        routeIdentity: 'idle',
        status: RideMapPreviewStatus.idle,
        statusLabel: 'Confirm pickup & destination to continue',
      );
    }

    List<LatLng> points = const <LatLng>[];
    String? encoded;
    if (hasUsablePricing &&
        pricingEstimate != null &&
        pricingEstimate.hasUsableEncodedPolyline) {
      encoded = pricingEstimate.encodedPolyline!.trim();
      points = EncodedPolylineDecoder.decode(encoded);
    }

    final identity = buildRouteIdentity(
      pickup: pickup,
      destination: destination,
      encodedPolyline: encoded,
      pricingSnapshotId:
          hasUsablePricing ? pricingEstimate?.pricingSnapshotId : null,
    );

    final label = _statusLabel(
      hasPickup: pickup != null,
      hasDestination: destination != null,
      pickupConfirmed: confirmedPickup != null,
      destinationConfirmed: confirmedDestination != null,
      pricingStatus: pricingStatus,
      hasUsablePricing: hasUsablePricing,
      hasPolyline: points.length >= 2,
    );

    final status = switch (pricingStatus) {
      PricingStatus.loading
          when confirmedPickup != null && confirmedDestination != null =>
        RideMapPreviewStatus.loading,
      PricingStatus.routeUnavailable => RideMapPreviewStatus.routeUnavailable,
      _ => RideMapPreviewStatus.ready,
    };

    final double? distanceKm =
        hasUsablePricing ? pricingEstimate?.distanceKm : null;
    final double? durationMin =
        hasUsablePricing ? pricingEstimate?.durationMin : null;

    return RideMapPreviewModel(
      routeIdentity: identity,
      status: status,
      pickup: pickup,
      destination: destination,
      encodedPolyline: encoded,
      polylinePoints: points,
      statusLabel: label,
      pickupLabel: _shortLabel(pickupLoc),
      destinationLabel: _shortLabel(destLoc),
      distanceKm: distanceKm,
      durationMin: durationMin,
    );
  }

  /// Stable identity so stale polylines never survive coordinate changes.
  static String buildRouteIdentity({
    required LatLng? pickup,
    required LatLng? destination,
    String? encodedPolyline,
    String? pricingSnapshotId,
  }) {
    String fmt(LatLng? p) {
      if (p == null) return '-';
      return '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
    }

    final poly = encodedPolyline?.trim();
    final polyKey = (poly == null || poly.isEmpty)
        ? 'nopoly'
        : 'poly:${poly.hashCode}';
    final snap = (pricingSnapshotId == null || pricingSnapshotId.isEmpty)
        ? 'nosnap'
        : pricingSnapshotId;
    return '${fmt(pickup)}|${fmt(destination)}|$polyKey|$snap';
  }
}

ResolvedPassengerLocation? _preferValid(
  ResolvedPassengerLocation? confirmed,
  ResolvedPassengerLocation? proposed,
) {
  if (confirmed != null && confirmed.hasValidCoordinates) return confirmed;
  if (proposed != null && proposed.hasValidCoordinates) return proposed;
  return null;
}

LatLng? _toLatLng(ResolvedPassengerLocation? loc) {
  if (loc == null || !loc.hasValidCoordinates) return null;
  return LatLng(loc.lat, loc.lng);
}

String _shortLabel(ResolvedPassengerLocation? loc) {
  if (loc == null) return '';
  final raw = loc.displayLabel.trim();
  if (raw.isEmpty) return 'Location selected';
  // Prefer first clause / line for compact callout cards.
  final firstComma = raw.split(',').first.trim();
  if (firstComma.length <= 28) return firstComma;
  return '${firstComma.substring(0, 27)}…';
}

String _statusLabel({
  required bool hasPickup,
  required bool hasDestination,
  required bool pickupConfirmed,
  required bool destinationConfirmed,
  required PricingStatus pricingStatus,
  required bool hasUsablePricing,
  required bool hasPolyline,
}) {
  if (pickupConfirmed && destinationConfirmed) {
    if (pricingStatus == PricingStatus.loading) {
      return 'Loading route preview…';
    }
    if (pricingStatus == PricingStatus.routeUnavailable) {
      return 'Route unavailable · markers shown';
    }
    if (hasUsablePricing && hasPolyline) {
      return 'Pickup & destination confirmed';
    }
    return 'Pickup & destination confirmed';
  }
  if (pickupConfirmed) return 'Pickup confirmed · destination needed';
  if (destinationConfirmed) return 'Destination confirmed · pickup needed';
  if (hasPickup && hasDestination) {
    return 'Confirm pickup & destination to continue';
  }
  if (hasPickup) return 'Pickup set · destination needed';
  if (hasDestination) return 'Destination set · pickup needed';
  return 'Confirm pickup & destination to continue';
}
