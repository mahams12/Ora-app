import '../entities/passenger_places.dart';

/// Local persistence port for passenger saved places + recent destinations.
///
/// All reads/writes are scoped to an authenticated [uid] — implementers must
/// never share one account's data with another.
abstract interface class PassengerPlacesStore {
  Future<List<SavedPlace>> loadSavedPlaces({required String uid});

  Future<void> writeSavedPlaces({
    required String uid,
    required List<SavedPlace> places,
  });

  Future<List<RecentDestination>> loadRecentDestinations({required String uid});

  Future<void> writeRecentDestinations({
    required String uid,
    required List<RecentDestination> recents,
  });
}
