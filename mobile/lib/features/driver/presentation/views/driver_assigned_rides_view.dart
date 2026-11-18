import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_assets.dart';
import '../../domain/driver_earnings_summary.dart';
import '../driver_display.dart';
import '../view_models/driver_assigned_rides_view_model.dart';
import '../widgets/driver_ui_kit.dart';

/// Driver "My rides" — Active / Completed tabs over the
/// server ride list (GET /v1/rides). Client-side bucketing only; the list
/// is never fabricated.
class DriverAssignedRidesView extends ConsumerStatefulWidget {
  const DriverAssignedRidesView({
    super.key,
    this.active = false,
    this.ridePathFor = AppRoutes.driverRidePath,
    this.jobSingular = 'ride',
    this.jobPlural = 'rides',
  });

  final bool active;

  /// Detail-route builder — logistics partners push their own shell-scoped
  /// delivery detail route.
  final String Function(String rideId) ridePathFor;

  /// Empty-state nouns — 'ride(s)' for drivers, 'delivery/deliveries' for
  /// logistics.
  final String jobSingular;
  final String jobPlural;

  @override
  ConsumerState<DriverAssignedRidesView> createState() =>
      _DriverAssignedRidesViewState();
}

enum _BookingTab { active, completed }

class _DriverAssignedRidesViewState
    extends ConsumerState<DriverAssignedRidesView> {
  bool _initialLoadRequested = false;
  _BookingTab _tab = _BookingTab.active;

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

  bool _isCompleted(Ride ride) => isDriverEarningsCompletedState(ride.state);

  bool _isActive(Ride ride) =>
      !_isCompleted(ride) && !isDriverJobTerminalState(ride.state);

  List<Ride> _bucket(List<Ride> rides) => switch (_tab) {
    _BookingTab.active => rides.where(_isActive).toList(),
    _BookingTab.completed => rides.where(_isCompleted).toList(),
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_initialLoadRequested) {
      return const SizedBox.expand();
    }

    final state = ref.watch(driverAssignedRidesViewModelProvider);
    final vm = ref.read(driverAssignedRidesViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);
    final activeCount = state.rides.where(_isActive).length;
    final tabRides = _bucket(state.rides);

    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              OraSpacing.sm,
              padding,
              OraSpacing.sm,
            ),
            child: DriverSegmentedTabs(
              tabs: ['Active ($activeCount)', 'Completed'],
              selectedIndex: _tab.index,
              onSelected: (i) => setState(() => _tab = _BookingTab.values[i]),
            ),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Text(
                state.errorMessage!,
                style: OraTypography.caption(OraColors.dangerForeground),
              ),
            ),
          Expanded(
            child: _Body(
              state: state,
              tab: _tab,
              rides: tabRides,
              jobSingular: widget.jobSingular,
              jobPlural: widget.jobPlural,
              ridePathFor: widget.ridePathFor,
              onLoadMore: vm.loadMore,
              onRefresh: vm.refresh,
              onRetry: vm.retry,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.tab,
    required this.rides,
    required this.jobSingular,
    required this.jobPlural,
    required this.ridePathFor,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onRetry,
  });

  final DriverAssignedRidesUiState state;
  final _BookingTab tab;
  final List<Ride> rides;
  final String jobSingular;
  final String jobPlural;
  final String Function(String rideId) ridePathFor;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    if (state.phase == DriverAssignedRidesPhase.initialLoading) {
      return const Center(
        child: OraLoadingIndicator(message: 'Loading rides…'),
      );
    }

    if (state.phase == DriverAssignedRidesPhase.fatalError) {
      return OraErrorState(
        title: 'Couldn’t load rides',
        message: state.errorMessage ?? 'Something went wrong.',
        onRetry: onRetry,
      );
    }

    if (rides.isEmpty) {
      return RefreshIndicator(
        color: OraColors.primary,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(padding),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            OraEmptyState(
              title: switch (tab) {
                _BookingTab.active => 'No active $jobPlural',
                _BookingTab.completed => 'No completed $jobPlural',
              },
              message: switch (tab) {
                _BookingTab.active =>
                  'When you are assigned to a $jobSingular, it will appear '
                      'here from the server.',
                _BookingTab.completed =>
                  '${jobPlural[0].toUpperCase()}${jobPlural.substring(1)} '
                      'you complete will appear here from the server.',
              },
              icon: Icons.assignment_outlined,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        cacheExtent: 480,
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        itemCount: rides.length + 1,
        itemBuilder: (context, index) {
          if (index < rides.length) {
            final ride = rides[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: _BookingCard(
                ride: ride,
                onTap: () => context.push(ridePathFor(ride.rideId)),
              ),
            );
          }
          return _PaginationFooter(state: state, onLoadMore: onLoadMore);
        },
      ),
    );
  }
}

/// Booking card — 3D car art, route, date, fare + status pill.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.ride, required this.onTap});

  final Ride ride;
  final VoidCallback onTap;

  String? _bookedAt() {
    for (final iso in [ride.createdAt, ride.updatedAt]) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) return _formatBookingDate(parsed.toLocal());
    }
    return null;
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatBookingDate(DateTime d) {
    final day = d.day;
    final month = _months[d.month - 1];
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour < 12 ? 'AM' : 'PM';
    return '$day $month, $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final completed = isDriverEarningsCompletedState(ride.state);
    final cancelled = ride.state.toUpperCase() == 'CANCELLED';
    final fare = formatMinorFare(
      ride.agreedFareMinor ?? ride.driverPayoutMinor,
      ride.agreedFareCurrency ?? ride.payoutCurrency,
    );
    final pickup = rideCardLocationLabel(ride.pickup);
    final destination = rideCardLocationLabel(ride.destination);
    final bookedAt = _bookedAt();

    return OraCard(
      onTap: onTap,
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: OraColors.primaryMuted,
                  borderRadius: BorderRadius.circular(OraRadius.sm),
                ),
                alignment: Alignment.center,
                child: const RideCardAssetImage(
                  assetPath: RideCardAssets.carWhite,
                  width: 34,
                  height: 24,
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$pickup → $destination',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.bodyEmphasis(
                        OraColors.textPrimary,
                      ).copyWith(fontSize: 14),
                    ),
                    if (bookedAt != null)
                      Text(
                        bookedAt,
                        style: OraTypography.caption(
                          OraColors.textMuted,
                        ).copyWith(fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              if (fare != null)
                Text(
                  fare,
                  style: OraTypography.bodyEmphasis(
                    OraColors.textPrimary,
                  ).copyWith(fontSize: 14),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          Row(
            children: [
              _BookingStatusPill(
                ride: ride,
                completed: completed,
                cancelled: cancelled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingStatusPill extends StatelessWidget {
  const _BookingStatusPill({
    required this.ride,
    required this.completed,
    required this.cancelled,
  });

  final Ride ride;
  final bool completed;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = completed
        ? ('Completed', OraColors.successSurface, OraColors.successForeground)
        : cancelled || isDriverJobTerminalState(ride.state)
        ? (
            driverJobTitle(ride.state, courier: ride.isDelivery),
            OraColors.errorSurface,
            OraColors.dangerForeground,
          )
        : (
            driverJobTitle(ride.state, courier: ride.isDelivery),
            OraColors.primaryMuted,
            OraColors.goldDeep,
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(OraRadius.pill),
      ),
      child: Text(
        label,
        style: OraTypography.caption(
          fg,
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.state, required this.onLoadMore});

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
