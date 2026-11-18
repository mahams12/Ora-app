import 'dart:convert';

import 'package:flutter/material.dart';

/// A vendor listing as served by /v1/marketplace + /v1/vendor/listings.
///
/// One unified shape across the three verticals (`service`, `rental`,
/// `cargo`): per-type extras (amenities, capacity, availability…) travel in
/// the bounded `details` map, matching the backend contract.
class MarketplaceListing {
  const MarketplaceListing({
    required this.listingId,
    required this.vendorId,
    required this.vendorName,
    required this.type,
    required this.categoryId,
    required this.subcategoryId,
    required this.title,
    required this.description,
    required this.price,
    required this.priceUnit,
    required this.location,
    required this.details,
    required this.photos,
    required this.contactNumber,
    required this.status,
    required this.createdAt,
    this.publishedAt,
  });

  final String listingId;
  final String vendorId;
  final String vendorName;
  final String type;
  final String categoryId;
  final String subcategoryId;
  final String title;
  final String description;
  final int price;
  final String priceUnit;
  final String location;
  final Map<String, dynamic> details;
  final List<String> photos;
  final String contactNumber;
  final String status;
  final DateTime createdAt;
  final DateTime? publishedAt;

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) {
    return MarketplaceListing(
      listingId: json['listingId'] as String,
      vendorId: json['vendorId'] as String,
      vendorName: json['vendorName'] as String? ?? 'ORA Vendor',
      type: json['type'] as String,
      categoryId: json['categoryId'] as String,
      subcategoryId: json['subcategoryId'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toInt(),
      priceUnit: json['priceUnit'] as String,
      location: json['location'] as String,
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      photos: (json['photos'] as List<dynamic>?)?.cast<String>() ?? const [],
      contactNumber: json['contactNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'published',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      publishedAt: json['publishedAt'] != null
          ? DateTime.tryParse(json['publishedAt'] as String)
          : null,
    );
  }

  // ---- Per-vertical convenience accessors over `details`. ----

  String? detailString(String key) {
    final v = details[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  List<String> detailList(String key) {
    final v = details[key];
    return v is List ? v.whereType<String>().toList() : const [];
  }

  String get subcategoryName => detailString('subcategoryName') ?? '';
  List<String> get amenities => detailList('amenities');
  List<String> get features => detailList('features');
  String? get availableFrom => detailString('availableFrom');
  String? get availableTo => detailString('availableTo');
  String? get timing => detailString('timing');
  String? get email => detailString('email');
  String? get capacity => detailString('capacity');
  String? get serviceArea => detailString('serviceArea');
  String? get availability => detailString('availability');
  String? get whatsappNumber => detailString('whatsappNumber');
  String get vehicleTypeName =>
      detailString('vehicleTypeName') ?? subcategoryName;

  bool get isPublished => status == 'published';
  bool get isPaused => status == 'paused';
  bool get isDraft => status == 'draft';

  String get priceLabel =>
      'Rs ${_formatRupees(price)} / ${priceUnit.replaceFirst('Per ', '').toLowerCase()}';

  String get rateLabel => priceLabel;

  /// Decodes a base64 data-URL photo for widgets (MemoryImage).
  static ImageProvider photoProvider(String dataUrl) {
    final base64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
    return MemoryImage(base64Decode(base64));
  }

  ImageProvider? get coverImage =>
      photos.isEmpty ? null : photoProvider(photos.first);

  static String _formatRupees(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final fromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buffer.write(',');
    }
    return buffer.toString();
  }
}

/// Customer ↔ vendor booking. `request` carries the customer's payload
/// (contact + per-type details); `quote` is the vendor's priced response.
class MarketplaceBooking {
  const MarketplaceBooking({
    required this.bookingId,
    required this.listingId,
    required this.listingTitle,
    required this.type,
    required this.vendorId,
    required this.customerId,
    required this.customerName,
    required this.status,
    required this.request,
    required this.statusHistory,
    required this.createdAt,
    this.quote,
  });

  final String bookingId;
  final String listingId;
  final String listingTitle;
  final String type;
  final String vendorId;
  final String customerId;
  final String customerName;
  final String status;
  final Map<String, dynamic> request;
  final List<BookingStatusEvent> statusHistory;
  final DateTime createdAt;
  final BookingQuote? quote;

  factory MarketplaceBooking.fromJson(Map<String, dynamic> json) {
    return MarketplaceBooking(
      bookingId: json['bookingId'] as String,
      listingId: json['listingId'] as String,
      listingTitle: json['listingTitle'] as String? ?? '',
      type: json['type'] as String,
      vendorId: json['vendorId'] as String,
      customerId: json['customerId'] as String,
      customerName: json['customerName'] as String? ?? '',
      status: json['status'] as String,
      request: (json['request'] as Map<String, dynamic>?) ?? const {},
      statusHistory: [
        for (final e in (json['statusHistory'] as List<dynamic>? ?? const []))
          BookingStatusEvent.fromJson(e as Map<String, dynamic>),
      ],
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      quote: json['quote'] != null
          ? BookingQuote.fromJson(json['quote'] as Map<String, dynamic>)
          : null,
    );
  }

  String? requestString(String key) {
    final v = request[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  Map<String, dynamic> get requestDetails {
    final d = request['details'];
    return d is Map<String, dynamic> ? d : request;
  }

  bool get isTerminal =>
      status == 'completed' || status == 'rejected' || status == 'cancelled';
}

class BookingStatusEvent {
  const BookingStatusEvent({required this.status, required this.at});

  final String status;
  final DateTime at;

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) {
    return BookingStatusEvent(
      status: json['status'] as String,
      at:
          DateTime.tryParse(json['at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class BookingQuote {
  const BookingQuote({required this.amount, this.note});

  final int amount;
  final String? note;

  factory BookingQuote.fromJson(Map<String, dynamic> json) {
    return BookingQuote(
      amount: (json['amount'] as num).toInt(),
      note: json['note'] as String?,
    );
  }

  String get label => 'Rs ${MarketplaceListing._formatRupees(amount)}';
}
