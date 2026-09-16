import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';
import '../../../ride/presentation/history/ride_history_display.dart';

enum DriverAssignedRidesPhase {
  initialLoading,
  ready,
  empty,
  fatalError,
}

class DriverAssignedRidesUiState {
  const DriverAssignedRidesUiState({
    this.phase = DriverAssignedRidesPhase.initialLoading,
    this.rides = const [],
    this.nextCursor,
    this.status = 'all',
    this.serviceType,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.paginationError,
  });

  final DriverAssignedRidesPhase phase;
  final List<Ride> rides;
  final String? nextCursor;
  final String status;
  final String? serviceType;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? paginationError;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  bool get canLoadMore =>
      hasMore &&
      !isLoadingMore &&
      !isRefreshing &&
      phase != DriverAssignedRidesPhase.initialLoading;

  DriverAssignedRidesUiState copyWith({
    DriverAssignedRidesPhase? phase,
    List<Ride>? rides,
    String? nextCursor,
    String? status,
    String? serviceType,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? errorMessage,
    String? paginationError,
    bool clearNextCursor = false,
    bool clearServiceType = false,
    bool clearError = false,
    bool clearPaginationError = false,
  }) {
    return DriverAssignedRidesUiState(
      phase: phase ?? this.phase,
      rides: rides ?? this.rides,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      status: status ?? this.status,
      serviceType:
          clearServiceType ? null : (serviceType ?? this.serviceType),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      paginationError: clearPaginationError
          ? null
          : (paginationError ?? this.paginationError),
    );
  }
}

/// Driver assigned rides / history via GET /v1/rides — not a marketplace feed.
class DriverAssignedRidesViewModel
    extends AutoDisposeNotifier<DriverAssignedRidesUiState> {
  late final ListRidesUseCase _listRides;
  late final FailureMapper _failures;

  bool _loadMoreInFlight = false;
  bool _refreshInFlight = false;
  int _requestSeq = 0;

  @override
  DriverAssignedRidesUiState build() {
    _listRides = ref.read(listRidesUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    return const DriverAssignedRidesUiState();
  }

  Future<void> loadInitial() async {
    final seq = ++_requestSeq;
    state = state.copyWith(
      phase: DriverAssignedRidesPhase.initialLoading,
      rides: const [],
      clearNextCursor: true,
      clearError: true,
      clearPaginationError: true,
      isRefreshing: false,
      isLoadingMore: false,
    );
    await _fetchPage(seq: seq, append: false, refreshing: false);
  }

  Future<void> refresh() async {
    if (_refreshInFlight ||
        state.phase == DriverAssignedRidesPhase.initialLoading) {
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

  Future<void> setStatus(String status) async {
    final normalized = status.toLowerCase();
    if (!rideHistoryStatusFilters.contains(normalized)) return;
    if (normalized == state.status &&
        state.phase != DriverAssignedRidesPhase.fatalError) {
      return;
    }
    state = state.copyWith(status: normalized, clearNextCursor: true);
    await loadInitial();
  }

  Future<void> setServiceType(String? serviceType) async {
    final normalized = serviceType?.toLowerCase();
    if (normalized != null &&
        !rideHistoryServiceTypes.contains(normalized)) {
      return;
    }
    final current = state.serviceType;
    if (normalized == current &&
        state.phase != DriverAssignedRidesPhase.fatalError) {
      return;
    }
    state = normalized == null
        ? state.copyWith(clearServiceType: true, clearNextCursor: true)
        : state.copyWith(serviceType: normalized, clearNextCursor: true);
    await loadInitial();
  }

  Future<void> retry() => loadInitial();

  Future<void> _fetchPage({
    required int seq,
    required bool append,
    required bool refreshing,
    String? cursor,
  }) async {
    try {
      final page = await _listRides(
        limit: rideHistoryDefaultLimit,
        cursor: cursor,
        status: state.status,
        serviceType: state.serviceType,
      );
      if (seq != _requestSeq) return;

      final merged = append
          ? _dedupeAppend(state.rides, page.rides)
          : List<Ride>.from(page.rides);
      final next = page.nextCursor;
      final hasNext = next != null && next.isNotEmpty;

      state = state.copyWith(
        phase: merged.isEmpty
            ? DriverAssignedRidesPhase.empty
            : DriverAssignedRidesPhase.ready,
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
      if (append && state.rides.isNotEmpty) {
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
          phase: DriverAssignedRidesPhase.ready,
        );
      } else {
        state = state.copyWith(
          phase: DriverAssignedRidesPhase.fatalError,
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: failure.userMessage,
          rides: const [],
          clearNextCursor: true,
        );
      }
    }
  }

  List<Ride> _dedupeAppend(List<Ride> existing, List<Ride> incoming) {
    final seen = existing.map((r) => r.rideId).toSet();
    final out = List<Ride>.from(existing);
    for (final ride in incoming) {
      if (seen.add(ride.rideId)) {
        out.add(ride);
      }
    }
    return out;
  }
}

final driverAssignedRidesViewModelProvider = NotifierProvider.autoDispose<
    DriverAssignedRidesViewModel, DriverAssignedRidesUiState>(
  DriverAssignedRidesViewModel.new,
);
