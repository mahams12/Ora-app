import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../data/availability/driver_availability_remote_data_source.dart';
import '../../domain/location/driver_presence_publisher.dart';

class DriverAvailabilityUiState {
  const DriverAvailabilityUiState({
    this.availabilityState = 'offline',
    this.busy = false,
    this.loaded = false,
    this.errorMessage,
  });

  /// 'online' | 'offline' — last value confirmed by the server.
  final String availabilityState;

  /// A go-online/go-offline call is in flight.
  final bool busy;

  /// The first GET /drivers/availability completed (success or failure).
  final bool loaded;

  final String? errorMessage;

  bool get isOnline => availabilityState == 'online';

  DriverAvailabilityUiState copyWith({
    String? availabilityState,
    bool? busy,
    bool? loaded,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DriverAvailabilityUiState(
      availabilityState: availabilityState ?? this.availabilityState,
      busy: busy ?? this.busy,
      loaded: loaded ?? this.loaded,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Driver availability (N1) — server is authoritative. The toggle issues the
/// real go-online/go-offline mutation and adopts the returned snapshot; the
/// GET restores persisted state on app start (drivers are otherwise offline
/// by default — never assume online).
class DriverAvailabilityController
    extends Notifier<DriverAvailabilityUiState> {
  late final DriverAvailabilityRemoteDataSource _remote;
  late final FailureMapper _failures;

  @override
  DriverAvailabilityUiState build() {
    _remote = ref.read(driverAvailabilityRemoteDataSourceProvider);
    _failures = ref.read(failureMapperProvider);
    Future.microtask(refresh);
    return const DriverAvailabilityUiState();
  }

  Future<void> refresh() async {
    try {
      final snap = await _remote.getAvailability();
      state = state.copyWith(
        availabilityState: snap.availabilityState,
        loaded: true,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        loaded: true,
        errorMessage: _failures.fromException(error).userMessage,
      );
    }
  }

  Future<void> toggle() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final snap = state.isOnline
          ? await _remote.goOffline()
          : await _remote.goOnline();
      state = state.copyWith(
        availabilityState: snap.availabilityState,
        busy: false,
        loaded: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        errorMessage: _failures.fromException(error).userMessage,
      );
    }
  }
}

final driverAvailabilityProvider =
    NotifierProvider<DriverAvailabilityController, DriverAvailabilityUiState>(
  DriverAvailabilityController.new,
);

/// Shell-scoped idle presence owner (N2C). Starts a [DriverPresencePublisher]
/// while the driver is online, signed in, and foregrounded — the publisher
/// writes idle-mode location updates so the driver stays in the geo index
/// and N3/N4 matching between trips.
///
/// Lifecycle comes from DriverShellView's WidgetsBindingObserver; sign-out
/// stops it via [onSignedOut].
class DriverPresenceController extends Notifier<bool> {
  late final DriverPresencePublisher _publisher;

  @override
  bool build() {
    _publisher = DriverPresencePublisher(
      remote: ref.read(driverLocationRemoteDataSourceProvider),
      source: ref.read(driverLocationSourceProvider),
      logger: ref.read(appLoggerProvider),
    );
    ref.onDispose(_publisher.dispose);
    ref.listen<bool>(
      driverAvailabilityProvider.select((s) => s.isOnline),
      (prev, next) => _publisher.onAvailability(online: next),
    );
    return false;
  }

  void onAppLifecycle(bool resumed) {
    if (resumed) {
      _publisher.onForeground();
    } else {
      _publisher.onBackground();
    }
  }

  void onSignedOut() => _publisher.onSignedOut();
}

final driverPresenceProvider =
    NotifierProvider<DriverPresenceController, bool>(
  DriverPresenceController.new,
);
