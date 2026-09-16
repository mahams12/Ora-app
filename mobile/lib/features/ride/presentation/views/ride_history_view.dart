import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/ride.dart';
import '../history/ride_history_display.dart';
import '../view_models/ride_history_view_model.dart';

/// Passenger My Rides — server-backed list via GET /v1/rides.
///
/// [active] gates the initial load so IndexedStack mounting Home does not
/// fetch history until the Rides tab is first shown (Slice K-P2-01).
class RideHistoryView extends ConsumerStatefulWidget {
  const RideHistoryView({super.key, this.active = false});

  /// True when the shell's Rides tab is selected.
  final bool active;

  @override
  ConsumerState<RideHistoryView> createState() => _RideHistoryViewState();
}

class _RideHistoryViewState extends ConsumerState<RideHistoryView> {
  bool _initialLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadInitial();
  }

  @override
  void didUpdateWidget(RideHistoryView oldWidget) {
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
      ref.read(rideHistoryViewModelProvider.notifier).loadInitial();
    });
  }

  void _openRide(BuildContext context, Ride ride) {
    switch (rideHistoryDestinationFor(ride.state)) {
      case RideHistoryDestination.offers:
        context.push(AppRoutes.offersInboxPath(ride.rideId));
      case RideHistoryDestination.active:
        context.push(AppRoutes.activeRidePath(ride.rideId));
      case RideHistoryDestination.detail:
        context.push(AppRoutes.rideHistoryDetailPath(ride.rideId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps this mounted off-tab. Avoid an infinite loading
    // spinner before the first gated load (breaks pumpAndSettle / wastes work).
    if (!widget.active && !_initialLoadRequested) {
      return const Scaffold(
        backgroundColor: OraColors.background,
        body: SizedBox.expand(),
      );
    }

    final state = ref.watch(rideHistoryViewModelProvider);
    final vm = ref.read(rideHistoryViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: OraColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding,
                OraSpacing.md,
                padding,
                OraSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My rides',
                    style: OraTypography.headline(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    'Trips from Ora\'s servers. All can include active rides — '
                    'not a past-only list.',
                    style: OraTypography.caption(OraColors.textMuted),
                  ),
                  const SizedBox(height: OraSpacing.md),
                  _FilterRow(
                    label: 'Status',
                    children: [
                      for (final status in rideHistoryStatusFilters)
                        OraChip(
                          label: historyStatusFilterLabel(status),
                          selected: state.status == status,
                          onTap: () => vm.setStatus(status),
                        ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  _FilterRow(
                    label: 'Service',
                    children: [
                      OraChip(
                        label: 'Any',
                        selected: state.serviceType == null,
                        onTap: () => vm.setServiceType(null),
                      ),
                      for (final type in rideHistoryServiceTypes)
                        OraChip(
                          label: historyServiceTypeLabel(type),
                          selected: state.serviceType == type,
                          onTap: () => vm.setServiceType(type),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(child: _Body(state: state, onOpen: _openRide)),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: OraTypography.label(OraColors.textSecondary)),
        const SizedBox(height: OraSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: OraSpacing.xs),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state, required this.onOpen});

  final RideHistoryUiState state;
  final void Function(BuildContext context, Ride ride) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(rideHistoryViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    if (state.phase == RideHistoryPhase.initialLoading) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading your rides…'),
      );
    }

    if (state.phase == RideHistoryPhase.fatalError) {
      return OraErrorState(
        title: 'Couldn’t load rides',
        message: state.errorMessage ?? 'Something went wrong.',
        onRetry: vm.retry,
      );
    }

    if (state.phase == RideHistoryPhase.empty) {
      return RefreshIndicator(
        color: OraColors.primary,
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(padding),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
            OraEmptyState(
              title: 'No rides here',
              message: state.status == 'all'
                  ? 'When you request a ride, it will show up from the server.'
                  : 'No rides match this filter on the server.',
              icon: Icons.receipt_long_rounded,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: vm.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        // Soft refresh error (+1) + rides + pagination footer.
        itemCount: state.rides.length + 1 + (state.errorMessage != null ? 1 : 0),
        itemBuilder: (context, index) {
          final hasSoftError = state.errorMessage != null;
          if (hasSoftError && index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: Text(
                state.errorMessage!,
                style: OraTypography.caption(OraColors.dangerForeground),
              ),
            );
          }
          final rideIndex = hasSoftError ? index - 1 : index;
          if (rideIndex < state.rides.length) {
            final ride = state.rides[rideIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: _RideHistoryCard(
                ride: ride,
                onTap: () => onOpen(context, ride),
              ),
            );
          }
          return _PaginationFooter(state: state, onLoadMore: vm.loadMore);
        },
      ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fare = formatMinorFare(ride.agreedFareMinor, ride.agreedFareCurrency);
    final when = formatHistoryTimestamp(ride.createdAt);
    final pickup = ride.pickup.address;
    final drop = ride.destination.address;

    return OraCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  historyRideTitle(ride.state),
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
              ),
              OraChip(
                label: ride.state,
                selected: !isHistoryTerminalState(ride.state),
                variant: OraChipVariant.status,
              ),
            ],
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            [
              if (pickup != null && pickup.isNotEmpty) pickup else 'Pickup',
              '→',
              if (drop != null && drop.isNotEmpty) drop else 'Destination',
            ].join(' '),
            style: OraTypography.body(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            [
              historyServiceTypeLabel(ride.serviceType),
              '·',
              ride.category,
              if (when != null) ...['·', when],
            ].join(' '),
            style: OraTypography.caption(OraColors.textMuted),
          ),
          if (fare != null) ...[
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Agreed fare $fare',
              style: OraTypography.caption(OraColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.state,
    required this.onLoadMore,
  });

  final RideHistoryUiState state;
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

    if (state.rides.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OraSpacing.md),
        child: Text(
          'End of list from server',
          textAlign: TextAlign.center,
          style: OraTypography.caption(OraColors.textMuted),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
