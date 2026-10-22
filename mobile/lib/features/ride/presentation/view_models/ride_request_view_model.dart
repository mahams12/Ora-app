import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../saved_places/domain/entities/passenger_places.dart';
import '../../../saved_places/presentation/view_models/passenger_places_view_model.dart';
import '../../domain/entities/ride.dart';
import '../../domain/models/passenger_city.dart';
import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/models/ride_category_option.dart';
import '../../domain/models/ride_compose_draft.dart';
import '../../domain/ports/device_location_port.dart';
import '../../domain/ports/place_search_port.dart';
import '../../domain/ports/pricing_estimate_port.dart';
import '../../domain/ports/ride_compose_draft_store.dart';
import '../../domain/use_cases/ride_use_cases.dart';
import '../offers/offer_display.dart';

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

/// Service kinds this UI exposes. Backend validates `ride|courier|intercity|move`;
/// courier/move stay "coming later" (different product semantics).
const kRideRequestServiceTypes = <String>{'ride', 'intercity'};

String rideRequestServiceTypeLabel(String serviceType) =>
    serviceType == 'intercity' ? 'Intercity' : 'City ride';

enum LocationField { pickup, destination }

class RideRequestUiState {
  const RideRequestUiState({
    this.phase = RideRequestPhase.compose,
    this.pickupText = '',
    this.destinationText = '',
    this.categoryId = 'easy',
    this.serviceType = 'ride',
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
    this.pickupNameUnresolved = false,
    this.destinationNameUnresolved = false,
    this.pinAdjustTarget,
    this.citySlug,
    this.pricingStatus = PricingStatus.idle,
    this.pricingEstimate,
    this.pricingFailureKind,
    this.pricingFailureMessage,
    this.passengerOfferMinor,
    this.passengerOfferDraftText = '',
    this.passengerOfferError,
  });

  final RideRequestPhase phase;
  final String pickupText;
  final String destinationText;
  final String categoryId;

  /// Backend-supported service kind sent on estimate + create
  /// (`ride` | `intercity`; courier/move stay unexposed in this UI).
  final String serviceType;
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

  /// GPS pickup resolved coordinates but reverse-geocode found no place name —
  /// coordinates remain authoritative; the proposal shows a retry affordance.
  final bool pickupNameUnresolved;

  /// Map-pin destination resolved coordinates but no place name — same honest
  /// retry affordance as pickup (destinations can only be unnamed via map pin).
  final bool destinationNameUnresolved;

  /// MAP-PIN-ADJUST: when set, the next map tap sets this endpoint's proposed
  /// coordinates. Null = normal map interaction. UI-only; never persisted.
  final LocationField? pinAdjustTarget;

  final String? citySlug;
  final PricingStatus pricingStatus;
  final PricingEstimate? pricingEstimate;
  final PricingFailureKind? pricingFailureKind;
  final String? pricingFailureMessage;

  /// Last **valid** passenger offer in paisas (server bounds). Null if draft invalid.
  final int? passengerOfferMinor;

  /// Editable draft (whole PKR rupees text). Synced from estimate; not clamped.
  final String passengerOfferDraftText;

  /// Validation message for the draft; null when draft is valid.
  final String? passengerOfferError;

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

  /// True when draft parses to an in-bound offer for the current snapshot.
  bool get hasValidPassengerOffer {
    if (!hasUsablePricing || pricingEstimate == null) return false;
    if (passengerOfferMinor == null || passengerOfferMinor! <= 0) return false;
    if (passengerOfferError != null) return false;
    final estimate = pricingEstimate!;
    return passengerOfferMinor! >= estimate.offerBoundMinMinor &&
        passengerOfferMinor! <= estimate.offerBoundMaxMinor;
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
    String? serviceType,
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
    bool? pickupNameUnresolved,
    bool? destinationNameUnresolved,
    LocationField? pinAdjustTarget,
    String? citySlug,
    PricingStatus? pricingStatus,
    PricingEstimate? pricingEstimate,
    PricingFailureKind? pricingFailureKind,
    String? pricingFailureMessage,
    int? passengerOfferMinor,
    String? passengerOfferDraftText,
    String? passengerOfferError,
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
    bool clearPickupNameUnresolved = false,
    bool clearDestinationNameUnresolved = false,
    bool clearPinAdjustTarget = false,
    bool clearCitySlug = false,
    bool clearPricing = false,
    bool clearPassengerOffer = false,
    bool clearPassengerOfferError = false,
  }) {
    return RideRequestUiState(
      phase: phase ?? this.phase,
      pickupText: pickupText ?? this.pickupText,
      destinationText: destinationText ?? this.destinationText,
      categoryId: categoryId ?? this.categoryId,
      serviceType: serviceType ?? this.serviceType,
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
      pickupNameUnresolved: clearPickupNameUnresolved
          ? false
          : (pickupNameUnresolved ?? this.pickupNameUnresolved),
      destinationNameUnresolved: clearDestinationNameUnresolved
          ? false
          : (destinationNameUnresolved ?? this.destinationNameUnresolved),
      pinAdjustTarget: clearPinAdjustTarget
          ? null
          : (pinAdjustTarget ?? this.pinAdjustTarget),
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
      passengerOfferDraftText:
          passengerOfferDraftText ?? this.passengerOfferDraftText,
      passengerOfferError: clearPassengerOfferError
          ? null
          : (passengerOfferError ?? this.passengerOfferError),
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
  late final PassengerPlacesViewModel _places;
  late final RideComposeDraftStore _draftStore;

  /// True once the restore attempt finished (draft applied or skipped) —
  /// persists scheduled before this would overwrite an unread draft.
  bool _draftRestoreDone = false;
  Timer? _draftWriteTimer;

  /// Fresh uid read — never cached, so a mid-session account switch can
  /// never write one account's draft under another's key.
  String? get _draftUid => ref.read(sessionUserProfileProvider)?.uid;

  String? _createOperationKey;
  String _pickupSessionToken = const Uuid().v4();
  String _destinationSessionToken = const Uuid().v4();
  int _pickupSearchGen = 0;
  int _destinationSearchGen = 0;
  int _pickupResolveGen = 0;
  int _destinationResolveGen = 0;
  int _pricingGen = 0;

  /// serviceType used for the last successful estimate — the API response does
  /// not echo it, so we track it to keep the stale-estimate guard honest.
  String _estimateServiceType = 'ride';
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
    _places = ref.read(passengerPlacesProvider.notifier);
    _draftStore = ref.read(rideComposeDraftStoreProvider);
    ref.onDispose(() {
      _pickupDebounce?.cancel();
      _destinationDebounce?.cancel();
      _draftWriteTimer?.cancel();
    });
    // COMPOSE-DRAFT: restore an in-progress request after process death /
    // navigation. Fire-and-forget; applies only while compose is pristine.
    unawaited(_restoreComposeDraft());
    return const RideRequestUiState();
  }

  /// Restore a persisted compose draft — only into a pristine compose state
  /// (any passenger input since build wins over the draft; deep-link seeds
  /// applied first also win). Stale/corrupt drafts are discarded, never
  /// partially applied.
  Future<void> _restoreComposeDraft() async {
    final uid = ref.read(sessionUserProfileProvider)?.uid;
    if (uid == null) {
      _draftRestoreDone = true;
      return;
    }
    RideComposeDraft? draft;
    try {
      draft = await _draftStore.loadDraft(uid: uid);
    } catch (_) {
      draft = null;
    }
    if (draft == null) {
      _draftRestoreDone = true;
      return;
    }
    if (draft.isStaleAt(DateTime.now())) {
      _draftRestoreDone = true;
      unawaited(_clearDraft());
      return;
    }
    _draftRestoreDone = true;

    final s = state;
    final pristine = s.phase == RideRequestPhase.compose &&
        s.pickupText.isEmpty &&
        s.destinationText.isEmpty &&
        s.proposedPickup == null &&
        s.proposedDestination == null &&
        s.confirmedPickup == null &&
        s.confirmedDestination == null;
    if (!pristine) return;

    // Nothing in flight may overwrite the restored endpoints.
    _pickupSearchGen++;
    _pickupResolveGen++;
    _destinationSearchGen++;
    _destinationResolveGen++;
    _invalidatePricing();

    final pickup = draft.pickup?.toLocation();
    final destination = draft.destination?.toLocation();
    if (pickup != null && !pickup.hasValidCoordinates) return;
    if (destination != null && !destination.hasValidCoordinates) return;

    // Build on post-invalidation state — never resurrect cleared pricing.
    RideRequestUiState next = state.copyWith(
      pickupText: draft.pickupText.isNotEmpty
          ? draft.pickupText
          : (pickup?.displayLabel ?? ''),
      destinationText: draft.destinationText.isNotEmpty
          ? draft.destinationText
          : (destination?.displayLabel ?? ''),
      passengerOfferDraftText: draft.passengerOfferDraftText,
      clearBlock: true,
      clearError: true,
    );

    // Category/serviceType from the draft only when nothing else set them
    // (a route deep-link seed that already landed wins).
    if (s.categoryId == 'easy' &&
        rideCategoryById(draft.categoryId) != null) {
      next = next.copyWith(categoryId: draft.categoryId);
    }
    if (s.serviceType == 'ride' &&
        kRideRequestServiceTypes.contains(draft.serviceType)) {
      next = next.copyWith(serviceType: draft.serviceType);
    }

    if (pickup != null) {
      final confirmed = draft.pickup!.confirmed;
      final unnamed = pickup.address?.trim().isEmpty ?? true;
      next = next.copyWith(
        proposedPickup: confirmed ? null : pickup,
        confirmedPickup: confirmed ? pickup : null,
        clearProposedPickup: confirmed,
        clearConfirmedPickup: !confirmed,
        pickupNameUnresolved: !confirmed && unnamed,
      );
    }
    if (destination != null) {
      final confirmed = draft.destination!.confirmed;
      final unnamed = destination.address?.trim().isEmpty ?? true;
      next = next.copyWith(
        proposedDestination: confirmed ? null : destination,
        confirmedDestination: confirmed ? destination : null,
        clearProposedDestination: confirmed,
        clearConfirmedDestination: !confirmed,
        destinationNameUnresolved: !confirmed && unnamed,
      );
    }

    state = next;
    _refreshCitySuggestion();
    if (state.canAdvanceToReview) {
      unawaited(requestPricingEstimate());
    }
  }

  /// Debounced draft write — batches bursts of field edits into one
  /// SecureStorage write. No-op until the restore attempt has resolved, so
  /// an early empty state can never wipe an unread draft.
  void _scheduleDraftPersist() {
    if (!_draftRestoreDone) return;
    if (_draftUid == null) return;
    _draftWriteTimer?.cancel();
    _draftWriteTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persistDraft());
    });
  }

  /// Snapshot the compose payload to durable storage. An emptied compose
  /// clears the stored draft instead of persisting nothing-of-value.
  Future<void> _persistDraft() async {
    final uid = _draftUid;
    if (uid == null) return;
    final s = state;

    final hasContent = s.pickupText.trim().isNotEmpty ||
        s.destinationText.trim().isNotEmpty ||
        s.proposedPickup != null ||
        s.confirmedPickup != null ||
        s.proposedDestination != null ||
        s.confirmedDestination != null ||
        s.passengerOfferDraftText.isNotEmpty;
    if (!hasContent || s.phase == RideRequestPhase.created) {
      await _clearDraft();
      return;
    }

    RideComposeDraftPoint? pointFor(
      ResolvedPassengerLocation? proposed,
      ResolvedPassengerLocation? confirmed,
    ) {
      // At most one is non-null — a new proposal clears the confirmation.
      final loc = proposed ?? confirmed;
      if (loc == null || !loc.hasValidCoordinates) return null;
      return RideComposeDraftPoint(
        lat: loc.lat,
        lng: loc.lng,
        source: loc.source,
        confirmed: confirmed != null && proposed == null,
        address: loc.address,
        placeId: loc.placeId,
        displayName: loc.displayName,
      );
    }

    final draft = RideComposeDraft(
      savedAtMillis: DateTime.now().toUtc().millisecondsSinceEpoch,
      categoryId: s.categoryId,
      serviceType: s.serviceType,
      pickup: pointFor(s.proposedPickup, s.confirmedPickup),
      destination: pointFor(s.proposedDestination, s.confirmedDestination),
      pickupText: s.pickupText,
      destinationText: s.destinationText,
      passengerOfferDraftText: s.passengerOfferDraftText,
    );
    try {
      await _draftStore.writeDraft(uid: uid, draft: draft);
    } catch (_) {
      // Draft loss is acceptable; a failed write must never surface.
    }
  }

  Future<void> _clearDraft() async {
    _draftWriteTimer?.cancel();
    final uid = _draftUid;
    if (uid == null) return;
    try {
      await _draftStore.clearDraft(uid: uid);
    } catch (_) {}
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

  /// Route-deep-link seed (e.g. `?service=intercity` from the home tile).
  void seedServiceType(String? serviceType) {
    if (serviceType == null) return;
    final normalized = serviceType.trim().toLowerCase();
    if (!kRideRequestServiceTypes.contains(normalized)) return;
    if (normalized == state.serviceType) return;
    state = state.copyWith(serviceType: normalized);
  }

  void selectServiceType(String serviceType) {
    final normalized = serviceType.trim().toLowerCase();
    if (!kRideRequestServiceTypes.contains(normalized)) return;
    if (normalized == state.serviceType) return;
    _invalidatePricing();
    state = state.copyWith(
      serviceType: normalized,
      clearBlock: true,
      clearError: true,
    );
    _scheduleDraftPersist();
    unawaited(requestPricingEstimate());
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
      clearPickupNameUnresolved: true,
      clearConfirmedPickup: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      pickupBusy: false,
      clearCitySlug: true,
    );
    _scheduleDraftPersist();
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
    _scheduleDraftPersist();
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
        clearPickupNameUnresolved: true,
        clearConfirmedPickup: true,
        clearPickupLookupError: true,
        clearPinAdjustTarget: true,
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
        clearDestinationNameUnresolved: true,
        clearConfirmedDestination: true,
        clearDestinationLookupError: true,
        clearPinAdjustTarget: true,
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
          clearPickupNameUnresolved: true,
        );
      } else {
        state = state.copyWith(
          destinationBusy: false,
          destinationLookupError: message,
          clearProposedDestination: true,
        );
      }
    }
    _scheduleDraftPersist();
  }

  Future<void> useCurrentLocationForPickup() async {
    final generation = ++_pickupResolveGen;
    _pickupDebounce?.cancel();
    _pickupSearchGen++;
    _invalidatePricing();
    state = state.copyWith(
      pickupBusy: true,
      pickupText: 'Finding location…',
      clearPickupSuggestions: true,
      clearProposedPickup: true,
      clearPickupNameUnresolved: true,
      clearConfirmedPickup: true,
      clearPickupLookupError: true,
      clearPinAdjustTarget: true,
      clearBlock: true,
      clearError: true,
      clearCitySlug: true,
    );

    try {
      final gps = await _deviceLocation.getCurrentLocation();
      if (!_isResolveCurrent(LocationField.pickup, generation)) return;

      // Keep GPS coords authoritative; resolve a human-readable place name.
      final resolved = await _resolvePointName(gps);
      if (!_isResolveCurrent(LocationField.pickup, generation)) return;

      state = state.copyWith(
        proposedPickup: resolved.loc,
        pickupText: resolved.loc.displayLabel,
        pickupBusy: false,
        pickupNameUnresolved: !resolved.named,
        clearPickupSuggestions: true,
        clearPickupLookupError: true,
      );
    } catch (error) {
      if (!_isResolveCurrent(LocationField.pickup, generation)) return;
      state = state.copyWith(
        pickupBusy: false,
        pickupLookupError: _mapLookupError(error),
        clearProposedPickup: true,
        clearPickupNameUnresolved: true,
      );
    }
    _scheduleDraftPersist();
  }

  /// Soft-fail reverse geocode: coords always preserved; never invent locality.
  /// [named] reports whether a real place label was resolved — false means the
  /// UI should surface a name-unresolved state with retry, not fake an address.
  /// [source] is the caller's acquisition source (gps / mapPin) — the resolved
  /// label never rewrites it.
  Future<({ResolvedPassengerLocation loc, bool named})> _resolvePointName(
    ResolvedPassengerLocation point, {
    PassengerLocationSource source = PassengerLocationSource.gps,
  }) async {
    try {
      final named = await _placeSearch.reverseGeocode(
        lat: point.lat,
        lng: point.lng,
      );
      final label = named.address?.trim();
      if (label != null &&
          label.isNotEmpty &&
          label.toLowerCase() != 'current location') {
        return (
          loc: ResolvedPassengerLocation(
            lat: point.lat,
            lng: point.lng,
            address: label,
            placeId: named.placeId,
            source: source,
            horizontalAccuracyMeters: point.horizontalAccuracyMeters,
          ),
          named: true,
        );
      }
    } catch (error) {
      // Soft-fail — keep coords, use graceful display fallback. Log the
      // failure kind for diagnosis (no payload, no key material).
      if (error is PlaceSearchException) {
        debugPrint(
          'reverseGeocode soft-fail: ${error.kind}'
          '${error.message != null ? ' — ${error.message}' : ''}',
        );
      } else {
        debugPrint('reverseGeocode soft-fail: ${error.runtimeType}');
      }
    }
    return (
      loc: ResolvedPassengerLocation(
        lat: point.lat,
        lng: point.lng,
        // No invented address — displayLabel renders 'Location selected'.
        address: null,
        source: source,
        horizontalAccuracyMeters: point.horizontalAccuracyMeters,
      ),
      named: false,
    );
  }

  /// Retry only the place-name lookup for an unresolved GPS/map-pin pickup
  /// proposal — reuses existing coordinates; never triggers a fresh GPS fix.
  Future<void> retryPickupNameLookup() async {
    final proposed = state.proposedPickup;
    if (proposed == null ||
        (proposed.source != PassengerLocationSource.gps &&
            proposed.source != PassengerLocationSource.mapPin) ||
        !proposed.hasValidCoordinates ||
        state.pickupBusy ||
        !state.pickupNameUnresolved) {
      return;
    }
    final generation = ++_pickupResolveGen;
    state = state.copyWith(
      pickupBusy: true,
      clearPickupLookupError: true,
    );
    final resolved = await _resolvePointName(
      proposed,
      source: proposed.source,
    );
    if (!_isResolveCurrent(LocationField.pickup, generation)) return;
    state = state.copyWith(
      proposedPickup: resolved.named ? resolved.loc : proposed,
      pickupText: resolved.named ? resolved.loc.displayLabel : state.pickupText,
      pickupBusy: false,
      pickupNameUnresolved: !resolved.named,
    );
    _scheduleDraftPersist();
  }

  /// Retry only the place-name lookup for an unresolved map-pin destination
  /// proposal — reuses the tapped coordinates verbatim.
  Future<void> retryDestinationNameLookup() async {
    final proposed = state.proposedDestination;
    if (proposed == null ||
        proposed.source != PassengerLocationSource.mapPin ||
        !proposed.hasValidCoordinates ||
        state.destinationBusy ||
        !state.destinationNameUnresolved) {
      return;
    }
    final generation = ++_destinationResolveGen;
    state = state.copyWith(
      destinationBusy: true,
      clearDestinationLookupError: true,
    );
    final resolved = await _resolvePointName(
      proposed,
      source: proposed.source,
    );
    if (!_isResolveCurrent(LocationField.destination, generation)) return;
    state = state.copyWith(
      proposedDestination: resolved.named ? resolved.loc : proposed,
      destinationText:
          resolved.named ? resolved.loc.displayLabel : state.destinationText,
      destinationBusy: false,
      destinationNameUnresolved: !resolved.named,
    );
    _scheduleDraftPersist();
  }

  /// MAP-PIN-ADJUST: enter "set point on map" mode — the next map tap sets
  /// this endpoint's proposed coordinates. UI-only; no pricing/GPS effect.
  void startPinAdjust(LocationField field) {
    if (state.pinAdjustTarget == field) return;
    state = state.copyWith(pinAdjustTarget: field);
  }

  void cancelPinAdjust() {
    if (state.pinAdjustTarget == null) return;
    state = state.copyWith(clearPinAdjustTarget: true);
  }

  /// MAP-PIN-ADJUST: set the active [pinAdjustTarget] endpoint to a tapped
  /// map point. Tapped coordinates are authoritative; the name resolves
  /// best-effort via the same Places→device fallback as GPS (never invented;
  /// unresolved proposals keep the honest retry affordance).
  Future<void> setPinFromMapTap(double lat, double lng) async {
    final field = state.pinAdjustTarget;
    if (field == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return;
    }
    final isPickup = field == LocationField.pickup;
    final generation =
        isPickup ? ++_pickupResolveGen : ++_destinationResolveGen;
    if (isPickup) {
      _pickupDebounce?.cancel();
      _pickupSearchGen++;
    } else {
      _destinationDebounce?.cancel();
      _destinationSearchGen++;
    }
    _invalidatePricing();
    state = isPickup
        ? state.copyWith(
            pickupBusy: true,
            clearPinAdjustTarget: true,
            clearProposedPickup: true,
            clearPickupNameUnresolved: true,
            clearConfirmedPickup: true,
            clearPickupLookupError: true,
            clearPickupSuggestions: true,
            clearBlock: true,
            clearError: true,
            clearCitySlug: true,
          )
        : state.copyWith(
            destinationBusy: true,
            clearPinAdjustTarget: true,
            clearProposedDestination: true,
            clearDestinationNameUnresolved: true,
            clearConfirmedDestination: true,
            clearDestinationLookupError: true,
            clearDestinationSuggestions: true,
            clearBlock: true,
            clearError: true,
          );

    final resolved = await _resolvePointName(
      ResolvedPassengerLocation(
        lat: lat,
        lng: lng,
        source: PassengerLocationSource.mapPin,
      ),
      source: PassengerLocationSource.mapPin,
    );
    if (!_isResolveCurrent(field, generation)) return;
    state = isPickup
        ? state.copyWith(
            proposedPickup: resolved.loc,
            pickupText: resolved.loc.displayLabel,
            pickupBusy: false,
            pickupNameUnresolved: !resolved.named,
          )
        : state.copyWith(
            proposedDestination: resolved.loc,
            destinationText: resolved.loc.displayLabel,
            destinationBusy: false,
            destinationNameUnresolved: !resolved.named,
          );
    _scheduleDraftPersist();
  }

  void confirmPickup() {
    final proposed = state.proposedPickup;
    if (proposed == null || !proposed.hasValidCoordinates) return;
    _invalidatePricing();
    state = state.copyWith(
      confirmedPickup: proposed,
      pickupText: proposed.displayLabel,
      clearProposedPickup: true,
      clearPickupNameUnresolved: true,
      clearPickupSuggestions: true,
      clearPickupLookupError: true,
      clearPinAdjustTarget: true,
      clearBlock: true,
      clearError: true,
    );
    _refreshCitySuggestion();
    _scheduleDraftPersist();
    if (state.canAdvanceToReview) {
      unawaited(requestPricingEstimate());
    }
  }

  /// SAVED-PLACES: apply a saved place — zero network calls; coordinates
  /// were resolved when the place was saved. [displayName] carries the
  /// user-assigned name for UI only (never sent as the ride `address`).
  void applySavedPlace({
    required LocationField field,
    required SavedPlace place,
  }) {
    if (!place.hasValidCoordinates) return;
    _applyLocalLocation(
      field: field,
      resolved: ResolvedPassengerLocation(
        lat: place.lat,
        lng: place.lng,
        address: place.addressLabel,
        placeId: place.placeId,
        source: PassengerLocationSource.savedPlace,
        displayName: place.name,
      ),
      text: place.name,
    );
  }

  /// RECENTS: apply a recent destination — zero network calls.
  void applyRecentDestination(RecentDestination recent) {
    if (!recent.hasValidCoordinates) return;
    _applyLocalLocation(
      field: LocationField.destination,
      resolved: ResolvedPassengerLocation(
        lat: recent.lat,
        lng: recent.lng,
        address: recent.label,
        placeId: recent.placeId,
        source: PassengerLocationSource.recent,
      ),
      text: recent.displayLabel,
    );
  }

  /// Shared proposal path for locally-resolved points (saved/recent).
  /// Mirrors suggestion selection minus the Places details call — state
  /// transitions and generation guards stay identical.
  void _applyLocalLocation({
    required LocationField field,
    required ResolvedPassengerLocation resolved,
    required String text,
  }) {
    final isPickup = field == LocationField.pickup;
    if (isPickup) {
      _pickupDebounce?.cancel();
      _pickupSearchGen++;
      _pickupResolveGen++;
      _invalidatePricing();
      state = state.copyWith(
        pickupText: text,
        proposedPickup: resolved,
        pickupBusy: false,
        clearPickupSuggestions: true,
        clearPickupNameUnresolved: true,
        clearConfirmedPickup: true,
        clearPickupLookupError: true,
        clearPinAdjustTarget: true,
        clearBlock: true,
        clearError: true,
      );
    } else {
      _destinationDebounce?.cancel();
      _destinationSearchGen++;
      _destinationResolveGen++;
      _invalidatePricing();
      state = state.copyWith(
        destinationText: text,
        proposedDestination: resolved,
        destinationBusy: false,
        clearDestinationSuggestions: true,
        clearDestinationNameUnresolved: true,
        clearConfirmedDestination: true,
        clearDestinationLookupError: true,
        clearPinAdjustTarget: true,
        clearBlock: true,
        clearError: true,
      );
    }
    _scheduleDraftPersist();
  }

  /// Persist the proposed-or-confirmed point for [field] as a saved place.
  /// Pass [id] 'home'/'work' for the reserved slots. Returns an error
  /// message on invalid input/storage failure, null on success.
  Future<String?> savePlaceForField({
    required LocationField field,
    required String name,
    String? id,
  }) {
    final isPickup = field == LocationField.pickup;
    final loc = isPickup
        ? (state.proposedPickup ?? state.confirmedPickup)
        : (state.proposedDestination ?? state.confirmedDestination);
    if (loc == null || !loc.hasValidCoordinates) {
      return Future.value('Pick a location first.');
    }
    return _places.savePlace(
      name: name,
      lat: loc.lat,
      lng: loc.lng,
      addressLabel: loc.address,
      placeId: loc.placeId,
      id: id,
    );
  }

  void confirmDestination() {
    final proposed = state.proposedDestination;
    if (proposed == null || !proposed.hasValidCoordinates) return;
    _invalidatePricing();
    state = state.copyWith(
      confirmedDestination: proposed,
      destinationText: proposed.displayLabel,
      clearProposedDestination: true,
      clearDestinationNameUnresolved: true,
      clearDestinationSuggestions: true,
      clearDestinationLookupError: true,
      clearPinAdjustTarget: true,
      clearBlock: true,
      clearError: true,
    );
    // RECENTS: record only on explicit passenger confirmation — abandoned
    // searches and unconfirmed proposals are never recorded.
    unawaited(
      _places.recordRecentDestination(
        lat: proposed.lat,
        lng: proposed.lng,
        label: proposed.address,
        placeId: proposed.placeId,
      ),
    );
    _refreshCitySuggestion();
    _scheduleDraftPersist();
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
    _scheduleDraftPersist();
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
      passengerOfferDraftText: '',
      clearPassengerOfferError: true,
    );
  }

  RideRequestUiState _withPricingSurface({
    required PricingStatus pricingStatus,
    PricingEstimate? pricingEstimate,
    PricingFailureKind? pricingFailureKind,
    String? pricingFailureMessage,
    int? passengerOfferMinor,
    String? passengerOfferDraftText,
    String? passengerOfferError,
  }) {
    return RideRequestUiState(
      phase: state.phase,
      pickupText: state.pickupText,
      destinationText: state.destinationText,
      categoryId: state.categoryId,
      serviceType: state.serviceType,
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
      passengerOfferDraftText: passengerOfferDraftText ?? '',
      passengerOfferError: passengerOfferError,
    );
  }

  /// Reconcile a prior offer against a **new** snapshot (never silent clamp).
  ///
  /// Keeps the previous offer only when it still lies within the new bounds;
  /// otherwise resets to [estimate.recommendedFareMinor].
  ({int offerMinor, String draft}) _reconcileOfferForEstimate(
    PricingEstimate estimate,
  ) {
    final previous = state.passengerOfferMinor;
    if (previous != null &&
        previous >= estimate.offerBoundMinMinor &&
        previous <= estimate.offerBoundMaxMinor) {
      return (
        offerMinor: previous,
        draft: offerRupeesFieldText(previous),
      );
    }
    return (
      offerMinor: estimate.recommendedFareMinor,
      draft: offerRupeesFieldText(estimate.recommendedFareMinor),
    );
  }

  /// Passenger edited the offer field (whole PKR). Does not clamp out-of-range.
  void setPassengerOfferDraft(String text) {
    final estimate = state.pricingEstimate;
    if (!state.hasUsablePricing || estimate == null) return;

    final result = validatePassengerOfferRupees(
      text: text,
      offerBoundMinMinor: estimate.offerBoundMinMinor,
      offerBoundMaxMinor: estimate.offerBoundMaxMinor,
    );
    if (result.isValid) {
      state = state.copyWith(
        passengerOfferDraftText: text,
        passengerOfferMinor: result.amountMinor,
        clearPassengerOfferError: true,
        clearBlock: true,
      );
      _scheduleDraftPersist();
      return;
    }
    state = state.copyWith(
      passengerOfferDraftText: text,
      clearPassengerOffer: true,
      passengerOfferError: result.message,
      clearBlock: true,
    );
    _scheduleDraftPersist();
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
        state.pricingEstimate?.category == state.categoryId &&
        _estimateServiceType == state.serviceType) {
      return;
    }

    final generation = ++_pricingGen;
    // Keep prior offer through loading so success can reconcile vs new bounds.
    state = _withPricingSurface(
      pricingStatus: PricingStatus.loading,
      passengerOfferMinor: state.passengerOfferMinor,
      passengerOfferDraftText: state.passengerOfferDraftText,
      passengerOfferError: state.passengerOfferError,
    );

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
          serviceType: state.serviceType,
        ),
      );
      if (generation != _pricingGen) return;
      _estimateServiceType = state.serviceType;
      // New snapshot: keep prior offer only if still in-bounds; else recommended.
      final reconciled = _reconcileOfferForEstimate(estimate);
      state = _withPricingSurface(
        pricingStatus: PricingStatus.success,
        pricingEstimate: estimate,
        passengerOfferMinor: reconciled.offerMinor,
        passengerOfferDraftText: reconciled.draft,
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
    if (!_usesInjectedPricing && !state.hasValidPassengerOffer) return false;
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
    if (!_usesInjectedPricing && !state.hasValidPassengerOffer) {
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
        state.passengerOfferError ??
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

    // Re-validate draft against current snapshot before create.
    if (!_usesInjectedPricing && state.hasUsablePricing) {
      final estimate = state.pricingEstimate!;
      final result = validatePassengerOfferRupees(
        text: state.passengerOfferDraftText,
        offerBoundMinMinor: estimate.offerBoundMinMinor,
        offerBoundMaxMinor: estimate.offerBoundMaxMinor,
      );
      if (!result.isValid) {
        state = state.copyWith(
          clearPassengerOffer: true,
          passengerOfferDraftText: state.passengerOfferDraftText,
          passengerOfferError: result.message,
          phase: RideRequestPhase.blocked,
          blockReason: RideRequestBlockReason.pricingUnavailable,
          clearError: true,
        );
        return;
      }
      if (state.passengerOfferMinor != result.amountMinor) {
        state = state.copyWith(passengerOfferMinor: result.amountMinor);
      }
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
    // Prefer the validated draft amount over any stale capability fallback.
    final offerMinor = (!_usesInjectedPricing && state.passengerOfferMinor != null)
        ? state.passengerOfferMinor!
        : caps.passengerOfferMinor!;
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
          'serviceType': state.serviceType,
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
      // The request is now a real ride — the compose draft's job is done.
      unawaited(_clearDraft());
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
