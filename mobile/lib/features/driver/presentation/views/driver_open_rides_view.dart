import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/models/ride_category_option.dart';
import '../../../ride/presentation/history/ride_history_display.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_assets.dart';
import '../../../ride/presentation/widgets/ride_card/ride_card_map_thumb.dart';
import '../open_ride_display.dart';
import '../view_models/driver_invites_view_model.dart';
import '../view_models/driver_open_rides_view_model.dart';
import '../widgets/driver_invites_section.dart';
import '../widgets/driver_ui_kit.dart';

/// Open ride requests — GET /v1/rides/open. Not nearby / GEO.
class DriverOpenRidesView extends ConsumerStatefulWidget {
  const DriverOpenRidesView({
    super.key,
    this.active = false,
    this.infoText =
        'Available ride requests from Ora\'s servers for approved drivers.',
    this.sheetTitle = 'New Ride Request',
    this.offerLabel = 'Passenger Offer',
    this.invitesSectionLabel = 'Ride requests for you',
  });

  final bool active;

  /// Copy overrides — logistics partners show delivery wording.
  final String infoText;
  final String sheetTitle;
  final String offerLabel;
  final String invitesSectionLabel;

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

  /// Pull-to-refresh resyncs the open list AND the invite feed — the invites
  /// otherwise depend solely on the DISPATCH_INVITE FCM nudge, so a missed or
  /// delayed push (or FCM-off local builds) would hide live invitations.
  Future<void> _refreshAll(DriverOpenRidesViewModel vm) async {
    unawaited(ref.read(driverInvitesViewModelProvider.notifier).refresh());
    await vm.refresh();
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
          child: _OpenRideOfferSheet(
            ride: ride,
            sheetTitle: widget.sheetTitle,
            offerLabel: widget.offerLabel,
          ),
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
      top: false,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: OraSpacing.sm,
                    vertical: OraSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: OraColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                    border: Border.all(color: OraColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: OraColors.goldSharp,
                      ),
                      const SizedBox(width: OraSpacing.xs),
                      Expanded(
                        child: Text(
                          widget.infoText,
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ),
                    ],
                  ),
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
                if (state.phase != DriverOpenRidesPhase.initialLoading) ...[
                  const SizedBox(height: OraSpacing.sm),
                  _OpenRidesFilterRow(
                    label: 'Service',
                    children: [
                      OraChip(
                        label: 'Any',
                        selected: state.serviceTypeFilter == null,
                        onTap: () => vm.setServiceTypeFilter(null),
                      ),
                      for (final type in rideHistoryServiceTypes)
                        OraChip(
                          label: historyServiceTypeLabel(type),
                          selected: state.serviceTypeFilter == type,
                          onTap: () => vm.setServiceTypeFilter(type),
                        ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  _OpenRidesFilterRow(
                    label: 'Category',
                    children: [
                      OraChip(
                        label: 'Any',
                        selected: state.categoryFilter == null,
                        onTap: () => vm.setCategoryFilter(null),
                      ),
                      for (final c in kRideCategoryOptions)
                        OraChip(
                          label: c.name,
                          selected: state.categoryFilter == c.id,
                          onTap: () => vm.setCategoryFilter(c.id),
                        ),
                    ],
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
      final filtered = state.hasActiveFilters;
      return RefreshIndicator(
        color: OraColors.primary,
        onRefresh: () => _refreshAll(vm),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: padding),
          children: [
            DriverInvitesSection(
              sectionLabel: widget.invitesSectionLabel,
              sheetTitle: widget.sheetTitle,
              offerLabel: widget.offerLabel,
            ),
            const SizedBox(height: OraSpacing.xxl),
            OraEmptyState(
              title: filtered ? 'No open rides match' : 'No open ride requests',
              message: filtered
                  ? 'No open ride requests match the selected filters. '
                        'Clear them or pull to refresh.'
                  : 'There are currently no open ride requests available. '
                        'Pull to refresh when you want to check again.',
            ),
            if (filtered) ...[
              const SizedBox(height: OraSpacing.md),
              Center(
                child: OraButton(
                  label: 'Clear filters',
                  variant: OraButtonVariant.outline,
                  onPressed: vm.clearFilters,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: () => _refreshAll(vm),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        scrollCacheExtent: const ScrollCacheExtent.pixels(480),
        padding: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.sm,
          padding,
          OraSpacing.xxl,
        ),
        itemCount:
            state.rides.length + 2 + (state.errorMessage != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: DriverInvitesSection(
                sectionLabel: widget.invitesSectionLabel,
                sheetTitle: widget.sheetTitle,
                offerLabel: widget.offerLabel,
              ),
            );
          }
          final shifted = index - 1;
          final hasSoftError = state.errorMessage != null;
          if (hasSoftError && shifted == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: Text(
                state.errorMessage!,
                style: OraTypography.caption(OraColors.dangerForeground),
              ),
            );
          }
          final rideIndex = hasSoftError ? shifted - 1 : shifted;
          if (rideIndex < state.rides.length) {
            final ride = state.rides[rideIndex];
            final offering = state.offeringRideId == ride.rideId;
            return Padding(
              key: ValueKey('open_ride_${ride.rideId}'),
              padding: const EdgeInsets.only(bottom: OraSpacing.sm),
              child: RideCard(
                model: RideCardAdapters.fromOpenRide(
                  ride,
                  offering: offering,
                  offerDisabled: state.isOffering,
                  onAccept: () => _openOfferSheet(ride),
                  onDecline: () => vm.dismissRideLocally(ride.rideId),
                  onTap: () => _openOfferSheet(ride),
                ),
              ),
            );
          }
          return _OpenPaginationFooter(state: state, onLoadMore: vm.loadMore);
        },
      ),
    );
  }
}

/// Labelled horizontal chip row — mirrors the ride-history filter rows.
class _OpenRidesFilterRow extends StatelessWidget {
  const _OpenRidesFilterRow({required this.label, required this.children});

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

class _OpenRideOfferSheet extends ConsumerStatefulWidget {
  const _OpenRideOfferSheet({
    required this.ride,
    required this.sheetTitle,
    required this.offerLabel,
  });

  final OpenRide ride;
  final String sheetTitle;
  final String offerLabel;

  @override
  ConsumerState<_OpenRideOfferSheet> createState() =>
      _OpenRideOfferSheetState();
}

class _OpenRideOfferSheetState extends ConsumerState<_OpenRideOfferSheet> {
  bool _counterMode = false;
  late final TextEditingController _amountController;
  Timer? _ticker;
  Duration? _remaining;
  Duration _window = Duration.zero;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: openRideOfferRupeesFieldText(widget.ride.passengerOfferMinor),
    );
    final expiresAt = DateTime.tryParse(widget.ride.expiresAt);
    if (expiresAt != null) {
      final left = expiresAt.difference(DateTime.now());
      if (left > Duration.zero) {
        _remaining = left;
        _window = left;
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          final next = expiresAt.difference(DateTime.now());
          if (!mounted) return;
          if (next <= Duration.zero) {
            _ticker?.cancel();
          }
          setState(() => _remaining = next);
        });
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool counter}) async {
    final amountMinor = counter
        ? parseOpenRideOfferRupeesToMinor(_amountController.text)
        : widget.ride.passengerOfferMinor;
    if (amountMinor == null) return;
    final vm = ref.read(driverOpenRidesViewModelProvider.notifier);
    await vm.submitOffer(
      ride: widget.ride,
      type: counter ? 'DRIVER_COUNTEROFFER' : 'PASSENGER_PRICE_ACCEPTED',
      amountMinor: amountMinor,
    );
    if (!mounted) return;
    final after = ref.read(driverOpenRidesViewModelProvider);
    final success =
        after.lastCreatedOffer?.rideId == widget.ride.rideId &&
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
    final distanceLabel = formatOpenRideDistanceKm(ride.distanceKm);
    final durationLabel = formatOpenRideDurationMin(ride.estimatedDurationMin);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DriverRequestSheetHeader(
              title: widget.sheetTitle,
              onBack: offering ? null : () => Navigator.of(context).pop(),
              trailing:
                  (_remaining != null && _remaining! > Duration.zero)
                  ? DriverCountdownRing(
                      remaining: _remaining!,
                      total: _window,
                      bright: true,
                    )
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OraSpacing.lg,
                OraSpacing.sm,
                OraSpacing.lg,
                OraSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RideCardMapBanner(
                    pickupLat: ride.pickup.lat,
                    pickupLng: ride.pickup.lng,
                    destinationLat: ride.destination.lat,
                    destinationLng: ride.destination.lng,
                    height: 118,
                    carAssetPath: RideCardAssets.carWhite,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  DriverRouteCard(
                    pickupLabel: rideCardLocationLabel(ride.pickup),
                    destinationLabel: rideCardLocationLabel(ride.destination),
                    pickupCaption: distanceLabel != null
                        ? 'Pickup ($distanceLabel)'
                        : 'Pickup',
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Row(
                    children: [
                      if (distanceLabel != null) ...[
                        DriverStatPill(
                          icon: Icons.route_rounded,
                          label: distanceLabel,
                        ),
                        const SizedBox(width: OraSpacing.xs),
                      ],
                      if (durationLabel != null) ...[
                        DriverStatPill(
                          icon: Icons.schedule_rounded,
                          label: durationLabel,
                        ),
                        const SizedBox(width: OraSpacing.xs),
                      ],
                      DriverStatPill(
                        icon: Icons.directions_car_rounded,
                        label: ride.paymentMethod,
                      ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  DriverOfferCard(
                    label: widget.offerLabel,
                    amountLabel: formatOpenRideFareMinor(
                      ride.passengerOfferMinor,
                    ),
                    onEdit: offering
                        ? null
                        : () => setState(() => _counterMode = !_counterMode),
                    trailing: Image.asset(
                      'assets/driver_tiles/wallet_3d.png',
                      width: 56,
                      height: 56,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  if (_counterMode) ...[
                    const SizedBox(height: OraSpacing.md),
                    OraTextField(
                      controller: _amountController,
                      label: 'Your offer',
                      hint: 'Amount in PKR',
                      keyboardType: TextInputType.number,
                      enabled: !offering,
                    ),
                  ],
                  if (state.offerErrorMessage != null) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      state.offerErrorMessage!,
                      style: OraTypography.caption(OraColors.dangerForeground),
                    ),
                  ],
                  const SizedBox(height: OraSpacing.lg),
                  if (_counterMode)
                    DriverActionButton(
                      label: 'Submit counteroffer',
                      isLoading: offering,
                      onPressed: offering ? null : () => _submit(counter: true),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: DriverActionButton.accept(
                            label: 'Accept',
                            isLoading: offering,
                            onPressed: offering
                                ? null
                                : () => _submit(counter: false),
                          ),
                        ),
                        const SizedBox(width: OraSpacing.sm),
                        Expanded(
                          child: DriverActionButton.decline(
                            label: 'Decline',
                            onPressed: offering
                                ? null
                                : () {
                                    ref
                                        .read(
                                          driverOpenRidesViewModelProvider
                                              .notifier,
                                        )
                                        .dismissRideLocally(ride.rideId);
                                    Navigator.of(context).pop();
                                  },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenPaginationFooter extends StatelessWidget {
  const _OpenPaginationFooter({required this.state, required this.onLoadMore});

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
