/// Ora Courier — client-side parcel manifest draft.
///
/// Mirrors the server-side `parcel` contract in `parseParcelDetails`; the
/// server remains authoritative — this only drives form validity and the
/// create-ride payload.
library;

const kParcelCategories = <String>{
  'documents',
  'food',
  'fragile',
  'electronics',
  'clothing',
  'gifts',
  'other',
};

const kParcelSizes = <String>{'SMALL', 'MEDIUM', 'LARGE'};

/// Displayed limits — keep in sync with server caps in
/// `parseParcelDetails` (weight ≤ 30 kg, quantity 1–50).
const kParcelMaxWeightKg = 30.0;
const kParcelMaxQuantity = 50;

const kParcelProhibitedItems = <String>[
  'Cash, jewellery or other valuables',
  'Illegal goods, drugs or weapons',
  'Flammable, explosive or hazardous materials',
  'Live animals',
  'Perishables without proper packaging',
];

class ParcelDraft {
  const ParcelDraft({
    this.senderName = '',
    this.senderPhone = '',
    this.receiverName = '',
    this.receiverPhone = '',
    this.parcelCategory = 'documents',
    this.size = 'SMALL',
    this.weightText = '',
    this.quantityText = '1',
    this.description = '',
    this.handlingInstructions = '',
    this.photoUrl,
  });

  final String senderName;
  final String senderPhone;
  final String receiverName;
  final String receiverPhone;
  final String parcelCategory;
  final String size;
  final String weightText;
  final String quantityText;
  final String description;
  final String handlingInstructions;
  final String? photoUrl;

  static const _phonePattern = r'^\+?[0-9][0-9\s-]{5,18}$';

  double? get weightKg {
    final v = double.tryParse(weightText.trim());
    if (v == null || v <= 0 || v > kParcelMaxWeightKg) return null;
    return v;
  }

  int? get quantity {
    final v = int.tryParse(quantityText.trim());
    if (v == null || v < 1 || v > kParcelMaxQuantity) return null;
    return v;
  }

  bool get isSenderPhoneValid =>
      senderPhone.trim().length >= 7 &&
      RegExp(_phonePattern).hasMatch(senderPhone.trim());

  bool get isReceiverPhoneValid =>
      receiverPhone.trim().length >= 7 &&
      RegExp(_phonePattern).hasMatch(receiverPhone.trim());

  bool get isValid =>
      senderName.trim().isNotEmpty &&
      isSenderPhoneValid &&
      receiverName.trim().isNotEmpty &&
      isReceiverPhoneValid &&
      kParcelCategories.contains(parcelCategory) &&
      kParcelSizes.contains(size) &&
      weightKg != null &&
      quantity != null &&
      description.trim().isNotEmpty;

  /// First validation failure message for the blocked banner.
  String? get firstError {
    if (senderName.trim().isEmpty) return 'Enter the sender name.';
    if (!isSenderPhoneValid) return 'Enter a valid sender phone number.';
    if (receiverName.trim().isEmpty) return 'Enter the receiver name.';
    if (!isReceiverPhoneValid) {
      return 'Enter a valid receiver phone number.';
    }
    if (weightKg == null) {
      return 'Enter the approximate weight (up to ${kParcelMaxWeightKg.toInt()} kg).';
    }
    if (quantity == null) return 'Enter a quantity between 1 and 50.';
    if (description.trim().isEmpty) {
      return 'Describe the parcel briefly.';
    }
    return null;
  }

  ParcelDraft copyWith({
    String? senderName,
    String? senderPhone,
    String? receiverName,
    String? receiverPhone,
    String? parcelCategory,
    String? size,
    String? weightText,
    String? quantityText,
    String? description,
    String? handlingInstructions,
    String? photoUrl,
    bool clearPhoto = false,
  }) {
    return ParcelDraft(
      senderName: senderName ?? this.senderName,
      senderPhone: senderPhone ?? this.senderPhone,
      receiverName: receiverName ?? this.receiverName,
      receiverPhone: receiverPhone ?? this.receiverPhone,
      parcelCategory: parcelCategory ?? this.parcelCategory,
      size: size ?? this.size,
      weightText: weightText ?? this.weightText,
      quantityText: quantityText ?? this.quantityText,
      description: description ?? this.description,
      handlingInstructions:
          handlingInstructions ?? this.handlingInstructions,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
    );
  }

  /// API payload — matches the server `parcel` contract exactly.
  Map<String, Object?> toApiMap() {
    return {
      'senderName': senderName.trim(),
      'senderPhone': senderPhone.trim(),
      'receiverName': receiverName.trim(),
      'receiverPhone': receiverPhone.trim(),
      'parcelCategory': parcelCategory,
      'size': size,
      'weightKg': weightKg,
      'quantity': quantity,
      'description': description.trim(),
      if (handlingInstructions.trim().isNotEmpty)
        'handlingInstructions': handlingInstructions.trim(),
      if (photoUrl != null && photoUrl!.trim().isNotEmpty)
        'photoUrl': photoUrl!.trim(),
    };
  }
}
