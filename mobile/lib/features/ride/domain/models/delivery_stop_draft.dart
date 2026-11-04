/// Ora Courier v2 — customer-edited intermediate stop on the booking form.
/// The first/last waypoints are the existing pickup/destination fields;
/// these drafts only model stops inserted in between.
class ShopItemDraft {
  const ShopItemDraft({
    this.name = '',
    this.quantity = 1,
    this.note = '',
  });

  final String name;
  final int quantity;
  final String note;

  bool get isValid => name.trim().isNotEmpty && quantity >= 1;

  ShopItemDraft copyWith({String? name, int? quantity, String? note}) =>
      ShopItemDraft(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        note: note ?? this.note,
      );

  Map<String, Object?> toApiMap() => <String, Object?>{
        'name': name.trim(),
        'qty': quantity,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      };
}

/// PICKUP | SHOP | DROPOFF — types allowed depend on the service type:
/// courier inserts PICKUP/DROPOFF stops; buy_deliver inserts SHOP stops.
class DeliveryStopDraft {
  const DeliveryStopDraft({
    required this.type,
    this.locationText = '',
    this.lat,
    this.lng,
    this.label = '',
    this.instructions = '',
    this.items = const [],
    this.shopBudgetMinor,
  });

  /// PICKUP | SHOP | DROPOFF.
  final String type;
  final String locationText;
  final double? lat;
  final double? lng;
  final String label;
  final String instructions;
  final List<ShopItemDraft> items;
  final int? shopBudgetMinor;

  bool get hasLocation => lat != null && lng != null;

  bool get isValid {
    if (!hasLocation) return false;
    if (type == 'SHOP' && !items.any((i) => i.isValid)) return false;
    return true;
  }

  DeliveryStopDraft copyWith({
    String? type,
    String? locationText,
    double? lat,
    double? lng,
    String? label,
    String? instructions,
    List<ShopItemDraft>? items,
    int? shopBudgetMinor,
    bool clearBudget = false,
  }) =>
      DeliveryStopDraft(
        type: type ?? this.type,
        locationText: locationText ?? this.locationText,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        label: label ?? this.label,
        instructions: instructions ?? this.instructions,
        items: items ?? this.items,
        shopBudgetMinor:
            clearBudget ? null : (shopBudgetMinor ?? this.shopBudgetMinor),
      );

  /// Backend wire shape — `type`/`location` are required; item fields only
  /// appear on SHOP stops (server rejects them elsewhere).
  Map<String, Object?> toApiMap() => <String, Object?>{
        'type': type,
        'location': <String, Object?>{'lat': lat, 'lng': lng},
        if (label.trim().isNotEmpty) 'label': label.trim(),
        if (instructions.trim().isNotEmpty)
          'instructions': instructions.trim(),
        if (type == 'SHOP')
          'items': items
              .where((i) => i.isValid)
              .map((i) => i.toApiMap())
              .toList(),
        if (type == 'SHOP' && shopBudgetMinor != null)
          'shopBudgetMinor': shopBudgetMinor,
      };
}
