/// Location services — Phase 4.
abstract interface class LocationService {
  Future<bool> isServiceEnabled();
}

class PlaceholderLocationService implements LocationService {
  const PlaceholderLocationService();

  @override
  Future<bool> isServiceEnabled() async => false;
}
