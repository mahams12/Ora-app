import '../../../core/network/api_client.dart';
import '../../../core/network/request_context.dart';
import 'marketplace_models.dart';

/// Remote data source for the vendor marketplace.
///
/// Vendor writes hit `/vendor/listings*` (per-role approval + ownership
/// enforced server-side); discovery + the booking workflow live under
/// `/marketplace/*`.
class MarketplaceApi {
  const MarketplaceApi(this._apiClient);

  final ApiClient _apiClient;

  // ---- Vendor listing management ----

  Future<MarketplaceListing> createListing({
    required Map<String, dynamic> body,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/vendor/listings',
      data: body,
      context: context,
      idempotent: true,
    );
    return MarketplaceListing.fromJson(
      response.data!['listing'] as Map<String, dynamic>,
    );
  }

  Future<List<MarketplaceListing>> myListings({
    required String type,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/vendor/listings',
      queryParameters: {'type': type},
      context: context,
    );
    return [
      for (final item
          in (response.data!['listings'] as List<dynamic>? ?? const []))
        MarketplaceListing.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<MarketplaceListing> updateListing({
    required String listingId,
    required Map<String, dynamic> patch,
    required RequestContext context,
  }) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '/vendor/listings/$listingId',
      data: patch,
      context: context,
      idempotent: true,
    );
    return MarketplaceListing.fromJson(
      response.data!['listing'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteListing({
    required String listingId,
    required RequestContext context,
  }) async {
    await _apiClient.delete<void>(
      '/vendor/listings/$listingId',
      context: context,
      idempotent: true,
    );
  }

  // ---- Customer discovery ----

  Future<List<MarketplaceListing>> publishedListings({
    required String type,
    String? categoryId,
    String? subcategoryId,
    String? q,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/marketplace/listings',
      queryParameters: {
        'type': type,
        if (categoryId != null) 'categoryId': categoryId,
        if (subcategoryId != null) 'subcategoryId': subcategoryId,
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': '50',
      },
      context: context,
    );
    return [
      for (final item
          in (response.data!['listings'] as List<dynamic>? ?? const []))
        MarketplaceListing.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<MarketplaceListing> getPublishedListing({
    required String listingId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/marketplace/listings/$listingId',
      context: context,
    );
    return MarketplaceListing.fromJson(
      response.data!['listing'] as Map<String, dynamic>,
    );
  }

  // ---- Booking / quotation workflow ----

  Future<MarketplaceBooking> createBooking({
    required String listingId,
    required Map<String, dynamic> request,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/marketplace/bookings',
      data: {'listingId': listingId, 'request': request},
      context: context,
      idempotent: true,
    );
    return MarketplaceBooking.fromJson(
      response.data!['booking'] as Map<String, dynamic>,
    );
  }

  /// `role` = 'customer' (my requests) or 'vendor' (my inbox).
  Future<List<MarketplaceBooking>> bookings({
    required String role,
    String? type,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/marketplace/bookings',
      queryParameters: {'role': role, if (type != null) 'type': type},
      context: context,
    );
    return [
      for (final item
          in (response.data!['bookings'] as List<dynamic>? ?? const []))
        MarketplaceBooking.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<MarketplaceBooking> getBooking({
    required String bookingId,
    required RequestContext context,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/marketplace/bookings/$bookingId',
      context: context,
    );
    return MarketplaceBooking.fromJson(
      response.data!['booking'] as Map<String, dynamic>,
    );
  }

  /// quote | accept | reject | cancel | start | complete
  Future<MarketplaceBooking> vendorAction({
    required String bookingId,
    required String action,
    int? amount,
    String? note,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/marketplace/bookings/$bookingId/vendor-action',
      data: {
        'action': action,
        if (amount != null) 'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      context: context,
      idempotent: true,
    );
    return MarketplaceBooking.fromJson(
      response.data!['booking'] as Map<String, dynamic>,
    );
  }

  /// accept (a quote) | cancel
  Future<MarketplaceBooking> customerAction({
    required String bookingId,
    required String action,
    String? note,
    required RequestContext context,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/marketplace/bookings/$bookingId/customer-action',
      data: {
        'action': action,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      context: context,
      idempotent: true,
    );
    return MarketplaceBooking.fromJson(
      response.data!['booking'] as Map<String, dynamic>,
    );
  }
}
