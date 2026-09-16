import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../driver_display.dart';
import '../view_models/driver_assigned_rides_view_model.dart';

/// Driver assigned rides / history — GET /v1/rides, not a marketplace.
class DriverAssignedRidesView extends ConsumerStatefulWidget {
  const DriverAssignedRidesView({super.key, this.active = false});

  final bool active;

  @override
  ConsumerState<DriverAssignedRidesView> createState() =>
      _DriverAssignedRidesViewState();
}

class _DriverAssignedRidesViewState
    extends ConsumerState<DriverAssignedRidesView> {
  bool _initialLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadInitial();
  }

  @override
  void didUpdateWidget(DriverAssignedRidesView oldWidget) {
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
      ref.read(driverAssignedRidesViewModelProvider.notifier).loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_initialLoadRequested) {
      return const SizedBox.expand();
    }

    final state = ref.watch(driverAssignedRidesViewModelProvider);
    final vm = ref.read(driverAssignedRidesViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    return SafeArea(
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
                  'Assigned rides',
                  style: OraTypography.headline(OraColors.textPrimary),
                ),
                const SizedBox(height: OraSpacing.xxs),
                Text(
                  'Jobs from Ora\'s servers for your approved driver account. '
                  'This is assigned rides / history — not a marketplace browse.',
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
          Expanded(child: _Body(state: state)),
        ],
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
  const _Body({required this.state});

  final DriverAssignedRidesUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(driverAssignedRidesViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    if (state.phase == DriverAssignedRidesPhase.initialLoading) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading assigned rides…'),
      );
    }

    if (state.phase == DriverAssignedRidesPhase.fatalError) {
      return OraErrorState(
        title: 'Couldn’t load rides',
        message: state.errorMessage ?? 'Something went wrong.',
        onRetry: vm.retry,
      );
    }

    if (state.phase == DriverAssignedRidesPhase.empty) {
      return RefreshIndicator(
        color: OraColors.primary,
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(padding),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            OraEmptyState(
              title: 'No assigned rides',
              message: state.status == 'all'
                  ? 'When you are assigned to a ride, it will appear here from '
                      'the server. This list is not a live marketplace.'
                  : 'No rides match this filter on the server.',
              icon: Icons.assignment_outlined,
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
        itemCount:
            state.rides.length + 1 + (state.errorMessage != null ? 1 : 0),
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
              child: _AssignedRideCard(
                ride: ride,
                onTap: () =>
                    context.push(AppRoutes.driverRidePath(ride.rideId)),
              ),
            );
          }
          return _PaginationFooter(state: state, onLoadMore: vm.loadMore);
        },
      ),
    );
  }
}

class _AssignedRideCard extends StatelessWidget {
  const _AssignedRideCard({required this.ride, required this.onTap});

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
                  driverJobTitle(ride.state),
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
              ),
              OraChip(
                label: ride.state,
                selected: !isDriverJobTerminalState(ride.state),
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

  final DriverAssignedRidesUiState state;
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
