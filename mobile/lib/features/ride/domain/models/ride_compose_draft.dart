import 'resolved_passenger_location.dart';

/// COMPOSE-DRAFT: durable snapshot of an in-progress ride request so a
/// process death / back-navigation never loses the passenger's work.
///
/// What is persisted: endpoint points (with whether the passenger had
/// confirmed them), free-text field contents, category, service type, and
/// the offer draft text. What is NOT persisted: pricing snapshots, fare
/// bounds, or any server-derived value — estimates are always refetched
/// after a restore, so a stale snapshot can never leak into a create.
class RideComposeDraft {
  const RideComposeDraft({
    required this.savedAtMillis,
    required this.categoryId,
    required this.serviceType,
    this.pickup,
    this.destination,
    this.pickupText = '',
    this.destinationText = '',
    this.passengerOfferDraftText = '',
  });

  final int savedAtMillis;
  final String categoryId;
  final String serviceType;
  final RideComposeDraftPoint? pickup;
  final RideComposeDraftPoint? destination;
  final String pickupText;
  final String destinationText;

  /// Whole-rupee offer draft — revalidated against the *fresh* estimate on
  /// restore; never treated as authoritative.
  final String passengerOfferDraftText;

  /// Drafts older than this are discarded — a stale ride request is worse
  /// than none.
  static const Duration maxAge = Duration(hours: 24);

  bool isStaleAt(DateTime now) {
    final saved =
        DateTime.fromMillisecondsSinceEpoch(savedAtMillis, isUtc: true);
    return now.toUtc().difference(saved) > maxAge;
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'savedAt': savedAtMillis,
        'categoryId': categoryId,
        'serviceType': serviceType,
        'pickup': pickup?.toJson(),
        'destination': destination?.toJson(),
        'pickupText': pickupText,
        'destinationText': destinationText,
        'offerDraft': passengerOfferDraftText,
      };

  /// Corrupt/partial payloads decode to null — callers treat as "no draft".
  static RideComposeDraft? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final savedAt = raw['savedAt'];
    final categoryId = raw['categoryId'];
    final serviceType = raw['serviceType'];
    if (savedAt is! int ||
        categoryId is! String ||
        serviceType is! String) {
      return null;
    }
    return RideComposeDraft(
      savedAtMillis: savedAt,
      categoryId: categoryId,
      serviceType: serviceType,
      pickup: RideComposeDraftPoint.tryFromJson(raw['pickup']),
      destination: RideComposeDraftPoint.tryFromJson(raw['destination']),
      pickupText: raw['pickupText'] is String ? raw['pickupText'] as String : '',
      destinationText: raw['destinationText'] is String
          ? raw['destinationText'] as String
          : '',
      passengerOfferDraftText:
          raw['offerDraft'] is String ? raw['offerDraft'] as String : '',
    );
  }
}

/// One endpoint of a compose draft. [confirmed] mirrors the compose model —
/// a restored proposal still shows its confirm affordance; a confirmed point
/// restores straight into confirmed.
class RideComposeDraftPoint {
  const RideComposeDraftPoint({
    required this.lat,
    required this.lng,
    required this.source,
    required this.confirmed,
    this.address,
    this.placeId,
    this.displayName,
  });

  final double lat;
  final double lng;
  final PassengerLocationSource source;
  final bool confirmed;
  final String? address;
  final String? placeId;
  final String? displayName;

  ResolvedPassengerLocation toLocation() => ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        source: source,
        address: address,
        placeId: placeId,
        displayName: displayName,
        // GPS accuracy is a live-fix property — never persisted/restored.
      );

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lng': lng,
        'source': source.name,
        'confirmed': confirmed,
        'address': address,
        'placeId': placeId,
        'displayName': displayName,
      };

  static RideComposeDraftPoint? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    final sourceName = raw['source'];
    final confirmed = raw['confirmed'];
    if (lat is! num || lng is! num || sourceName is! String) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    PassengerLocationSource source;
    try {
      source = PassengerLocationSource.values.byName(sourceName);
    } on ArgumentError {
      return null;
    }
    return RideComposeDraftPoint(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      source: source,
      confirmed: confirmed == true,
      address: raw['address'] is String ? raw['address'] as String : null,
      placeId: raw['placeId'] is String ? raw['placeId'] as String : null,
      displayName:
          raw['displayName'] is String ? raw['displayName'] as String : null,
    );
  }
}
