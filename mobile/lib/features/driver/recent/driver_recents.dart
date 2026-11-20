import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Driver "Frequently used" destinations — mirrors the passenger
/// `RecentActivitySection` but tracks which driver areas were opened.
enum DriverRecentDestination {
  requests,
  bookings,
  earnings,
  wallet,
  profile,
  activeRide,
}

final driverRecentsProvider =
    NotifierProvider<DriverRecentsNotifier, List<DriverRecentDestination>>(
      DriverRecentsNotifier.new,
    );

/// In-memory MRU list seeded with the main sections so the home strip is
/// never empty on first launch; real usage reorders it like the passenger
/// side (most recent first, max 4 shown).
class DriverRecentsNotifier extends Notifier<List<DriverRecentDestination>> {
  @override
  List<DriverRecentDestination> build() => const [
    DriverRecentDestination.requests,
    DriverRecentDestination.bookings,
    DriverRecentDestination.earnings,
  ];

  void record(DriverRecentDestination destination) {
    state = List.unmodifiable(
      [destination, ...state.where((item) => item != destination)].take(4),
    );
  }
}
