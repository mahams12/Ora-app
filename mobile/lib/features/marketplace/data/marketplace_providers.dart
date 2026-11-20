import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/di/providers.dart';
import 'marketplace_api.dart';
import 'marketplace_models.dart';

final marketplaceApiProvider = Provider<MarketplaceApi>(
  (ref) => MarketplaceApi(ref.watch(apiClientProvider)),
);

String _newRequestId() => 'mk-${const Uuid().v4()}';

/// The signed-in vendor's own listings for one role ('service' | 'rental' |
/// 'cargo'). All statuses except deleted — drafts + paused included.
final myListingsProvider = FutureProvider.autoDispose
    .family<List<MarketplaceListing>, String>((ref, type) async {
      final api = ref.watch(marketplaceApiProvider);
      final ctx = ref
          .watch(apiClientProvider)
          .newContext(idempotencyKey: _newRequestId());
      return api.myListings(type: type, context: ctx);
    });

/// Published listings for the customer discovery surfaces — the same
/// published set the backend serves, filtered by the exact catalogue ids.
final publishedListingsProvider = FutureProvider.autoDispose
    .family<List<MarketplaceListing>, PublishedQuery>((ref, query) async {
      final api = ref.watch(marketplaceApiProvider);
      final ctx = ref.watch(apiClientProvider).newContext();
      return api.publishedListings(
        type: query.type,
        categoryId: query.categoryId,
        subcategoryId: query.subcategoryId,
        q: query.q,
        context: ctx,
      );
    });

class PublishedQuery {
  const PublishedQuery({
    required this.type,
    this.categoryId,
    this.subcategoryId,
    this.q,
  });

  final String type;
  final String? categoryId;
  final String? subcategoryId;
  final String? q;

  @override
  bool operator ==(Object other) =>
      other is PublishedQuery &&
      other.type == type &&
      other.categoryId == categoryId &&
      other.subcategoryId == subcategoryId &&
      other.q == q;

  @override
  int get hashCode => Object.hash(type, categoryId, subcategoryId, q);
}

/// The caller's bookings — role 'customer' for their own requests, 'vendor'
/// for their inbox. Optionally filtered by vertical.
final bookingsProvider = FutureProvider.autoDispose
    .family<List<MarketplaceBooking>, BookingsQuery>((ref, query) async {
      final api = ref.watch(marketplaceApiProvider);
      final ctx = ref.watch(apiClientProvider).newContext();
      return api.bookings(role: query.role, type: query.type, context: ctx);
    });

class BookingsQuery {
  const BookingsQuery({required this.role, this.type});

  final String role;
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is BookingsQuery && other.role == role && other.type == type;

  @override
  int get hashCode => Object.hash(role, type);
}

/// Vendor listing mutations — each returns the server-updated listing and
/// invalidates the owning provider so dashboards refresh from source.
final listingMutationsProvider = Provider((ref) {
  final api = ref.watch(marketplaceApiProvider);
  final client = ref.watch(apiClientProvider);

  Future<MarketplaceListing> create(Map<String, dynamic> body) async {
    final listing = await api.createListing(
      body: body,
      context: client.newContext(idempotencyKey: _newRequestId()),
    );
    ref.invalidate(myListingsProvider(listing.type));
    ref.invalidate(publishedListingsProvider);
    return listing;
  }

  Future<MarketplaceListing> update(
    MarketplaceListing current,
    Map<String, dynamic> patch,
  ) async {
    final listing = await api.updateListing(
      listingId: current.listingId,
      patch: patch,
      context: client.newContext(),
    );
    ref.invalidate(myListingsProvider(listing.type));
    ref.invalidate(publishedListingsProvider);
    return listing;
  }

  Future<void> delete(MarketplaceListing listing) async {
    await api.deleteListing(
      listingId: listing.listingId,
      context: client.newContext(),
    );
    ref.invalidate(myListingsProvider(listing.type));
    ref.invalidate(publishedListingsProvider);
  }

  return (create: create, update: update, delete: delete);
});

/// Booking mutations shared by customer + vendor flows; invalidates both
/// inbox lists so status changes propagate to every open screen.
final bookingMutationsProvider = Provider((ref) {
  final api = ref.watch(marketplaceApiProvider);
  final client = ref.watch(apiClientProvider);

  void refresh() {
    ref.invalidate(bookingsProvider);
  }

  Future<MarketplaceBooking> createBooking({
    required String listingId,
    required Map<String, dynamic> request,
  }) async {
    final booking = await api.createBooking(
      listingId: listingId,
      request: request,
      context: client.newContext(idempotencyKey: _newRequestId()),
    );
    refresh();
    return booking;
  }

  Future<MarketplaceBooking> vendorAction(
    String bookingId,
    String action, {
    int? amount,
    String? note,
  }) async {
    final booking = await api.vendorAction(
      bookingId: bookingId,
      action: action,
      amount: amount,
      note: note,
      context: client.newContext(),
    );
    refresh();
    return booking;
  }

  Future<MarketplaceBooking> customerAction(
    String bookingId,
    String action, {
    String? note,
  }) async {
    final booking = await api.customerAction(
      bookingId: bookingId,
      action: action,
      note: note,
      context: client.newContext(),
    );
    refresh();
    return booking;
  }

  return (
    createBooking: createBooking,
    vendorAction: vendorAction,
    customerAction: customerAction,
  );
});
