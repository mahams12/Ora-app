import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/storage/idempotency_nonce_store.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';
import '../../../ride/presentation/offers/offer_display.dart';
import '../open_ride_display.dart';
import 'driver_direct_offer_view_model.dart';

enum DriverOpenRidesPhase {
  initialLoading,
  ready,
  empty,
  fatalError,
}

class DriverOpenRidesUiState {
  const DriverOpenRidesUiState({
    this.phase = DriverOpenRidesPhase.initialLoading,
    this.rides = const [],
    this.nextCursor,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.paginationError,
    this.offeringRideId,
    this.lastCreatedOffer,
    this.offerErrorMessage,
    this.offerInfoMessage,
  });

  final DriverOpenRidesPhase phase;
  final List<OpenRide> rides;
  final String? nextCursor;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? paginationError;
  final String? offeringRideId;
  final RideOffer? lastCreatedOffer;
  final String? offerErrorMessage;
  final String? offerInfoMessage;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  bool get canLoadMore =>
      hasMore &&
      !isLoadingMore &&
      !isRefreshing &&
      offeringRideId == null &&
      phase != DriverOpenRidesPhase.initialLoading;

  bool get isOffering => offeringRideId != null;

  DriverOpenRidesUiState copyWith({
    DriverOpenRidesPhase? phase,
    List<OpenRide>? rides,
    String? nextCursor,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? errorMessage,
    String? paginationError,
    String? offeringRideId,
    RideOffer? lastCreatedOffer,
    String? offerErrorMessage,
    String? offerInfoMessage,
    bool clearNextCursor = false,
    bool clearError = false,
    bool clearPaginationError = false,
    bool clearOffering = false,
    bool clearLastOffer = false,
    bool clearOfferError = false,
    bool clearOfferInfo = false,
  }) {
    return DriverOpenRidesUiState(
      phase: phase ?? this.phase,
      rides: rides ?? this.rides,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      paginationError: clearPaginationError
          ? null
          : (paginationError ?? this.paginationError),
      offeringRideId:
          clearOffering ? null : (offeringRideId ?? this.offeringRideId),
      lastCreatedOffer: clearLastOffer
          ? null
          : (lastCreatedOffer ?? this.lastCreatedOffer),
      offerErrorMessage: clearOfferError
          ? null
          : (offerErrorMessage ?? this.offerErrorMessage),
      offerInfoMessage: clearOfferInfo
          ? null
          : (offerInfoMessage ?? this.offerInfoMessage),
    );
  }
}

/// Open-ride discovery via GET /v1/rides/open — not nearby / GEO.
class DriverOpenRidesViewModel
    extends AutoDisposeNotifier<DriverOpenRidesUiState> {
  late final ListOpenRidesUseCase _listOpenRides;
  late final CreateOfferUseCase _createOffer;
  late final FailureMapper _failures;
  late final IdempotencyNonceStore _nonceStore;

  bool _loadMoreInFlight = false;
  bool _refreshInFlight = false;
  int _requestSeq = 0;
  int _offerGen = 0;
  String? _createOpKey;

  @override
  DriverOpenRidesUiState build() {
    _listOpenRides = ref.read(listOpenRidesUseCaseProvider);
    _createOffer = ref.read(createOfferUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    _nonceStore = ref.read(idempotencyNonceStoreProvider);
    return const DriverOpenRidesUiState();
  }

  Future<void> loadInitial() async {
    final seq = ++_requestSeq;
    state = state.copyWith(
      phase: DriverOpenRidesPhase.initialLoading,
      rides: const [],
      clearNextCursor: true,
      clearError: true,
      clearPaginationError: true,
      clearOfferError: true,
      clearOfferInfo: true,
      isRefreshing: false,
      isLoadingMore: false,
    );
    await _fetchPage(seq: seq, append: false, refreshing: false);
  }

  Future<void> refresh() async {
    if (_refreshInFlight ||
        state.phase == DriverOpenRidesPhase.initialLoading ||
        state.isOffering) {
      return;
    }
    _refreshInFlight = true;
    final seq = ++_requestSeq;
    state = state.copyWith(
      isRefreshing: true,
      clearError: true,
      clearPaginationError: true,
    );
    try {
      await _fetchPage(seq: seq, append: false, refreshing: true);
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> loadMore() async {
    if (!state.canLoadMore || _loadMoreInFlight) return;
    final cursor = state.nextCursor;
    if (cursor == null || cursor.isEmpty) return;

    _loadMoreInFlight = true;
    final seq = ++_requestSeq;
    state = state.copyWith(
      isLoadingMore: true,
      clearPaginationError: true,
    );
    try {
      await _fetchPage(
        seq: seq,
        append: true,
        refreshing: false,
        cursor: cursor,
      );
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<void> retry() => loadInitial();

  Future<void> submitOffer({
    required OpenRide ride,
    required String type,
    required int amountMinor,
  }) async {
    if (state.isOffering) return;
    if (!driverOfferTypes.contains(type)) return;
    if (amountMinor <= 0) return;

    final gen = ++_offerGen;
    _createOpKey ??= 'open-offer:create:${ride.rideId}:${const Uuid().v4()}';
    state = state.copyWith(
      offeringRideId: ride.rideId,
      clearLastOffer: true,
      clearOfferError: true,
      clearOfferInfo: true,
    );

    try {
      final offer = await _createOffer(
        rideId: ride.rideId,
        body: {
          'type': type,
          'amountMinor': amountMinor,
          'expectedRequestVersion': ride.requestVersion,
        },
        operationKey: _createOpKey!,
      );
      if (gen != _offerGen) return;

      final old = _createOpKey;
      _createOpKey = null;
      if (old != null) unawaited(_nonceStore.clear(old));

      state = state.copyWith(
        clearOffering: true,
        lastCreatedOffer: offer,
        offerInfoMessage:
            'Offer ${offer.offerId} submitted for this request '
            '(${formatOfferAmountMinor(offer.amountMinor, offer.currency)}). '
            'Server-confirmed — not assigned until passenger selects.',
        clearOfferError: true,
      );
    } catch (error, stack) {
      if (gen != _offerGen) return;
      await _handleOfferFailure(
        _failures.fromException(error, stack),
        rideId: ride.rideId,
      );
    }
  }

  Future<void> _handleOfferFailure(
    AppFailure failure, {
    required String rideId,
  }) async {
    final code = failure.maybeWhen(
      conflict: (message, code) => code,
      forbidden: (message) => 'FORBIDDEN',
      validation: (message, fieldErrors) => 'VALIDATION',
      orElse: () => null,
    );

    final unavailable = code == 'ALREADY_ASSIGNED' ||
        code == 'STATE_CONFLICT' ||
        code == 'VERSION_CONFLICT';

    final definitiveKeyClear = unavailable ||
        code == 'IDEMPOTENCY_KEY_REUSED' ||
        code == 'VALIDATION' ||
        code == 'FORBIDDEN';

    if (definitiveKeyClear) {
      final old = _createOpKey;
      _createOpKey = null;
      if (old != null) unawaited(_nonceStore.clear(old));
    }

    var message = failure.userMessage;
    if (unavailable) {
      message =
          'This ride request is no longer available. Refreshing open rides.';
      state = state.copyWith(
        clearOffering: true,
        offerErrorMessage: message,
        clearOfferInfo: true,
        rides: state.rides.where((r) => r.rideId != rideId).toList(),
      );
      unawaited(refresh());
      return;
    }

    // OFFER_STALE arrives as validation (422) — ask driver to refresh.
    if (code == 'VALIDATION') {
      message =
          '${failure.userMessage} Request version may have changed — refresh open rides.';
    }

    state = state.copyWith(
      clearOffering: true,
      offerErrorMessage: message,
      clearOfferInfo: true,
    );
  }

  Future<void> _fetchPage({
    required int seq,
    required bool append,
    required bool refreshing,
    String? cursor,
  }) async {
    try {
      final page = await _listOpenRides(
        limit: openRidesDefaultLimit,
        cursor: cursor,
      );
      if (seq != _requestSeq) return;

      final merged = append
          ? _dedupeAppend(state.rides, page.rides)
          : List<OpenRide>.from(page.rides);
      final next = page.nextCursor;
      final hasNext = next != null && next.isNotEmpty;

      state = state.copyWith(
        phase: merged.isEmpty
            ? DriverOpenRidesPhase.empty
            : DriverOpenRidesPhase.ready,
        rides: merged,
        nextCursor: hasNext ? next : null,
        clearNextCursor: !hasNext,
        isRefreshing: false,
        isLoadingMore: false,
        clearError: true,
        clearPaginationError: true,
      );
    } catch (error, stack) {
      if (seq != _requestSeq) return;
      final failure = _failures.fromException(error, stack);
      if (append) {
        state = state.copyWith(
          isLoadingMore: false,
          isRefreshing: false,
          paginationError: failure.userMessage,
        );
      } else if (refreshing && state.rides.isNotEmpty) {
        state = state.copyWith(
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: failure.userMessage,
        );
      } else {
        state = state.copyWith(
          phase: DriverOpenRidesPhase.fatalError,
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: failure.userMessage,
          rides: const [],
          clearNextCursor: true,
        );
      }
    }
  }

  List<OpenRide> _dedupeAppend(List<OpenRide> existing, List<OpenRide> incoming) {
    final seen = existing.map((r) => r.rideId).toSet();
    final out = List<OpenRide>.from(existing);
    for (final ride in incoming) {
      if (seen.add(ride.rideId)) {
        out.add(ride);
      }
    }
    return out;
  }
}

final driverOpenRidesViewModelProvider = NotifierProvider.autoDispose<
    DriverOpenRidesViewModel, DriverOpenRidesUiState>(
  DriverOpenRidesViewModel.new,
);
