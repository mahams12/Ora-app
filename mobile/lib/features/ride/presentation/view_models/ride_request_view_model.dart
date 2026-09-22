import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/ride.dart';
import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/models/ride_category_option.dart';
import '../../domain/ports/device_location_port.dart';
import '../../domain/ports/place_search_port.dart';
import '../../domain/use_cases/ride_use_cases.dart';

/// Pricing fields remain externally injected (Phase 5). Coordinates come from
/// passenger-confirmed locations in [RideRequestUiState] (Phase 4A).
class RideRequestCapabilities {
  const RideRequestCapabilities({
    this.pricingSnapshotId,
    this.passengerOfferMinor,
    this.resolvedPickup,
    this.resolvedDestination,
  });

  final String? pricingSnapshotId;
  final int? passengerOfferMinor;
  final LatLngPoint? resolvedPickup;
  final LatLngPoint? resolvedDestination;

  bool get hasPricing =>
      pricingSnapshotId != null &&
      pricingSnapshotId!.isNotEmpty &&
      passengerOfferMinor != null &&
      passengerOfferMinor! > 0;

  bool get hasResolvedLocations =>
      resolvedPickup != null && resolvedDestination != null;

  bool get canCreateRide => hasPricing && hasResolvedLocations;

  RideRequestCapabilities withResolvedLocations({
    LatLngPoint? pickup,
    LatLngPoint? destination,
  }) {
    return RideRequestCapabilities(
      pricingSnapshotId: pricingSnapshotId,
      passengerOfferMinor: passengerOfferMinor,
      resolvedPickup: pickup,
      resolvedDestination: destination,
    );
  }
}

/// Pricing-only defaults for production. Empty until Phase 5.
final rideRequestCapabilitiesProvider = Provider<RideRequestCapabilities>(
  (ref) => const RideRequestCapabilities(),
);

enum RideRequestPhase {
  compose,
  review,
  submitting,
  created,
  error,
  blocked,
}

enum RideRequestBlockReason {
  incomplete,
  pricingUnavailable,
  locationUnavailable,
}

enum LocationField { pickup, destination }

class RideRequestUiState {
  const RideRequestUiState({
    this.phase = RideRequestPhase.compose,
    this.pickupText = '',
    this.destinationText = '',
    this.categoryId = 'easy',
    this.paymentMethod = 'CASH',
    this.blockReason,
    this.errorMessage,
    this.createdRide,
    this.pickupSuggestions = const [],
    this.destinationSuggestions = const [],
    this.proposedPickup,
    this.proposedDestination,
    this.confirmedPickup,
    this.confirmedDestination,
    this.pickupBusy = false,
    this.destinationBusy = false,
    this.pickupLookupError,
    this.destinationLookupError,
  });

  final RideRequestPhase phase;
  final String pickupText;
  final String destinationText;
  final String categoryId;
  final String paymentMethod;
  final RideRequestBlockReason? blockReason;
  final String? errorMessage;
  final Ride? createdRide;

  final List<PlaceSuggestion> pickupSuggestions;
  final List<PlaceSuggestion> destinationSuggestions;
  final ResolvedPassengerLocation? proposedPickup;
  final ResolvedPassengerLocation? proposedDestination;
  final ResolvedPassengerLocation? confirmedPickup;
  final ResolvedPassengerLocation? confirmedDestination;
  final bool pickupBusy;
  final bool destinationBusy;
  final String? pickupLookupError;
  final String? destinationLookupError;

  bool get hasPickupText => pickupText.trim().isNotEmpty;
  bool get hasDestinationText => destinationText.trim().isNotEmpty;

  bool get hasConfirmedPickup => confirmedPickup != null;
  bool get hasConfirmedDestination => confirmedDestination != null;

  /// Review requires passenger-confirmed coordinates (not free text alone).
  bool get canAdvanceToReview =>
      hasConfirmedPickup && hasConfirmedDestination;

  RideCategoryOption get selectedCategory =>
      rideCategoryById(categoryId) ?? kRideCategoryOptions[2];

  RideRequestUiState copyWith({
    RideRequestPhase? phase,
    String? pickupText,
    String? destinationText,
    String? categoryId,
    String? paymentMethod,
    RideRequestBlockReason? blockReason,
    String? errorMessage,
    Ride? createdRide,
    List<PlaceSuggestion>? pickupSuggestions,
    List<PlaceSuggestion>? destinationSuggestions,
    ResolvedPassengerLocation? proposedPickup,
    ResolvedPassengerLocation? proposedDestination,
    ResolvedPassengerLocation? confirmedPickup,
    ResolvedPassengerLocation? confirmedDestination,
    bool? pickupBusy,
    bool? destinationBusy,
    String? pickupLookupError,
    String? destinationLookupError,
    bool clearBlock = false,
    bool clearError = false,
    bool clearCreated = false,
    bool clearProposedPickup = false,
    bool clearProposedDestination = false,
    bool clearConfirmedPickup = false,
    bool clearConfirmedDestination = false,
    bool clearPickupSuggestions = false,
    bool clearDestinationSuggestions = false,
    bool clearPickupLookupError = false,
    bool clearDestinationLookupError = false,
  }) {
    return RideRequestUiState(
      phase: phase ?? this.phase,
      pickupText: pickupText ?? this.pickupText,
      destinationText: destinationText ?? this.destinationText,
      categoryId: categoryId ?? this.categoryId,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      blockReason: clearBlock ? null : (blockReason ?? this.blockReason),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      createdRide: clearCreated ? null : (createdRide ?? this.createdRide),
      pickupSuggestions: clearPickupSuggestions
          ? const []
          : (pickupSuggestions ?? this.pickupSuggestions),
      destinationSuggestions: clearDestinationSuggestions
          ? const []
          : (destinationSuggestions ?? this.destinationSuggestions),
      proposedPickup: clearProposedPickup
          ? null
          : (proposedPickup ?? this.proposedPickup),
      proposedDestination: clearProposedDestination
          ? null
          : (proposedDestination ?? this.proposedDestination),
      confirmedPickup: clearConfirmedPickup
          ? null
          : (confirmedPickup ?? this.confirmedPickup),
      confirmedDestination: clearConfirmedDestination
          ? null
          : (confirmedDestination ?? this.confirmedDestination),
      pickupBusy: pickupBusy ?? this.pickupBusy,
      destinationBusy: destinationBusy ?? this.destinationBusy,
      pickupLookupError: clearPickupLookupError
          ? null
          : (pickupLookupError ?? this.pickupLookupError),
      destinationLookupError: clearDestinationLookupError
          ? null
          : (destinationLookupError ?? this.destinationLookupError),
    );
  }
}

/// Compose → confirm coords → review → create (when capabilities allow).
/// Never invents pricing or coordinates.
class RideRequestViewModel extends AutoDisposeNotifier<RideRequestUiState> {
  late final CreateRideUseCase _createRide;
  late final FailureMapper _failures;
  late final RideRequestCapabilities _pricingCapabilities;
  late final DeviceLocationPort _deviceLocation;
  late final PlaceSearchPort _placeSearch;

  String? _createOperationKey;
  String _pickupSessionToken = const Uuid().v4();
  String _destinationSessionToken = const Uuid().v4();
  int _pickupSearchGen = 0;
  int _destinationSearchGen = 0;
  int _pickupResolveGen = 0;
  int _destinationResolveGen = 0;
  Timer? _pickupDebounce;
  Timer? _destinationDebounce;

  static const _debounce = Duration(milliseconds: 350);

  @override
  RideRequestUiState build() {
    _createRide = ref.read(createRideUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _pricingCapabilities = ref.read(rideRequestCapabilitiesProvider);
    _deviceLocation = ref.read(deviceLocationPortProvider);
    _placeSearch = ref.read(placeSearchPortProvider);
    ref.onDispose(() {
      _pickupDebounce?.cancel();
      _destinationDebounce?.cancel();
    });
    return const RideRequestUiState();
  }

  /// Effective create capabilities: pricing from provider + confirmed coords.
  RideRequestCapabilities get capabilities =>
      _pricingCapabilities.withResolvedLocations(
        pickup: state.confirmedPickup?.toLatLngPoint(),
        destination: state.confirmedDestination?.toLatLngPoint(),
      );

  void seedCategory(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return;
    if (rideCategoryById(categoryId) == null) return;
    state = state.copyWith(categoryId: categoryId);
  }

  void setPickupText(String value) {
    _pickupDebounce?.cancel();
    _pickupSearchGen++;
    _pickupResolveGen++;
    state = state.copyWith(
      pickupText: value,
      clearBlock: true,
      clearError: true,
      clearProposedPickup: true,
      clearConfirmedPickup: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      pickupBusy: false,
    );
    final trimmed = value.trim();
    if (trimmed.length < 2) return;
    final gen = _pickupSearchGen;
    _pickupDebounce = Timer(_debounce, () {
      unawaited(_runAutocomplete(LocationField.pickup, trimmed, gen));
    });
  }

  void setDestinationText(String value) {
    _destinationDebounce?.cancel();
    _destinationSearchGen++;
    _destinationResolveGen++;
    state = state.copyWith(
      destinationText: value,
      clearBlock: true,
      clearError: true,
      clearProposedDestination: true,
      clearConfirmedDestination: true,
      clearDestinationSuggestions: true,
      clearDestinationLookupError: true,
      destinationBusy: false,
    );
    final trimmed = value.trim();
    if (trimmed.length < 2) return;
    final gen = _destinationSearchGen;
    _destinationDebounce = Timer(_debounce, () {
      unawaited(_runAutocomplete(LocationField.destination, trimmed, gen));
    });
  }

  Future<void> _runAutocomplete(
    LocationField field,
    String query,
    int generation,
  ) async {
    final isPickup = field == LocationField.pickup;
    if (isPickup) {
      state = state.copyWith(
        pickupBusy: true,
        clearPickupLookupError: true,
      );
    } else {
      state = state.copyWith(
        destinationBusy: true,
        clearDestinationLookupError: true,
      );
    }

    try {
      final suggestions = await _placeSearch.autocomplete(
        query: query,
        sessionToken:
            isPickup ? _pickupSessionToken : _destinationSessionToken,
      );
      if (!_isSearchCurrent(field, generation)) return;
      if (isPickup) {
        state = state.copyWith(
          pickupSuggestions: suggestions,
          pickupBusy: false,
          clearPickupLookupError: true,
        );
      } else {
        state = state.copyWith(
          destinationSuggestions: suggestions,
          destinationBusy: false,
          clearDestinationLookupError: true,
        );
      }
    } catch (error) {
      if (!_isSearchCurrent(field, generation)) return;
      final message = _mapLookupError(error);
      if (isPickup) {
        state = state.copyWith(
          pickupBusy: false,
          pickupSuggestions: const [],
          pickupLookupError: message,
        );
      } else {
        state = state.copyWith(
          destinationBusy: false,
          destinationSuggestions: const [],
          destinationLookupError: message,
        );
      }
    }
  }

  bool _isSearchCurrent(LocationField field, int generation) {
    return field == LocationField.pickup
        ? generation == _pickupSearchGen
        : generation == _destinationSearchGen;
  }

  bool _isResolveCurrent(LocationField field, int generation) {
    return field == LocationField.pickup
        ? generation == _pickupResolveGen
        : generation == _destinationResolveGen;
  }

  Future<void> selectPlaceSuggestion({
    required LocationField field,
    required PlaceSuggestion suggestion,
  }) async {
    final isPickup = field == LocationField.pickup;
    final generation =
        isPickup ? ++_pickupResolveGen : ++_destinationResolveGen;
    // Selecting a suggestion supersedes in-flight autocomplete.
    if (isPickup) {
      _pickupDebounce?.cancel();
      _pickupSearchGen++;
      state = state.copyWith(
        pickupText: suggestion.displayText,
        pickupBusy: true,
        clearPickupSuggestions: true,
        clearProposedPickup: true,
        clearConfirmedPickup: true,
        clearPickupLookupError: true,
        clearBlock: true,
        clearError: true,
      );
    } else {
      _destinationDebounce?.cancel();
      _destinationSearchGen++;
      state = state.copyWith(
        destinationText: suggestion.displayText,
        destinationBusy: true,
        clearDestinationSuggestions: true,
        clearProposedDestination: true,
        clearConfirmedDestination: true,
        clearDestinationLookupError: true,
        clearBlock: true,
        clearError: true,
      );
    }

    try {
      final resolved = await _placeSearch.resolvePlace(
        placeId: suggestion.placeId,
        sessionToken:
            isPickup ? _pickupSessionToken : _destinationSessionToken,
      );
      if (!_isResolveCurrent(field, generation)) return;

      // New session after a successful details call (Places billing practice).
      if (isPickup) {
        _pickupSessionToken = const Uuid().v4();
        state = state.copyWith(
          proposedPickup: resolved,
          pickupText: resolved.displayLabel,
          pickupBusy: false,
          clearPickupSuggestions: true,
          clearPickupLookupError: true,
        );
      } else {
        _destinationSessionToken = const Uuid().v4();
        state = state.copyWith(
          proposedDestination: resolved,
          destinationText: resolved.displayLabel,
          destinationBusy: false,
          clearDestinationSuggestions: true,
          clearDestinationLookupError: true,
        );
      }
    } catch (error) {
      if (!_isResolveCurrent(field, generation)) return;
      final message = _mapLookupError(error);
      if (isPickup) {
        state = state.copyWith(
          pickupBusy: false,
          pickupLookupError: message,
          clearProposedPickup: true,
        );
      } else {
        state = state.copyWith(
          destinationBusy: false,
          destinationLookupError: message,
          clearProposedDestination: true,
        );
      }
    }
  }

  Future<void> useCurrentLocationForPickup() async {
    final generation = ++_pickupResolveGen;
    _pickupDebounce?.cancel();
    _pickupSearchGen++;
    state = state.copyWith(
      pickupBusy: true,
      clearPickupSuggestions: true,
      clearProposedPickup: true,
      clearConfirmedPickup: true,
      clearPickupLookupError: true,
      clearBlock: true,
      clearError: true,
    );

    try {
      final resolved = await _deviceLocation.getCurrentLocation();
      if (!_isResolveCurrent(LocationField.pickup, generation)) return;
      state = state.copyWith(
        proposedPickup: resolved,
        pickupText: resolved.displayLabel,
        pickupBusy: false,
        clearPickupSuggestions: true,
        clearPickupLookupError: true,
      );
    } catch (error) {
      if (!_isResolveCurrent(LocationField.pickup, generation)) return;
      state = state.copyWith(
        pickupBusy: false,
        pickupLookupError: _mapLookupError(error),
        clearProposedPickup: true,
      );
    }
  }

  void confirmPickup() {
    final proposed = state.proposedPickup;
    if (proposed == null || !proposed.hasValidCoordinates) return;
    state = state.copyWith(
      confirmedPickup: proposed,
      pickupText: proposed.displayLabel,
      clearProposedPickup: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      clearBlock: true,
      clearError: true,
    );
  }

  void confirmDestination() {
    final proposed = state.proposedDestination;
    if (proposed == null || !proposed.hasValidCoordinates) return;
    state = state.copyWith(
      confirmedDestination: proposed,
      destinationText: proposed.displayLabel,
      clearProposedDestination: true,
      clearDestinationSuggestions: true,
      clearDestinationLookupError: true,
      clearBlock: true,
      clearError: true,
    );
  }

  void selectCategory(String categoryId) {
    if (rideCategoryById(categoryId) == null) return;
    state = state.copyWith(
      categoryId: categoryId,
      clearBlock: true,
      clearError: true,
    );
  }

  void goToCompose() {
    if (state.phase == RideRequestPhase.submitting) return;
    state = state.copyWith(
      phase: RideRequestPhase.compose,
      clearBlock: true,
      clearError: true,
    );
  }

  void goToReview() {
    if (!state.canAdvanceToReview) {
      state = state.copyWith(
        phase: RideRequestPhase.blocked,
        blockReason: RideRequestBlockReason.incomplete,
      );
      return;
    }
    state = state.copyWith(
      phase: RideRequestPhase.review,
      clearBlock: true,
      clearError: true,
    );
  }

  bool get canSubmitRideRequest =>
      state.canAdvanceToReview && capabilities.canCreateRide;

  RideRequestBlockReason? get submitBlockReason {
    if (!state.canAdvanceToReview) {
      return RideRequestBlockReason.incomplete;
    }
    final caps = capabilities;
    if (!caps.hasPricing) {
      return RideRequestBlockReason.pricingUnavailable;
    }
    if (!caps.hasResolvedLocations) {
      return RideRequestBlockReason.locationUnavailable;
    }
    return null;
  }

  String messageFor(RideRequestBlockReason reason) {
    return switch (reason) {
      RideRequestBlockReason.incomplete =>
        'Confirm both a pickup and a destination to continue.',
      RideRequestBlockReason.pricingUnavailable =>
        'Pricing isn\'t available right now. Please try again later.',
      RideRequestBlockReason.locationUnavailable =>
        'Location isn\'t available yet. Ora will not invent pickup or '
            'destination coordinates.',
    };
  }

  String _mapLookupError(Object error) {
    if (error is DeviceLocationException) {
      return switch (error.kind) {
        DeviceLocationFailureKind.permissionDenied =>
          'Location permission is required to use current location.',
        DeviceLocationFailureKind.permissionDeniedForever =>
          'Location permission is permanently denied. Enable it in Settings.',
        DeviceLocationFailureKind.serviceDisabled =>
          'Turn on location services, then try again.',
        DeviceLocationFailureKind.timeout =>
          'Timed out waiting for GPS. Try again or search for a place.',
        DeviceLocationFailureKind.unavailable =>
          'We couldn\'t use that location. Pick another point.',
      };
    }
    if (error is PlaceSearchException) {
      return switch (error.kind) {
        PlaceSearchFailureKind.notConfigured =>
          'Location lookup isn\'t available right now. Try again.',
        PlaceSearchFailureKind.network ||
        PlaceSearchFailureKind.unavailable =>
          'Location lookup isn\'t available right now. Try again.',
        PlaceSearchFailureKind.empty =>
          'No places found. Try a different search.',
        PlaceSearchFailureKind.invalid =>
          'We couldn\'t use that location. Pick another point.',
      };
    }
    return 'Location lookup isn\'t available right now. Try again.';
  }

  /// Attempts create only when pricing + confirmed coordinates exist.
  Future<void> submit() async {
    if (state.phase == RideRequestPhase.submitting) return;

    final block = submitBlockReason;
    if (block != null) {
      state = state.copyWith(
        phase: RideRequestPhase.blocked,
        blockReason: block,
        clearError: true,
      );
      return;
    }

    final caps = capabilities;
    final pickup = caps.resolvedPickup!;
    final destination = caps.resolvedDestination!;
    final snapshotId = caps.pricingSnapshotId!;
    final offerMinor = caps.passengerOfferMinor!;

    _createOperationKey ??= 'ride:create:${const Uuid().v4()}';

    state = state.copyWith(
      phase: RideRequestPhase.submitting,
      clearBlock: true,
      clearError: true,
    );

    try {
      final ride = await _createRide(
        body: <String, Object?>{
          'pickup': <String, Object?>{
            'lat': pickup.lat,
            'lng': pickup.lng,
            if (pickup.address != null) 'address': pickup.address,
          },
          'destination': <String, Object?>{
            'lat': destination.lat,
            'lng': destination.lng,
            if (destination.address != null) 'address': destination.address,
          },
          'category': state.categoryId,
          'serviceType': 'ride',
          'passengerOfferMinor': offerMinor,
          'pricingSnapshotId': snapshotId,
          'paymentMethod': state.paymentMethod,
          'passengerCount': 1,
        },
        operationKey: _createOperationKey!,
      );
      state = state.copyWith(
        phase: RideRequestPhase.created,
        createdRide: ride,
        clearError: true,
        clearBlock: true,
      );
    } catch (error, stack) {
      final failure = _failures.fromException(error, stack);
      state = state.copyWith(
        phase: RideRequestPhase.error,
        errorMessage: failure.userMessage,
      );
    }
  }

  void clearBlocked() {
    state = state.copyWith(
      phase: state.canAdvanceToReview
          ? RideRequestPhase.review
          : RideRequestPhase.compose,
      clearBlock: true,
    );
  }

  void retryAfterError() {
    state = state.copyWith(
      phase: RideRequestPhase.review,
      clearError: true,
    );
  }
}

final rideRequestViewModelProvider =
    NotifierProvider.autoDispose<RideRequestViewModel, RideRequestUiState>(
  RideRequestViewModel.new,
);
