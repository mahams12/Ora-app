import 'dart:async';

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
import '../offers/offer_display.dart';
import '../view_models/offers_inbox_view_model.dart';
import '../widgets/offer_card.dart';

/// Passenger offers inbox — HTTP-polled, server-authoritative.
class OffersInboxView extends ConsumerStatefulWidget {
  const OffersInboxView({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<OffersInboxView> createState() => _OffersInboxViewState();
}

class _OffersInboxViewState extends ConsumerState<OffersInboxView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vm = ref.read(offersInboxViewModelProvider(widget.rideId).notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(vm.resumePolling());
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        vm.pausePolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rideId = widget.rideId;
    final phase = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.phase),
    );
    final isRefreshing = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.isRefreshing),
    );
    final canRefresh = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.canRefresh),
    );
    final errorMessage = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.errorMessage),
    );
    final vm = ref.read(offersInboxViewModelProvider(rideId).notifier);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(
        backgroundColor: OraColors.background,
        title: Text(
          'Offers',
          style: OraTypography.title(OraColors.textPrimary),
        ),
        leading: IconButton(
          tooltip: 'Back to Home',
          onPressed: () => context.go(AppRoutes.home),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          if (phase == OffersInboxPhase.ready)
            IconButton(
              tooltip: 'Refresh',
              onPressed: (!canRefresh || isRefreshing) ? null : () => vm.refresh(),
              icon: isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (phase) {
          OffersInboxPhase.initialLoading => const Center(
              child: OraLoadingIndicator(message: 'Loading offers…'),
            ),
          OffersInboxPhase.fatalError => OraErrorState(
              title: 'Could not load offers',
              message: errorMessage ?? 'Something went wrong.',
              onRetry: () => vm.start(),
            ),
          OffersInboxPhase.assigned => _AssignedPane(
              rideId: rideId,
              padding: padding,
              onOpenActiveRide: () =>
                  context.go(AppRoutes.activeRidePath(rideId)),
              onHome: () => context.go(AppRoutes.home),
            ),
          OffersInboxPhase.terminal => _TerminalPane(
              rideId: rideId,
              padding: padding,
              onHome: () => context.go(AppRoutes.home),
            ),
          OffersInboxPhase.ready || OffersInboxPhase.selecting => _OffersBody(
              rideId: rideId,
              padding: padding,
              onSelect: vm.selectOffer,
              onRefresh: canRefresh ? () => vm.refresh() : () async {},
            ),
        },
      ),
    );
  }
}

class _OffersBody extends ConsumerWidget {
  const _OffersBody({
    required this.rideId,
    required this.padding,
    required this.onSelect,
    required this.onRefresh,
  });

  final String rideId;
  final double padding;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.phase),
    );
    final offers = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.offers),
    );
    final selectingOfferId = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.selectingOfferId),
    );
    final isPolling = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.isPolling),
    );
    final errorMessage = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.errorMessage),
    );
    final infoMessage = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.infoMessage),
    );
    final ride = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.ride),
    );

    return RefreshIndicator(
      color: OraColors.primary,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding,
              OraSpacing.sm,
              padding,
              OraSpacing.xxl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _RideContextHeader(ride: ride),
                if (errorMessage != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    errorMessage,
                    style: OraTypography.caption(OraColors.dangerForeground),
                  ),
                ],
                if (infoMessage != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    infoMessage,
                    style: OraTypography.caption(OraColors.goldSoft),
                  ),
                ],
                const SizedBox(height: OraSpacing.md),
                if (offers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: OraSpacing.xl),
                    child: OraEmptyState(
                      icon: Icons.hourglass_top_rounded,
                      title: 'Waiting for offers',
                      message:
                          'Your request is live on Ora. New offers will appear '
                          'here when drivers respond. We are not inventing '
                          'nearby drivers.',
                    ),
                  )
                else ...[
                  OraSectionHeader(
                    title: 'Offers',
                    action: Text(
                      '${offers.length}',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  for (final offer in offers) ...[
                    OfferCard(
                      key: ValueKey(offer.offerId),
                      offer: offer,
                      isSelecting: selectingOfferId == offer.offerId,
                      enabled: phase != OffersInboxPhase.selecting,
                      onSelect: () => onSelect(offer.offerId),
                    ),
                    const SizedBox(height: OraSpacing.sm),
                  ],
                ],
                if (isPolling)
                  Padding(
                    padding: const EdgeInsets.only(top: OraSpacing.md),
                    child: Text(
                      'Checking for updates…',
                      textAlign: TextAlign.center,
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _RideContextHeader extends StatelessWidget {
  const _RideContextHeader({required this.ride});

  final Ride? ride;

  @override
  Widget build(BuildContext context) {
    final current = ride;
    return OraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ride request',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            current?.state ?? '…',
            style: OraTypography.bodyEmphasis(OraColors.primary),
          ),
          if (current != null) ...[
            const SizedBox(height: OraSpacing.xs),
            Text(
              '${current.pickup.address ?? 'Pickup'} → '
              '${current.destination.address ?? 'Destination'}',
              style: OraTypography.caption(OraColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Category ${current.category}',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignedPane extends ConsumerWidget {
  const _AssignedPane({
    required this.rideId,
    required this.padding,
    required this.onOpenActiveRide,
    required this.onHome,
  });

  final String rideId;
  final double padding;
  final VoidCallback onOpenActiveRide;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.assignment),
    );
    final rideState = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.rideState),
    );
    final fare = assignment == null
        ? null
        : formatOfferAmountMinor(
            assignment.agreedFareMinor,
            assignment.currency,
          );

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const OraEmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'Driver assigned',
            message:
                'Ora selected an offer on the server. Open the active ride to '
                'follow server status updates — this is not a fake map or ETA.',
          ),
          const SizedBox(height: OraSpacing.lg),
          OraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server state',
                  style: OraTypography.label(OraColors.textSecondary),
                ),
                Text(
                  assignment?.state ?? rideState,
                  style: OraTypography.bodyEmphasis(OraColors.primary),
                ),
                if (fare != null) ...[
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    'Agreed fare $fare',
                    style: OraTypography.body(OraColors.textPrimary),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          OraButton(
            label: 'Open active ride',
            onPressed: onOpenActiveRide,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Back to Home',
            variant: OraButtonVariant.ghost,
            onPressed: onHome,
          ),
        ],
      ),
    );
  }
}

class _TerminalPane extends ConsumerWidget {
  const _TerminalPane({
    required this.rideId,
    required this.padding,
    required this.onHome,
  });

  final String rideId;
  final double padding;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(
      offersInboxViewModelProvider(rideId).select((s) => s.rideState),
    );
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          OraEmptyState(
            icon: Icons.info_outline_rounded,
            title: 'Request ended',
            message:
                'This ride is now "$label" on Ora\'s servers. Offers are no '
                'longer available for this request.',
          ),
          const Spacer(),
          OraButton(label: 'Back to Home', onPressed: onHome),
        ],
      ),
    );
  }
}

