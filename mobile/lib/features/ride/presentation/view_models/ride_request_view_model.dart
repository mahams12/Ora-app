import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/ride.dart';
import '../../domain/models/passenger_city.dart';
import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/models/ride_category_option.dart';
import '../../domain/ports/device_location_port.dart';
import '../../domain/ports/place_search_port.dart';
import '../../domain/ports/pricing_estimate_port.dart';
import '../../domain/use_cases/ride_use_cases.dart';

/// Pricing fields come from POST /v1/pricing/estimate (Phase 5C).
/// Coordinates come from passenger-confirmed locations (Phase 4A).
/// Tests may inject capabilities via [rideRequestCapabilitiesProvider].
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

/// Empty until a live estimate succeeds (or a test override injects pricing).
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
    this.citySlug,
    this.pricingStatus = PricingStatus.idle,
    this.pricingEstimate,
    this.pricingFailureKind,
    this.pricingFailureMessage,
    this.passengerOfferMinor,
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

  final String? citySlug;
  final PricingStatus pricingStatus;
  final PricingEstimate? pricingEstimate;
  final PricingFailureKind? pricingFailureKind;
  final String? pricingFailureMessage;
  final int? passengerOfferMinor;

  bool get hasPickupText => pickupText.trim().isNotEmpty;
  bool get hasDestinationText => destinationText.trim().isNotEmpty;

  bool get hasConfirmedPickup => confirmedPickup != null;
  bool get hasConfirmedDestination => confirmedDestination != null;

  /// Review requires passenger-confirmed coordinates (not free text alone).
  bool get canAdvanceToReview =>
      hasConfirmedPickup && hasConfirmedDestination;

  bool get hasUsablePricing {
    final estimate = pricingEstimate;
    if (pricingStatus != PricingStatus.success || estimate == null) {
      return false;
    }
    if (estimate.pricingSnapshotId.trim().isEmpty) return false;
    return !estimate.isExpiredAt(DateTime.now().toUtc());
  }

  String? get pricingDisplayError {
    if (pricingStatus == PricingStatus.success ||
        pricingStatus == PricingStatus.idle ||
        pricingStatus == PricingStatus.loading) {
      return null;
    }
    return pricingFailureMessage ??
        'Pricing isn\'t available right now. Please try again later.';
  }

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
    String? citySlug,
    PricingStatus? pricingStatus,
    PricingEstimate? pricingEstimate,
    PricingFailureKind? pricingFailureKind,
    String? pricingFailureMessage,
    int? passengerOfferMinor,
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
    bool clearCitySlug = false,
    bool clearPricing = false,
    bool clearPassengerOffer = false,
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
      citySlug: clearCitySlug ? null : (citySlug ?? this.citySlug),
      pricingStatus: clearPricing
          ? PricingStatus.idle
          : (pricingStatus ?? this.pricingStatus),
      pricingEstimate:
          clearPricing ? null : (pricingEstimate ?? this.pricingEstimate),
      pricingFailureKind: clearPricing
          ? null
          : (pricingFailureKind ?? this.pricingFailureKind),
      pricingFailureMessage: clearPricing
          ? null
          : (pricingFailureMessage ?? this.pricingFailureMessage),
      passengerOfferMinor: clearPassengerOffer
          ? null
          : (passengerOfferMinor ?? this.passengerOfferMinor),
    );
  }
}

/// Compose → confirm coords → estimate → review → create (when capabilities allow).
/// Never invents pricing, distance, or snapshot IDs.
class RideRequestViewModel extends AutoDisposeNotifier<RideRequestUiState> {
  late final CreateRideUseCase _createRide;
  late final FailureMapper _failures;
  late final RideRequestCapabilities _pricingCapabilities;
  late final DeviceLocationPort _deviceLocation;
  late final PlaceSearchPort _placeSearch;
  late final PricingEstimatePort _pricing;

  String? _createOperationKey;
  String _pickupSessionToken = const Uuid().v4();
  String _destinationSessionToken = const Uuid().v4();
  int _pickupSearchGen = 0;
  int _destinationSearchGen = 0;
  int _pickupResolveGen = 0;
  int _destinationResolveGen = 0;
  int _pricingGen = 0;
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
    _pricing = ref.read(pricingEstimatePortProvider);
    ref.onDispose(() {
      _pickupDebounce?.cancel();
      _destinationDebounce?.cancel();
    });
    return const RideRequestUiState();
  }

  bool get _usesInjectedPricing => _pricingCapabilities.hasPricing;

  /// Effective create capabilities: injected test pricing OR live estimate.
  RideRequestCapabilities get capabilities {
    final pickup = state.confirmedPickup?.toLatLngPoint();
    final destination = state.confirmedDestination?.toLatLngPoint();
    if (_usesInjectedPricing) {
      return _pricingCapabilities.withResolvedLocations(
        pickup: pickup,
        destination: destination,
      );
    }
    if (!state.hasUsablePricing) {
      return RideRequestCapabilities(
        resolvedPickup: pickup,
        resolvedDestination: destination,
      );
    }
    final estimate = state.pricingEstimate!;
    return RideRequestCapabilities(
      pricingSnapshotId: estimate.pricingSnapshotId,
      passengerOfferMinor:
          state.passengerOfferMinor ?? estimate.recommendedFareMinor,
      resolvedPickup: pickup,
      resolvedDestination: destination,
    );
  }

  void seedCategory(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return;
    if (rideCategoryById(categoryId) == null) return;
    state = state.copyWith(categoryId: categoryId);
  }

  void setCitySlug(String slug) {
    final normalized = normalizePassengerCitySlug(slug);
    if (normalized == null) return;
    _invalidatePricing();
    state = state.copyWith(
      citySlug: normalized,
      clearBlock: true,
      clearError: true,
    );
    unawaited(requestPricingEstimate());
  }

  void setPickupText(String value) {
    _pickupDebounce?.cancel();
    _pickupSearchGen++;
    _pickupResolveGen++;
    _invalidatePricing();
    state = state.copyWith(
      pickupText: value,
      clearBlock: true,
      clearError: true,
      clearProposedPickup: true,
      clearConfirmedPickup: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      pickupBusy: false,
      clearCitySlug: true,
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
    _invalidatePricing();
    state = state.copyWith(
      destinationText: value,
      clearBlock: true,
      clearError: true,
      clearProposedDestination: true,
      clearConfirmedDestination: true,
      clearDestinationSuggestions: true,
      clearDestinationLookupError: true,
      destinationBusy: false,
      clearCitySlug: true,
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
      _invalidatePricing();
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
      _invalidatePricing();
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
    _invalidatePricing();
    state = state.copyWith(
      pickupBusy: true,
      clearPickupSuggestions: true,
      clearProposedPickup: true,
      clearConfirmedPickup: true,
      clearPickupLookupError: true,
      clearBlock: true,
      clearError: true,
      clearCitySlug: true,
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
    _invalidatePricing();
    state = state.copyWith(
      confirmedPickup: proposed,
      pickupText: proposed.displayLabel,
      clearProposedPickup: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      clearBlock: true,
      clearError: true,
    );
    _refreshCitySuggestion();
    if (state.canAdvanceToReview) {
      unawaited(requestPricingEstimate());
    }
  }

  void confirmDestination() {
    final proposed = state.proposedDestination;
    if (proposed == null || !proposed.hasValidCoordinates) return;
    _invalidatePricing();
    state = state.copyWith(
      confirmedDestination: proposed,
      destinationText: proposed.displayLabel,
      clearProposedDestination: true,
      clearDestinationSuggestions: true,
      clearDestinationLookupError: true,
      clearBlock: true,
      clearError: true,
    );
    _refreshCitySuggestion();
    if (state.canAdvanceToReview) {
      unawaited(requestPricingEstimate());
    }
  }

  void selectCategory(String categoryId) {
    if (rideCategoryById(categoryId) == null) return;
    if (categoryId == state.categoryId) return;
    _invalidatePricing();
    state = state.copyWith(
      categoryId: categoryId,
      clearBlock: true,
      clearError: true,
    );
    unawaited(requestPricingEstimate());
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
    unawaited(requestPricingEstimate());
  }

  void _refreshCitySuggestion() {
    final suggested = suggestCitySlugFromTrip(
      pickupAddress: state.confirmedPickup?.address,
      destinationAddress: state.confirmedDestination?.address,
    );
    if (suggested == null) return;
    if (state.citySlug == suggested) return;
    state = state.copyWith(citySlug: suggested);
  }

  void _invalidatePricing() {
    _pricingGen++;
    state = state.copyWith(
      clearPricing: true,
      clearPassengerOffer: true,
    );
  }

  RideRequestUiState _withPricingSurface({
    required PricingStatus pricingStatus,
    PricingEstimate? pricingEstimate,
    PricingFailureKind? pricingFailureKind,
    String? pricingFailureMessage,
    int? passengerOfferMinor,
  }) {
    return RideRequestUiState(
      phase: state.phase,
      pickupText: state.pickupText,
      destinationText: state.destinationText,
      categoryId: state.categoryId,
      paymentMethod: state.paymentMethod,
      blockReason: state.blockReason,
      errorMessage: state.errorMessage,
      createdRide: state.createdRide,
      pickupSuggestions: state.pickupSuggestions,
      destinationSuggestions: state.destinationSuggestions,
      proposedPickup: state.proposedPickup,
      proposedDestination: state.proposedDestination,
      confirmedPickup: state.confirmedPickup,
      confirmedDestination: state.confirmedDestination,
      pickupBusy: state.pickupBusy,
      destinationBusy: state.destinationBusy,
      pickupLookupError: state.pickupLookupError,
      destinationLookupError: state.destinationLookupError,
      citySlug: state.citySlug,
      pricingStatus: pricingStatus,
      pricingEstimate: pricingEstimate,
      pricingFailureKind: pricingFailureKind,
      pricingFailureMessage: pricingFailureMessage,
      passengerOfferMinor: passengerOfferMinor,
    );
  }

  /// Calls POST /v1/pricing/estimate when both coords + city are ready.
  Future<void> requestPricingEstimate({bool force = false}) async {
    if (_usesInjectedPricing) return;
    if (!state.canAdvanceToReview) return;

    final city = state.citySlug;
    if (city == null || city.isEmpty) {
      state = _withPricingSurface(
        pricingStatus: PricingStatus.pricingUnavailable,
        pricingFailureKind: PricingFailureKind.validation,
        pricingFailureMessage:
            'Select your city so we can load pricing for this trip.',
      );
      return;
    }

    final pickup = state.confirmedPickup!;
    final destination = state.confirmedDestination!;

    if (!force &&
        state.hasUsablePricing &&
        state.pricingEstimate?.category == state.categoryId) {
      return;
    }

    final generation = ++_pricingGen;
    state = _withPricingSurface(pricingStatus: PricingStatus.loading);

    try {
      final estimate = await _pricing.estimate(
        PricingEstimateRequest(
          pickupLat: pickup.lat,
          pickupLng: pickup.lng,
          pickupAddress: pickup.address,
          destinationLat: destination.lat,
          destinationLng: destination.lng,
          destinationAddress: destination.address,
          category: state.categoryId,
          city: city,
        ),
      );
      if (generation != _pricingGen) return;
      state = _withPricingSurface(
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate,
        passengerOfferMinor: estimate.recommendedFareMinor,
      );
    } on PricingClientException catch (error) {
      if (generation != _pricingGen) return;
      final status = switch (error.kind) {
        PricingFailureKind.routeUnavailable => PricingStatus.routeUnavailable,
        PricingFailureKind.pricingUnavailable =>
          PricingStatus.pricingUnavailable,
        PricingFailureKind.network => PricingStatus.error,
        PricingFailureKind.validation => PricingStatus.pricingUnavailable,
        PricingFailureKind.unknown => PricingStatus.error,
      };
      state = _withPricingSurface(
        pricingStatus: status,
        pricingFailureKind: error.kind,
        pricingFailureMessage: error.message ??
            'Pricing isn\'t available right now. Please try again later.',
      );
    } catch (_) {
      if (generation != _pricingGen) return;
      state = _withPricingSurface(
        pricingStatus: PricingStatus.error,
        pricingFailureKind: PricingFailureKind.unknown,
        pricingFailureMessage:
            'Pricing isn\'t available right now. Please try again later.',
      );
    }
  }

  Future<void> retryPricing() => requestPricingEstimate(force: true);

  bool get canSubmitRideRequest {
    if (!state.canAdvanceToReview) return false;
    if (state.citySlug == null || state.citySlug!.isEmpty) return false;
    if (state.pricingStatus == PricingStatus.loading) return false;
    return capabilities.canCreateRide;
  }

  RideRequestBlockReason? get submitBlockReason {
    if (!state.canAdvanceToReview) {
      return RideRequestBlockReason.incomplete;
    }
    if (state.citySlug == null || state.citySlug!.isEmpty) {
      return RideRequestBlockReason.pricingUnavailable;
    }
    if (state.pricingStatus == PricingStatus.loading) {
      return RideRequestBlockReason.pricingUnavailable;
    }
    if (!_usesInjectedPricing && !state.hasUsablePricing) {
      return RideRequestBlockReason.pricingUnavailable;
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
        state.pricingDisplayError ??
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

  /// Attempts create only when pricing + confirmed coordinates + city exist.
  Future<void> submit() async {
    if (state.phase == RideRequestPhase.submitting) return;

    // Re-check expiry at submit time.
    if (!_usesInjectedPricing &&
        state.pricingEstimate != null &&
        state.pricingEstimate!.isExpiredAt(DateTime.now().toUtc())) {
      _invalidatePricing();
      state = state.copyWith(
        phase: RideRequestPhase.blocked,
        blockReason: RideRequestBlockReason.pricingUnavailable,
        pricingStatus: PricingStatus.pricingUnavailable,
        pricingFailureKind: PricingFailureKind.pricingUnavailable,
        pricingFailureMessage:
            'This price expired. Tap retry for a fresh estimate.',
      );
      unawaited(requestPricingEstimate(force: true));
      return;
    }

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
    final city = state.citySlug!;

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
          'city': city,
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
      final message = failure.userMessage;
      final expired = message.toLowerCase().contains('expir') ||
          message.toUpperCase().contains('PRICING_SNAPSHOT_EXPIRED');
      if (expired && !_usesInjectedPricing) {
        _invalidatePricing();
        state = state.copyWith(
          phase: RideRequestPhase.review,
          errorMessage: null,
          pricingStatus: PricingStatus.pricingUnavailable,
          pricingFailureKind: PricingFailureKind.pricingUnavailable,
          pricingFailureMessage:
              'This price expired. Tap retry for a fresh estimate.',
          clearBlock: true,
        );
        unawaited(requestPricingEstimate(force: true));
        return;
      }
      state = state.copyWith(
        phase: RideRequestPhase.error,
        errorMessage: message,
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
