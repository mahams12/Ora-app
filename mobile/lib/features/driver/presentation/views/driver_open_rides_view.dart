import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../open_ride_display.dart';
import '../view_models/driver_direct_offer_view_model.dart';
import '../view_models/driver_open_rides_view_model.dart';

/// Open ride requests — GET /v1/rides/open. Not nearby / GEO.
class DriverOpenRidesView extends ConsumerStatefulWidget {
  const DriverOpenRidesView({super.key, this.active = false});

  final bool active;

  @override
  ConsumerState<DriverOpenRidesView> createState() =>
      _DriverOpenRidesViewState();
}

class _DriverOpenRidesViewState extends ConsumerState<DriverOpenRidesView> {
  bool _initialLoadRequested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadInitial();
  }

  @override
  void didUpdateWidget(DriverOpenRidesView oldWidget) {
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
      ref.read(driverOpenRidesViewModelProvider.notifier).loadInitial();
    });
  }

  Future<void> _openOfferSheet(OpenRide ride) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: _OpenRideOfferSheet(ride: ride),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_initialLoadRequested) {
      return const SizedBox.expand();
    }

    final state = ref.watch(driverOpenRidesViewModelProvider);
    final vm = ref.read(driverOpenRidesViewModelProvider.notifier);
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
                  'Open rides',
                  style: OraTypography.headline(OraColors.textPrimary),
                ),
                const SizedBox(height: OraSpacing.xxs),
                Text(
                  'Available ride requests from Ora\'s servers for approved '
                  'drivers. Not a GPS or map-radius feed.',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
                if (state.offerInfoMessage != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    state.offerInfoMessage!,
                    style: OraTypography.caption(OraColors.textPrimary),
                  ),
                ],
                if (state.offerErrorMessage != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    state.offerErrorMessage!,
                    style: OraTypography.caption(OraColors.dangerForeground),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body(context, state, vm, padding)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    DriverOpenRidesUiState state,
    DriverOpenRidesViewModel vm,
    double padding,
  ) {
    if (state.phase == DriverOpenRidesPhase.initialLoading) {
      return const Center(child: OraLoadingIndicator());
    }

    if (state.phase == DriverOpenRidesPhase.fatalError) {
      return OraErrorState(
        title: 'Could not load open rides',
        message: state.errorMessage,
        onRetry: vm.retry,
      );
    }

    if (state.phase == DriverOpenRidesPhase.empty) {
      return RefreshIndicator(
        color: OraColors.primary,
        onRefresh: vm.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: padding),
          children: const [
            SizedBox(height: OraSpacing.xxl),
            OraEmptyState(
              title: 'No open ride requests',
              message:
                  'There are currently no open ride requests available. '
                  'Pull to refresh when you want to check again.',
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
            final offering = state.offeringRideId == ride.rideId;
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: _OpenRideCard(
                ride: ride,
                offering: offering,
                offerDisabled: state.isOffering,
                onOffer: () => _openOfferSheet(ride),
              ),
            );
          }
          return _OpenPaginationFooter(state: state, onLoadMore: vm.loadMore);
        },
      ),
    );
  }
}

class _OpenRideCard extends StatelessWidget {
  const _OpenRideCard({
    required this.ride,
    required this.offering,
    required this.offerDisabled,
    required this.onOffer,
  });

  final OpenRide ride;
  final bool offering;
  final bool offerDisabled;
  final VoidCallback onOffer;

  @override
  Widget build(BuildContext context) {
    final pickup = openRideLocationLabel(ride.pickup, fallback: 'Pickup');
    final drop =
        openRideLocationLabel(ride.destination, fallback: 'Destination');
    final created = formatHistoryTimestamp(ride.createdAt);
    final expires = openRideExpiresLabel(ride.expiresAt);
    final distance = formatOpenRideDistanceKm(ride.distanceKm);
    final duration = formatOpenRideDurationMin(ride.estimatedDurationMin);

    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ride request',
                  style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                ),
              ),
              OraChip(
                label: openRideStateLabel(ride.state),
                selected: true,
                variant: OraChipVariant.status,
              ),
            ],
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            '$pickup → $drop',
            style: OraTypography.body(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            [
              openRideServiceLine(ride),
              '·',
              '${ride.passengerCount} passenger'
                  '${ride.passengerCount == 1 ? '' : 's'}',
              '·',
              ride.paymentMethod,
            ].join(' '),
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            'Passenger offer ${formatOpenRideFareMinor(ride.passengerOfferMinor)}',
            style: OraTypography.caption(OraColors.textPrimary),
          ),
          Text(
            'Recommended ${formatOpenRideFareMinor(ride.recommendedFareMinor)}',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          if (distance != null || duration != null) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              [
                if (distance != null) distance,
                if (duration != null) duration,
              ].join(' · '),
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          if (created != null || expires != null) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              [
                if (created != null) 'Requested $created',
                if (expires != null) expires,
              ].join(' · '),
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: offering ? 'Submitting…' : 'Respond',
            isLoading: offering,
            onPressed: offerDisabled ? null : onOffer,
          ),
        ],
      ),
    );
  }
}

class _OpenRideOfferSheet extends ConsumerStatefulWidget {
  const _OpenRideOfferSheet({required this.ride});

  final OpenRide ride;

  @override
  ConsumerState<_OpenRideOfferSheet> createState() =>
      _OpenRideOfferSheetState();
}

class _OpenRideOfferSheetState extends ConsumerState<_OpenRideOfferSheet> {
  late String _type;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _type = 'PASSENGER_PRICE_ACCEPTED';
    _amountController = TextEditingController(
      text: '${widget.ride.passengerOfferMinor}',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;
    final vm = ref.read(driverOpenRidesViewModelProvider.notifier);
    await vm.submitOffer(
      ride: widget.ride,
      type: _type,
      amountMinor: amount,
    );
    if (!mounted) return;
    final after = ref.read(driverOpenRidesViewModelProvider);
    final success = after.lastCreatedOffer?.rideId == widget.ride.rideId &&
        after.offerErrorMessage == null;
    final removed = !after.rides.any((r) => r.rideId == widget.ride.rideId);
    if (success || removed) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driverOpenRidesViewModelProvider);
    final offering = state.offeringRideId == widget.ride.rideId;
    final ride = widget.ride;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Submit offer',
              style: OraTypography.headline(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Uses POST /v1/rides/:rideId/offers with this request\'s '
              'server requestVersion (${ride.requestVersion}).',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.md),
            Wrap(
              spacing: OraSpacing.xs,
              runSpacing: OraSpacing.xs,
              children: [
                for (final type in driverOfferTypes)
                  OraChip(
                    label: type == 'PASSENGER_PRICE_ACCEPTED'
                        ? 'Accept passenger price'
                        : 'Counteroffer',
                    selected: _type == type,
                    onTap: offering
                        ? null
                        : () {
                            setState(() {
                              _type = type;
                              if (type == 'PASSENGER_PRICE_ACCEPTED') {
                                _amountController.text =
                                    '${ride.passengerOfferMinor}';
                              }
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: OraSpacing.md),
            OraTextField(
              controller: _amountController,
              label: 'Amount (minor units)',
              hint: 'Server minor units — enter explicitly',
              keyboardType: TextInputType.number,
              enabled: !offering,
            ),
            const SizedBox(height: OraSpacing.sm),
            Text(
              'Passenger offer on request: '
              '${formatOpenRideFareMinor(ride.passengerOfferMinor)}. '
              'Ora ride money is PKR (paisas). Offer response also returns currency.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            if (state.offerErrorMessage != null) ...[
              const SizedBox(height: OraSpacing.sm),
              Text(
                state.offerErrorMessage!,
                style: OraTypography.caption(OraColors.dangerForeground),
              ),
            ],
            const SizedBox(height: OraSpacing.lg),
            OraButton(
              label: 'Submit offer',
              isLoading: offering,
              onPressed: offering ? null : _submit,
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(
              label: 'Cancel',
              variant: OraButtonVariant.ghost,
              onPressed: offering ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenPaginationFooter extends StatelessWidget {
  const _OpenPaginationFooter({
    required this.state,
    required this.onLoadMore,
  });

  final DriverOpenRidesUiState state;
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
          'End of open rides from server',
          textAlign: TextAlign.center,
          style: OraTypography.caption(OraColors.textMuted),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
