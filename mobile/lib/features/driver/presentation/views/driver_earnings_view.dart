import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../view_models/driver_earnings_view_model.dart';

/// Driver earnings — verified trip fares from completed rides only.
/// The backend records no payout/commission today; that's labelled, not faked.
class DriverEarningsView extends ConsumerStatefulWidget {
  const DriverEarningsView({super.key, this.active = false});

  final bool active;

  @override
  ConsumerState<DriverEarningsView> createState() => _DriverEarningsViewState();
}

class _DriverEarningsViewState extends ConsumerState<DriverEarningsView> {
  bool _initialLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadInitial();
  }

  @override
  void didUpdateWidget(DriverEarningsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _maybeLoadInitial();
    }
  }

  void _maybeLoadInitial() {
    if (!widget.active || _initialLoadRequested) return;
    _initialLoadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(driverEarningsViewModelProvider.notifier).loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_initialLoadRequested) {
      return const SizedBox.expand();
    }
    final state = ref.watch(driverEarningsViewModelProvider);
    final padding = Responsive.horizontalPadding(context);

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: () =>
          ref.read(driverEarningsViewModelProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        children: [
          if (state.phase == DriverEarningsPhase.initialLoading)
            const Padding(
              padding: EdgeInsets.only(top: OraSpacing.xxl),
              child: Center(
                child: OraLoadingIndicator(message: 'Loading earnings…'),
              ),
            )
          else if (state.phase == DriverEarningsPhase.fatalError)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.14,
              ),
              child: OraErrorState(
                title: 'Couldn’t load earnings',
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => ref
                    .read(driverEarningsViewModelProvider.notifier)
                    .retry(),
              ),
            )
          else ...[
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: OraSpacing.sm),
                child: Text(
                  state.errorMessage!,
                  style: OraTypography.caption(OraColors.dangerForeground),
                ),
              ),
            _SummaryCard(state: state),
            const SizedBox(height: OraSpacing.lg),
            Text(
              'Completed trips',
              style: OraTypography.headline(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.sm),
            if (state.phase == DriverEarningsPhase.empty)
              const OraEmptyState(
                title: 'No completed trips yet',
                message:
                    'Trips you complete will appear here with their agreed '
                    'fare. Only finished rides count toward totals.',
                icon: Icons.receipt_long_outlined,
              )
            else ...[
              for (final ride in state.rides)
                Padding(
                  padding: const EdgeInsets.only(bottom: OraSpacing.sm),
                  child: RideCard(
                    model: RideCardAdapters.fromDriverJob(
                      ride,
                      onTap: () =>
                          context.push(AppRoutes.driverRidePath(ride.rideId)),
                    ),
                  ),
                ),
              _PaginationFooter(
                state: state,
                onLoadMore: () => ref
                    .read(driverEarningsViewModelProvider.notifier)
                    .loadMore(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final DriverEarningsUiState state;

  String _fare(int minor, String? currency) =>
      formatMinorFare(minor, currency) ?? '—';

  @override
  Widget build(BuildContext context) {
    final summary = state.summary;
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // "Driver payout" only when a server-derived payout snapshot
            // exists; "Trip fares" remains the honest fallback for
            // pre-payout-model rides.
            (summary?.allTime.payoutRideCount ?? 0) > 0
                ? 'Driver payout'
                : 'Trip fares',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            summary == null
                ? '—'
                : _fare(summary.allTime.faresMinor, summary.allTime.currency),
            style: OraTypography.headline(OraColors.textPrimary).copyWith(
              fontSize: 32,
            ),
          ),
          Text(
            (summary?.allTime.payoutRideCount ?? 0) > 0
                ? 'Server-verified payout for completed trips — the launch '
                    'platform fee is zero, so payout equals the agreed fare.'
                : 'Verified fares agreed with passengers on your completed '
                    'trips. This is the gross trip fare — not a payout.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.md),
          Row(
            children: [
              _PeriodTile(
                label: 'Today',
                value: summary == null
                    ? '—'
                    : _fare(
                        summary.today.faresMinor, summary.today.currency),
                count: summary?.today.rideCount,
              ),
              const SizedBox(width: OraSpacing.sm),
              _PeriodTile(
                label: 'Last 7 days',
                value: summary == null
                    ? '—'
                    : _fare(
                        summary.last7Days.faresMinor,
                        summary.last7Days.currency,
                      ),
                count: summary?.last7Days.rideCount,
              ),
              const SizedBox(width: OraSpacing.sm),
              _PeriodTile(
                label: 'Completed trips',
                value: '${summary?.completedRideCount ?? 0}',
                count: null,
              ),
            ],
          ),
          if (summary != null && summary.ridesMissingFare > 0) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              '${summary.ridesMissingFare} completed '
              '${summary.ridesMissingFare == 1 ? 'trip has' : 'trips have'} '
              'no recorded fare — excluded from totals.',
              style: OraTypography.caption(OraColors.dangerForeground),
            ),
          ],
          if (summary != null && summary.allTime.fareOnlyMinor > 0) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              '${_fare(summary.allTime.fareOnlyMinor, summary.allTime.currency)} '
              'of the total comes from older trips reporting trip fare only '
              '(pre-payout records).',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          if (state.scanCapped) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              'Totals cover your ${state.rides.length} most recent completed '
              'trips — load more below for the full history.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          const SizedBox(height: OraSpacing.md),
          Container(
            padding: const EdgeInsets.all(OraSpacing.sm),
            decoration: BoxDecoration(
              color: OraColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: OraColors.info,
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Text(
                    'Settlement, cash-out and commission are not recorded by '
                    'Ora yet — at launch the payout equals the agreed fare.',
                    style: OraTypography.caption(OraColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.label,
    required this.value,
    required this.count,
  });

  final String label;
  final String value;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(OraSpacing.sm),
        decoration: BoxDecoration(
          color: OraColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: OraTypography.caption(OraColors.textMuted)),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              value,
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            ),
            if (count != null)
              Text(
                '$count ${count == 1 ? 'trip' : 'trips'}',
                style: OraTypography.caption(OraColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.state, required this.onLoadMore});

  final DriverEarningsUiState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.paginationError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
        child: Column(
          children: [
            Text(
              state.paginationError!,
              textAlign: TextAlign.center,
              style: OraTypography.caption(OraColors.dangerForeground),
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(
              label: 'Retry load more',
              variant: OraButtonVariant.outline,
              onPressed: onLoadMore,
            ),
          ],
        ),
      );
    }
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: OraSpacing.lg),
        child: Center(child: OraLoadingIndicator()),
      );
    }
    if (state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
        child: OraButton(
          label: 'Load more',
          variant: OraButtonVariant.outline,
          onPressed: state.canLoadMore ? onLoadMore : null,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
      child: Text(
        'End of history',
        textAlign: TextAlign.center,
        style: OraTypography.caption(OraColors.textMuted),
      ),
    );
  }
}
