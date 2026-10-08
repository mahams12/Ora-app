/// Backend-owned pricing estimate result (Phase 5C).
///
/// Field names match POST /v1/pricing/estimate response `data`.
class PricingEstimate {
  const PricingEstimate({
    required this.pricingSnapshotId,
    required this.recommendedFareMinor,
    required this.offerBoundMinMinor,
    required this.offerBoundMaxMinor,
    required this.currency,
    required this.pricingRulesVersion,
    required this.computedAt,
    required this.expiresAt,
    required this.distanceKm,
    required this.durationMin,
    required this.category,
    this.encodedPolyline,
  });

  final String pricingSnapshotId;
  final int recommendedFareMinor;
  final int offerBoundMinMinor;
  final int offerBoundMaxMinor;
  final String currency;
  final String pricingRulesVersion;
  final String computedAt;
  final String expiresAt;
  final double distanceKm;
  final double durationMin;
  final String category;

  /// Optional Google encoded polyline for map preview only (MAP-1).
  /// Display-only — never used for fare authority.
  final String? encodedPolyline;

  bool get hasUsableEncodedPolyline {
    final value = encodedPolyline?.trim();
    return value != null && value.isNotEmpty;
  }

  bool isExpiredAt(DateTime now) {
    final expires = DateTime.tryParse(expiresAt);
    if (expires == null) return true;
    return !expires.isAfter(now.toUtc());
  }

  factory PricingEstimate.fromJson(Map<String, dynamic> json) {
    final snapshotId = json['pricingSnapshotId'];
    if (snapshotId is! String || snapshotId.trim().isEmpty) {
      throw const FormatException('pricingSnapshotId missing');
    }
    if (!snapshotId.startsWith('ps_')) {
      // Soft check — backend uses ps_ prefix; still accept if non-empty string
      // but Flutter must never generate one.
    }
    int asInt(Object? v, String field) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      throw FormatException('$field missing');
    }

    double asDouble(Object? v, String field) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      throw FormatException('$field missing');
    }

    String asString(Object? v, String field) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      throw FormatException('$field missing');
    }

    String? asOptionalPolyline(Object? v) {
      if (v == null) return null;
      if (v is! String) return null;
      final trimmed = v.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return PricingEstimate(
      pricingSnapshotId: snapshotId.trim(),
      recommendedFareMinor: asInt(json['recommendedFareMinor'], 'recommendedFareMinor'),
      offerBoundMinMinor: asInt(json['offerBoundMinMinor'], 'offerBoundMinMinor'),
      offerBoundMaxMinor: asInt(json['offerBoundMaxMinor'], 'offerBoundMaxMinor'),
      currency: asString(json['currency'], 'currency'),
      pricingRulesVersion:
          asString(json['pricingRulesVersion'], 'pricingRulesVersion'),
      computedAt: asString(json['computedAt'], 'computedAt'),
      expiresAt: asString(json['expiresAt'], 'expiresAt'),
      distanceKm: asDouble(json['distanceKm'], 'distanceKm'),
      durationMin: asDouble(json['durationMin'], 'durationMin'),
      category: asString(json['category'], 'category'),
      encodedPolyline: asOptionalPolyline(json['encodedPolyline']),
    );
  }
}

enum PricingStatus {
  idle,
  loading,
  success,
  pricingUnavailable,
  routeUnavailable,
  error,
}

enum PricingFailureKind {
  pricingUnavailable,
  routeUnavailable,
  network,
  validation,
  unknown,
}

class PricingClientException implements Exception {
  const PricingClientException(this.kind, [this.message]);

  final PricingFailureKind kind;
  final String? message;

  @override
  String toString() => 'PricingClientException($kind, $message)';
}

/// Inputs for POST /v1/pricing/estimate — no distance/fare/snapshot fields.
class PricingEstimateRequest {
  const PricingEstimateRequest({
    required this.pickupLat,
    required this.pickupLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.category,
    required this.city,
    this.pickupAddress,
    this.destinationAddress,
    this.serviceType = 'ride',
  });

  final double pickupLat;
  final double pickupLng;
  final String? pickupAddress;
  final double destinationLat;
  final double destinationLng;
  final String? destinationAddress;
  final String category;
  final String city;
  final String serviceType;

  Map<String, Object?> toJson() => <String, Object?>{
        'pickup': <String, Object?>{
          'lat': pickupLat,
          'lng': pickupLng,
          if (pickupAddress != null) 'address': pickupAddress,
        },
        'destination': <String, Object?>{
          'lat': destinationLat,
          'lng': destinationLng,
          if (destinationAddress != null) 'address': destinationAddress,
        },
        'category': category,
        'city': city,
        'serviceType': serviceType,
      };
}

abstract class PricingEstimatePort {
  Future<PricingEstimate> estimate(PricingEstimateRequest request);
}
