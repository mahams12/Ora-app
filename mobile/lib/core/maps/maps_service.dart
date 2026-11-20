/// Maps services — Phase 4.
abstract interface class MapsService {
  Future<void> initialize();
}

class PlaceholderMapsService implements MapsService {
  const PlaceholderMapsService();

  @override
  Future<void> initialize() async {}
}
