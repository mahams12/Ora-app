import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/use_cases/ride_use_cases.dart';
import '../../domain/driver_earnings_summary.dart';

enum DriverEarningsPhase {
  initialLoading,
  ready,
  empty,
  fatalError,
}

/// Completed rides only (server filter `status=completed` →
/// RIDE_COMPLETED + RIDE_CLOSED). Totals are verified trip fares —
/// never payouts; see [computeDriverEarnings] contract.
const driverEarningsCompletedStatus = 'completed';

/// Server list limit is capped at 50; the summary pre-scans at most this many
/// rides so totals cover a bounded, stated window (not silently partial).
const driverEarningsScanCap = 200;

const _pageLimit = 50;

class DriverEarningsUiState {
  const DriverEarningsUiState({
    this.phase = DriverEarningsPhase.initialLoading,
    this.rides = const [],
    this.summary,
    this.nextCursor,
    this.scanCapped = false,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.paginationError,
  });

  final DriverEarningsPhase phase;
  final List<Ride> rides;
  final DriverEarningsSummary? summary;
  final String? nextCursor;

  /// True when history still has more pages but the automatic scan stopped at
  /// [driverEarningsScanCap] — totals cover loaded rides only until the user
  /// loads more (or the cursor exhausts).
  final bool scanCapped;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? errorMessage;
  final String? paginationError;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  bool get canLoadMore =>
      hasMore &&
      !isLoadingMore &&
      !isRefreshing &&
      phase != DriverEarningsPhase.initialLoading;

  DriverEarningsUiState copyWith({
    DriverEarningsPhase? phase,
    List<Ride>? rides,
    DriverEarningsSummary? summary,
    String? nextCursor,
    bool? scanCapped,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? errorMessage,
    String? paginationError,
    bool clearNextCursor = false,
    bool clearError = false,
    bool clearPaginationError = false,
  }) {
    return DriverEarningsUiState(
      phase: phase ?? this.phase,
      rides: rides ?? this.rides,
      summary: summary ?? this.summary,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      scanCapped: scanCapped ?? this.scanCapped,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      paginationError: clearPaginationError
          ? null
          : (paginationError ?? this.paginationError),
    );
  }
}

/// Driver earnings — verified completed-ride fares via GET /v1/rides.
///
/// Authorization is server-side: the same endpoint scopes results to
/// `assignedDriverId == caller uid` (drivers only see their own records).
/// There is no payout/commission field today — the UI labels fares honestly.
class DriverEarningsViewModel
    extends AutoDisposeNotifier<DriverEarningsUiState> {
  late final ListRidesUseCase _listRides;
  late final FailureMapper _failures;

  bool _loadMoreInFlight = false;
  bool _refreshInFlight = false;
  int _requestSeq = 0;

  @override
  DriverEarningsUiState build() {
    _listRides = ref.read(listRidesUseCaseProvider);
    _failures = ref.read(failureMapperProvider);
    return const DriverEarningsUiState();
  }

  Future<void> loadInitial() async {
    final seq = ++_requestSeq;
    state = state.copyWith(
      phase: DriverEarningsPhase.initialLoading,
      rides: const [],
      summary: null,
      clearNextCursor: true,
      scanCapped: false,
      clearError: true,
      clearPaginationError: true,
      isRefreshing: false,
      isLoadingMore: false,
    );
    await _fetchScan(seq: seq);
  }

  Future<void> refresh() async {
    if (_refreshInFlight ||
        state.phase == DriverEarningsPhase.initialLoading) {
      return;
    }
    _refreshInFlight = true;
    final seq = ++_requestSeq;
    state = state.copyWith(
      isRefreshing: true,
      scanCapped: false,
      clearNextCursor: true,
      clearError: true,
      clearPaginationError: true,
    );
    try {
      await _fetchScan(seq: seq, refreshing: true);
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Continues server pagination past the automatic scan cap; totals recompute
  /// and [scanCapped] clears once the cursor exhausts.
  Future<void> loadMore() async {
    if (!state.canLoadMore || _loadMoreInFlight) return;
    final cursor = state.nextCursor;
    if (cursor == null || cursor.isEmpty) return;

    _loadMoreInFlight = true;
    final seq = ++_requestSeq;
    state = state.copyWith(isLoadingMore: true, clearPaginationError: true);
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

  /// Auto-scans completed-ride pages until the cursor exhausts or the scan cap
  /// is hit — bounded (≤4 requests), sequential, owner-scoped by the server.
  Future<void> _fetchScan({required int seq, bool refreshing = false}) async {
    var cursor = state.nextCursor;
    var guard = 0;
    // On refresh the first page replaces the stale list; later scan pages
    // append so multi-page histories aggregate correctly.
    var append = !refreshing;
    do {
      final ok = await _fetchPage(
        seq: seq,
        append: append,
        refreshing: refreshing,
        cursor: cursor,
      );
      if (!ok || seq != _requestSeq) return;
      cursor = state.nextCursor;
      guard++;
      append = true;
    } while (cursor != null &&
        cursor.isNotEmpty &&
        state.rides.length < driverEarningsScanCap &&
        guard < 8);

    if (seq != _requestSeq) return;
    state = state.copyWith(scanCapped: state.hasMore);
  }

  Future<bool> _fetchPage({
    required int seq,
    required bool append,
    required bool refreshing,
    String? cursor,
  }) async {
    try {
      final page = await _listRides(
        limit: _pageLimit,
        cursor: cursor,
        status: driverEarningsCompletedStatus,
      );
      if (seq != _requestSeq) return false;

      final merged = append
          ? _dedupeAppend(state.rides, page.rides)
          : List<Ride>.from(page.rides);
      final next = page.nextCursor;
      final hasNext = next != null && next.isNotEmpty;

      state = state.copyWith(
        phase: merged.isEmpty
            ? DriverEarningsPhase.empty
            : DriverEarningsPhase.ready,
        rides: merged,
        summary: computeDriverEarnings(merged),
        nextCursor: hasNext ? next : null,
        clearNextCursor: !hasNext,
        scanCapped: hasNext ? state.scanCapped : false,
        isRefreshing: false,
        isLoadingMore: false,
        clearError: true,
        clearPaginationError: true,
      );
      return true;
    } catch (error, stack) {
      if (seq != _requestSeq) return false;
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
          phase: DriverEarningsPhase.ready,
        );
      } else {
        state = state.copyWith(
          phase: DriverEarningsPhase.fatalError,
          isRefreshing: false,
          isLoadingMore: false,
          errorMessage: failure.userMessage,
          rides: const [],
          summary: null,
          clearNextCursor: true,
        );
      }
      return false;
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

final driverEarningsViewModelProvider = NotifierProvider.autoDispose<
    DriverEarningsViewModel, DriverEarningsUiState>(
  DriverEarningsViewModel.new,
);
