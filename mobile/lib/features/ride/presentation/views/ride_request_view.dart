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
import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/models/ride_category_option.dart';
import '../view_models/ride_request_view_model.dart';
import '../widgets/ride_category_selector.dart';
import '../widgets/ride_location_placeholder.dart';

/// Passenger ride compose + review. Create gated without pricing (Phase 5).
class RideRequestView extends ConsumerStatefulWidget {
  const RideRequestView({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  ConsumerState<RideRequestView> createState() => _RideRequestViewState();
}

class _RideRequestViewState extends ConsumerState<RideRequestView> {
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController();
    _destinationController = TextEditingController();
    final category = widget.initialCategoryId;
    if (category != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(rideRequestViewModelProvider.notifier).seedCategory(category);
      });
    }
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _showGateSheet(String title, String message) {
    return showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OraSectionHeader(
            eyebrow: 'Ride request',
            title: title,
            description: message,
          ),
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'OK',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rideRequestViewModelProvider);
    final vm = ref.read(rideRequestViewModelProvider.notifier);
    final padding = Responsive.horizontalPadding(context);

    // Keep text controllers aligned when VM sets labels (GPS / place select).
    ref.listen(rideRequestViewModelProvider, (prev, next) {
      if (prev?.pickupText != next.pickupText &&
          _pickupController.text != next.pickupText) {
        _pickupController.value = TextEditingValue(
          text: next.pickupText,
          selection: TextSelection.collapsed(offset: next.pickupText.length),
        );
      }
      if (prev?.destinationText != next.destinationText &&
          _destinationController.text != next.destinationText) {
        _destinationController.value = TextEditingValue(
          text: next.destinationText,
          selection:
              TextSelection.collapsed(offset: next.destinationText.length),
        );
      }

      if (next.phase == RideRequestPhase.created && next.createdRide != null) {
        final rideId = next.createdRide!.rideId;
        context.go(AppRoutes.offersInboxPath(rideId));
        return;
      }
      if (next.phase == RideRequestPhase.blocked &&
          next.blockReason != null &&
          prev?.phase != RideRequestPhase.blocked) {
        final reason = next.blockReason!;
        final title = switch (reason) {
          RideRequestBlockReason.incomplete => 'Almost there',
          RideRequestBlockReason.pricingUnavailable => 'Pricing unavailable',
          RideRequestBlockReason.locationUnavailable => 'Location unavailable',
        };
        _showGateSheet(title, vm.messageFor(reason)).then((_) {
          if (mounted) vm.clearBlocked();
        });
      }
    });

    return Scaffold(
      backgroundColor: OraColors.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            RideLocationPlaceholder(
              pickupConfirmed: state.hasConfirmedPickup,
              destinationConfirmed: state.hasConfirmedDestination,
              onBack: () {
                if (state.phase == RideRequestPhase.review) {
                  vm.goToCompose();
                } else if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(AppRoutes.home);
                }
              },
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: OraColors.surfaceElevated,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(OraRadius.xxl),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: state.phase == RideRequestPhase.submitting
                      ? const Center(
                          child: OraLoadingIndicator(
                            message: 'Sending your request…',
                          ),
                        )
                      : state.phase == RideRequestPhase.error
                          ? OraErrorState(
                              title: 'Request failed',
                              message: state.errorMessage ??
                                  'Something went wrong. Please try again.',
                              onRetry: vm.retryAfterError,
                            )
                          : state.phase == RideRequestPhase.review
                              ? _ReviewPane(
                                  state: state,
                                  padding: padding,
                                  onSelectCategory: vm.selectCategory,
                                  onEditLocations: vm.goToCompose,
                                  onSubmit: vm.submit,
                                  onPaymentChange: () => _showGateSheet(
                                    'Payments',
                                    'Wallet and online payment are not '
                                        'available in this build. Cash remains '
                                        'the only honest option.',
                                  ),
                                )
                              : _ComposePane(
                                  state: state,
                                  padding: padding,
                                  pickupController: _pickupController,
                                  destinationController:
                                      _destinationController,
                                  onPickupChanged: vm.setPickupText,
                                  onDestinationChanged: vm.setDestinationText,
                                  onUseCurrentLocation:
                                      vm.useCurrentLocationForPickup,
                                  onSelectPickupSuggestion: (s) =>
                                      vm.selectPlaceSuggestion(
                                    field: LocationField.pickup,
                                    suggestion: s,
                                  ),
                                  onSelectDestinationSuggestion: (s) =>
                                      vm.selectPlaceSuggestion(
                                    field: LocationField.destination,
                                    suggestion: s,
                                  ),
                                  onConfirmPickup: vm.confirmPickup,
                                  onConfirmDestination: vm.confirmDestination,
                                  onContinue: vm.goToReview,
                                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposePane extends StatelessWidget {
  const _ComposePane({
    required this.state,
    required this.padding,
    required this.pickupController,
    required this.destinationController,
    required this.onPickupChanged,
    required this.onDestinationChanged,
    required this.onUseCurrentLocation,
    required this.onSelectPickupSuggestion,
    required this.onSelectDestinationSuggestion,
    required this.onConfirmPickup,
    required this.onConfirmDestination,
    required this.onContinue,
  });

  final RideRequestUiState state;
  final double padding;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDestinationChanged;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<PlaceSuggestion> onSelectPickupSuggestion;
  final ValueChanged<PlaceSuggestion> onSelectDestinationSuggestion;
  final VoidCallback onConfirmPickup;
  final VoidCallback onConfirmDestination;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding,
              OraSpacing.lg,
              padding,
              OraSpacing.md + bottomInset,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OraColors.border,
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: OraSpacing.md),
              Text(
                'Where to?',
                style: OraTypography.headline(OraColors.textPrimary),
              ),
              const SizedBox(height: OraSpacing.xxs),
              Text(
                'Search a place or use your current location. Confirm each '
                'point before continuing — text alone is not enough.',
                style: OraTypography.caption(OraColors.textMuted),
              ),
              const SizedBox(height: OraSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: OraColors.tealBright,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 52,
                          color: OraColors.border,
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: OraColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: OraSpacing.sm),
                  Expanded(
                    child: Column(
                      children: [
                        OraTextField(
                          controller: pickupController,
                          label: 'Pickup',
                          hint: 'Search pickup place',
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.radio_button_checked,
                          onChanged: onPickupChanged,
                        ),
                        const SizedBox(height: OraSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed:
                                state.pickupBusy ? null : onUseCurrentLocation,
                            icon: const Icon(Icons.my_location, size: 18),
                            label: const Text('Use current location'),
                          ),
                        ),
                        if (state.pickupBusy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: OraSpacing.xs),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (state.pickupLookupError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: OraSpacing.xs),
                            child: Text(
                              state.pickupLookupError!,
                              style: OraTypography.caption(OraColors.danger),
                            ),
                          ),
                        ...state.pickupSuggestions.map(
                          (s) => OraListRow(
                            title: s.primaryText,
                            subtitle: s.secondaryText,
                            leading: const Icon(
                              Icons.place_outlined,
                              color: OraColors.tealBright,
                              size: 20,
                            ),
                            onTap: () => onSelectPickupSuggestion(s),
                            showDivider: true,
                          ),
                        ),
                        if (state.proposedPickup != null &&
                            !state.hasConfirmedPickup)
                          _ProposalCard(
                            title: 'Confirm pickup',
                            location: state.proposedPickup!,
                            onConfirm: onConfirmPickup,
                          ),
                        const SizedBox(height: OraSpacing.sm),
                        OraTextField(
                          controller: destinationController,
                          label: 'Destination',
                          hint: 'Search destination',
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.location_on_outlined,
                          onChanged: onDestinationChanged,
                        ),
                        if (state.destinationBusy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: OraSpacing.xs),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (state.destinationLookupError != null)
                          Padding(
                            padding: const EdgeInsets.only(
                              top: OraSpacing.xs,
                              bottom: OraSpacing.xs,
                            ),
                            child: Text(
                              state.destinationLookupError!,
                              style: OraTypography.caption(OraColors.danger),
                            ),
                          ),
                        ...state.destinationSuggestions.map(
                          (s) => OraListRow(
                            title: s.primaryText,
                            subtitle: s.secondaryText,
                            leading: const Icon(
                              Icons.flag_outlined,
                              color: OraColors.primary,
                              size: 20,
                            ),
                            onTap: () => onSelectDestinationSuggestion(s),
                            showDivider: true,
                          ),
                        ),
                        if (state.proposedDestination != null &&
                            !state.hasConfirmedDestination)
                          _ProposalCard(
                            title: 'Confirm destination',
                            location: state.proposedDestination!,
                            onConfirm: onConfirmDestination,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.sm),
              _StatusChip(
                label: state.hasConfirmedPickup
                    ? 'Pickup confirmed'
                    : state.proposedPickup != null
                        ? 'Pickup selected · confirm needed'
                        : 'Pickup needed',
                ok: state.hasConfirmedPickup,
              ),
              const SizedBox(height: OraSpacing.xs),
              _StatusChip(
                label: state.hasConfirmedDestination
                    ? 'Destination confirmed'
                    : state.proposedDestination != null
                        ? 'Destination selected · confirm needed'
                        : 'Destination needed',
                ok: state.hasConfirmedDestination,
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            OraSpacing.sm,
            padding,
            OraSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: OraButton(
            label: 'Continue',
            onPressed: state.canAdvanceToReview ? onContinue : null,
          ),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.title,
    required this.location,
    required this.onConfirm,
  });

  final String title;
  final ResolvedPassengerLocation location;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = switch (location.source) {
      PassengerLocationSource.gps => 'Current location',
      PassengerLocationSource.place => 'Place search',
      PassengerLocationSource.mapPin => 'Map pin',
      PassengerLocationSource.savedPlace => 'Saved place',
    };

    return Padding(
      padding: const EdgeInsets.only(top: OraSpacing.sm),
      child: OraCard(
        padding: const EdgeInsets.all(OraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              location.displayLabel,
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              '$sourceLabel · ${location.lat.toStringAsFixed(5)}, '
              '${location.lng.toStringAsFixed(5)}',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(label: title, onPressed: onConfirm),
          ],
        ),
      ),
    );
  }
}

class _ReviewPane extends StatelessWidget {
  const _ReviewPane({
    required this.state,
    required this.padding,
    required this.onSelectCategory,
    required this.onEditLocations,
    required this.onSubmit,
    required this.onPaymentChange,
  });

  final RideRequestUiState state;
  final double padding;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onEditLocations;
  final VoidCallback onSubmit;
  final VoidCallback onPaymentChange;

  @override
  Widget build(BuildContext context) {
    final cat = state.selectedCategory;
    final pickup = state.confirmedPickup;
    final destination = state.confirmedDestination;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding,
              OraSpacing.lg,
              padding,
              OraSpacing.md,
            ),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: OraColors.border,
                    borderRadius: BorderRadius.circular(OraRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: OraSpacing.md),
              OraSectionHeader(
                title: 'Select a ride',
                action: Text(
                  '${kRideCategoryOptions.length} options',
                  style: OraTypography.caption(OraColors.textMuted),
                ),
              ),
              const SizedBox(height: OraSpacing.sm),
              OraCard(
                onTap: onEditLocations,
                padding: const EdgeInsets.all(OraSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip summary',
                      style: OraTypography.label(OraColors.textSecondary),
                    ),
                    const SizedBox(height: OraSpacing.xs),
                    Text(
                      pickup?.displayLabel ?? state.pickupText.trim(),
                      style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    ),
                    Text(
                      'to ${destination?.displayLabel ?? state.destinationText.trim()}',
                      style: OraTypography.body(OraColors.textSecondary),
                    ),
                    const SizedBox(height: OraSpacing.xxs),
                    Text(
                      pickup != null && destination != null
                          ? 'Pickup & destination confirmed'
                          : 'Locations need confirmation',
                      style: OraTypography.caption(OraColors.goldSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: OraSpacing.md),
              RideCategorySelector(
                selectedId: state.categoryId,
                onSelect: onSelectCategory,
              ),
              const SizedBox(height: OraSpacing.md),
              Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    color: OraColors.tealBright,
                    size: 20,
                  ),
                  const SizedBox(width: OraSpacing.xs),
                  Text(
                    'Cash',
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onPaymentChange,
                    child: Text(
                      'Change',
                      style: OraTypography.label(OraColors.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            OraSpacing.sm,
            padding,
            OraSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: OraButton(
            label: 'Request ${cat.name}',
            onPressed: onSubmit,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OraChip(
        label: label,
        selected: ok,
        variant: OraChipVariant.status,
      ),
    );
  }
}
