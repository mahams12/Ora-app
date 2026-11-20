import '../core/errors/app_failure.dart';
import '../core/network/request_context.dart';
import '../features/marketplace/data/marketplace_api.dart';
import '../features/marketplace/data/marketplace_models.dart';
import 'demo_session_store.dart';

/// DEMO/REVIEW BUILD ONLY — in-memory marketplace backend.
///
/// Seeds listings + bookings for all three verticals and applies the real
/// booking workflow locally (request → quote → accept → start → complete),
/// so posting, editing, deleting and managing are fully explorable offline.
/// All mutations live in memory for the session; nothing touches the API
/// or Firebase. The production `MarketplaceApi` is untouched.
class DemoMarketplaceApi extends MarketplaceApi {
  DemoMarketplaceApi(super.apiClient, this._session);

  final DemoSessionStore _session;

  final List<MarketplaceListing> _listings = [];
  final List<MarketplaceBooking> _bookings = [];
  var _seeded = false;
  var _counter = 0;

  String get _uid => _session.profile?.uid ?? 'demo_vendor';
  String get _name => _session.profile?.displayName ?? 'Demo Vendor';

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final now = DateTime.now().toUtc().toIso8601String();

    MarketplaceListing listing(
      String id,
      String type,
      String category,
      String sub,
      String title,
      int price,
      String unit,
      String location, {
      String vendorId = 'demo_vendor',
      String vendorName = 'Demo Vendor',
      String status = 'published',
      Map<String, dynamic> details = const {},
    }) => MarketplaceListing(
      listingId: id,
      vendorId: vendorId,
      vendorName: vendorName,
      type: type,
      categoryId: category,
      subcategoryId: sub,
      title: title,
      description:
          'Demo listing — quality guaranteed, flexible timing. '
          'This is sample content for the design review build.',
      price: price,
      priceUnit: unit,
      location: location,
      details: details,
      photos: const [],
      contactNumber: '+923001234567',
      status: status,
      createdAt: DateTime.parse(now).subtract(const Duration(days: 3)),
      publishedAt: DateTime.parse(now).subtract(const Duration(days: 3)),
    );

    // The demo user's own inventory — one published per vertical + a draft.
    _listings.addAll([
      listing(
        'my-svc-1',
        'service',
        'home_services',
        'electrician',
        'Certified Electrician — same-day visits',
        1800,
        'Per visit',
        'Gulberg III, Lahore',
        vendorId: _uid,
        vendorName: _name,
      ),
      listing(
        'my-svc-2',
        'service',
        'home_services',
        'plumber',
        'Expert Plumber — kitchens & bathrooms',
        2200,
        'Per visit',
        'DHA Phase 5, Lahore',
        vendorId: _uid,
        vendorName: _name,
        status: 'paused',
      ),
      listing(
        'my-rent-1',
        'rental',
        'residential',
        'apartments',
        'DHA Garden Apartment — 2 bed, furnished',
        55000,
        'Per month',
        'DHA Phase 6, Lahore',
        vendorId: _uid,
        vendorName: _name,
        details: const {
          'amenities': ['Wi-Fi', 'Parking', 'Air conditioning'],
        },
      ),
      listing(
        'my-cargo-1',
        'cargo',
        'trucks',
        'mazda',
        'Mazda Truck — city & intercity haulage',
        8500,
        'Per trip',
        'Model Town, Lahore',
        vendorId: _uid,
        vendorName: _name,
        details: const {'vehicleTypeName': 'Mazda Truck', 'capacity': '3 tons'},
      ),
      // Other vendors' published stock for the customer discovery screens.
      listing(
        'svc-101',
        'service',
        'home_services',
        'electrician',
        'Hassan Ahmad Services — electrician',
        1500,
        'Per visit',
        'Gulberg, Lahore',
        vendorId: 'vendor_hassan',
        vendorName: 'Hassan Ahmad Services',
      ),
      listing(
        'svc-102',
        'service',
        'home_services',
        'cleaning',
        'Zara Home Experts — deep cleaning',
        3500,
        'Per visit',
        'DHA Phase 5, Lahore',
        vendorId: 'vendor_zara',
        vendorName: 'Zara Home Experts',
      ),
      listing(
        'rent-101',
        'rental',
        'residential',
        'houses',
        'Model Town Corner Home — 5 marla',
        42000,
        'Per month',
        'Model Town, Lahore',
        vendorId: 'vendor_mian',
        vendorName: 'Mian Properties',
        details: const {
          'amenities': ['Kitchen', 'Security', 'Generator'],
        },
      ),
      listing(
        'cargo-101',
        'cargo',
        'pickups',
        'shehzore',
        'Ravi Cargo Movers — Shehzore pickup',
        2800,
        'Per trip',
        'Gulberg, Lahore',
        vendorId: 'vendor_ravi',
        vendorName: 'Ravi Cargo Movers',
      ),
    ]);

    MarketplaceBooking booking(
      String id,
      MarketplaceListing l,
      String status,
      String customerId,
      String customerName, {
      int? quote,
    }) => MarketplaceBooking(
      bookingId: id,
      listingId: l.listingId,
      listingTitle: l.title,
      type: l.type,
      vendorId: l.vendorId,
      customerId: customerId,
      customerName: customerName,
      status: status,
      request: const {
        'contactName': 'Demo Customer',
        'contactPhone': '+923001234567',
        'details': {'date': 'Tomorrow', 'note': 'Demo booking request'},
      },
      statusHistory: [
        BookingStatusEvent(
          status: 'requested',
          at: DateTime.now().subtract(const Duration(hours: 5)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      quote: quote != null ? BookingQuote(amount: quote) : null,
    );

    // One inbound request for the vendor inbox + one outbound for "My
    // bookings", so both sides of the workflow screen have content.
    _bookings.addAll([
      booking(
        'bk-in-1',
        _listings.firstWhere((l) => l.listingId == 'my-svc-1'),
        'requested',
        'cust_amina',
        'Amina R.',
      ),
      booking(
        'bk-out-1',
        _listings.firstWhere((l) => l.listingId == 'svc-102'),
        'quoted',
        _uid,
        _name,
        quote: 3500,
      ),
    ]);
  }

  // ── Vendor listing management ─────────────────────────────────────────

  @override
  Future<MarketplaceListing> createListing({
    required Map<String, dynamic> body,
    required RequestContext context,
  }) async {
    _seed();
    final listing = MarketplaceListing(
      listingId: 'demo-listing-${++_counter}',
      vendorId: _uid,
      vendorName: _name,
      type: body['type'] as String? ?? 'service',
      categoryId: body['categoryId'] as String? ?? '',
      subcategoryId: body['subcategoryId'] as String? ?? '',
      title: body['title'] as String? ?? 'Untitled demo listing',
      description: body['description'] as String? ?? '',
      price: (body['price'] as num?)?.toInt() ?? 0,
      priceUnit: body['priceUnit'] as String? ?? 'Per visit',
      location: body['location'] as String? ?? '',
      details:
          (body['details'] as Map<String, dynamic>?) ??
          Map<String, dynamic>.from(body)..removeWhere(
            (k, _) => const {
              'type',
              'categoryId',
              'subcategoryId',
              'title',
              'description',
              'price',
              'priceUnit',
              'location',
              'photos',
              'contactNumber',
              'status',
            }.contains(k),
          ),
      photos:
          (body['photos'] as List<dynamic>?)?.cast<String>() ?? const [],
      contactNumber: body['contactNumber'] as String? ?? '',
      status: body['status'] as String? ?? 'published',
      createdAt: DateTime.now(),
      publishedAt: DateTime.now(),
    );
    _listings.insert(0, listing);
    return listing;
  }

  @override
  Future<List<MarketplaceListing>> myListings({
    required String type,
    required RequestContext context,
  }) async {
    _seed();
    return _listings
        .where((l) => l.vendorId == _uid && l.type == type)
        .toList();
  }

  @override
  Future<MarketplaceListing> updateListing({
    required String listingId,
    required Map<String, dynamic> patch,
    required RequestContext context,
  }) async {
    _seed();
    final i = _listings.indexWhere((l) => l.listingId == listingId);
    if (i < 0) throw const AppFailure.notFound();
    final l = _listings[i];
    final updated = MarketplaceListing(
      listingId: l.listingId,
      vendorId: l.vendorId,
      vendorName: l.vendorName,
      type: l.type,
      categoryId: patch['categoryId'] as String? ?? l.categoryId,
      subcategoryId: patch['subcategoryId'] as String? ?? l.subcategoryId,
      title: patch['title'] as String? ?? l.title,
      description: patch['description'] as String? ?? l.description,
      price: (patch['price'] as num?)?.toInt() ?? l.price,
      priceUnit: patch['priceUnit'] as String? ?? l.priceUnit,
      location: patch['location'] as String? ?? l.location,
      details:
          (patch['details'] as Map<String, dynamic>?) ?? l.details,
      photos:
          (patch['photos'] as List<dynamic>?)?.cast<String>() ?? l.photos,
      contactNumber: patch['contactNumber'] as String? ?? l.contactNumber,
      status: patch['status'] as String? ?? l.status,
      createdAt: l.createdAt,
      publishedAt: l.publishedAt,
    );
    _listings[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteListing({
    required String listingId,
    required RequestContext context,
  }) async {
    _seed();
    _listings.removeWhere((l) => l.listingId == listingId);
  }

  // ── Customer discovery ────────────────────────────────────────────────

  @override
  Future<List<MarketplaceListing>> publishedListings({
    required String type,
    String? categoryId,
    String? subcategoryId,
    String? q,
    required RequestContext context,
  }) async {
    _seed();
    final query = q?.toLowerCase();
    return _listings.where((l) {
      if (!l.isPublished || l.type != type) return false;
      if (categoryId != null && l.categoryId != categoryId) return false;
      if (subcategoryId != null && l.subcategoryId != subcategoryId) {
        return false;
      }
      if (query != null &&
          query.isNotEmpty &&
          !l.title.toLowerCase().contains(query) &&
          !l.description.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<MarketplaceListing> getPublishedListing({
    required String listingId,
    required RequestContext context,
  }) async {
    _seed();
    return _listings.firstWhere(
      (l) => l.listingId == listingId && l.isPublished,
      orElse: () => throw const AppFailure.notFound(),
    );
  }

  // ── Booking workflow ──────────────────────────────────────────────────

  @override
  Future<MarketplaceBooking> createBooking({
    required String listingId,
    required Map<String, dynamic> request,
    required RequestContext context,
  }) async {
    _seed();
    final l = _listings.firstWhere(
      (x) => x.listingId == listingId,
      orElse: () => throw const AppFailure.notFound(),
    );
    final booking = MarketplaceBooking(
      bookingId: 'demo-booking-${++_counter}',
      listingId: l.listingId,
      listingTitle: l.title,
      type: l.type,
      vendorId: l.vendorId,
      customerId: _uid,
      customerName: _name,
      status: 'requested',
      request: request,
      statusHistory: [
        BookingStatusEvent(status: 'requested', at: DateTime.now()),
      ],
      createdAt: DateTime.now(),
    );
    _bookings.insert(0, booking);
    return booking;
  }

  @override
  Future<List<MarketplaceBooking>> bookings({
    required String role,
    String? type,
    required RequestContext context,
  }) async {
    _seed();
    return _bookings.where((b) {
      final mine = role == 'vendor' ? b.vendorId == _uid : b.customerId == _uid;
      return mine && (type == null || b.type == type);
    }).toList();
  }

  @override
  Future<MarketplaceBooking> getBooking({
    required String bookingId,
    required RequestContext context,
  }) async {
    _seed();
    return _bookings.firstWhere(
      (b) => b.bookingId == bookingId,
      orElse: () => throw const AppFailure.notFound(),
    );
  }

  MarketplaceBooking _transition(
    String bookingId,
    String status, {
    int? quote,
    String? note,
  }) {
    final i = _bookings.indexWhere((b) => b.bookingId == bookingId);
    if (i < 0) throw const AppFailure.notFound();
    final b = _bookings[i];
    final updated = MarketplaceBooking(
      bookingId: b.bookingId,
      listingId: b.listingId,
      listingTitle: b.listingTitle,
      type: b.type,
      vendorId: b.vendorId,
      customerId: b.customerId,
      customerName: b.customerName,
      status: status,
      request: b.request,
      statusHistory: [
        ...b.statusHistory,
        BookingStatusEvent(status: status, at: DateTime.now()),
      ],
      createdAt: b.createdAt,
      quote: quote != null ? BookingQuote(amount: quote, note: note) : b.quote,
    );
    _bookings[i] = updated;
    return updated;
  }

  /// quote | accept | reject | cancel | start | complete
  @override
  Future<MarketplaceBooking> vendorAction({
    required String bookingId,
    required String action,
    int? amount,
    String? note,
    required RequestContext context,
  }) async {
    _seed();
    final status = switch (action) {
      'quote' => 'quoted',
      'accept' => 'accepted',
      'reject' => 'rejected',
      'cancel' => 'cancelled',
      'start' => 'in_progress',
      'complete' => 'completed',
      _ => throw AppFailure.validation(message: 'Unknown demo action: $action'),
    };
    return _transition(
      bookingId,
      status,
      quote: action == 'quote' ? amount : null,
      note: note,
    );
  }

  /// accept (a quote) | cancel
  @override
  Future<MarketplaceBooking> customerAction({
    required String bookingId,
    required String action,
    String? note,
    required RequestContext context,
  }) async {
    _seed();
    final status = switch (action) {
      'accept' => 'accepted',
      'cancel' => 'cancelled',
      _ => throw AppFailure.validation(message: 'Unknown demo action: $action'),
    };
    return _transition(bookingId, status);
  }
}
