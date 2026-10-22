import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/utils/responsive.dart';
import '../../../saved_places/domain/entities/passenger_places.dart';
import '../../../saved_places/presentation/view_models/passenger_places_view_model.dart';
import '../../../saved_places/presentation/widgets/passenger_places_sections.dart';
import '../../domain/models/passenger_city.dart';
import '../../domain/models/resolved_passenger_location.dart';
import '../../domain/models/ride_category_option.dart';
import '../../domain/ports/pricing_estimate_port.dart';
import '../offers/offer_display.dart';
import '../models/ride_map_preview_model.dart';
import '../utils/ride_request_map_layout.dart';
import '../view_models/ride_request_view_model.dart';
import '../widgets/ride_category_selector.dart';
import '../widgets/ride_map_preview.dart';

/// Passenger ride compose + review. Pricing from backend estimate (Phase 5C).
class RideRequestView extends ConsumerStatefulWidget {
  const RideRequestView({
    super.key,
    this.initialCategoryId,
    this.initialServiceType,
  });

  final String? initialCategoryId;

  /// e.g. `?service=intercity` — validated against [kRideRequestServiceTypes].
  final String? initialServiceType;

  @override
  ConsumerState<RideRequestView> createState() => _RideRequestViewState();
}

class _RideRequestViewState extends ConsumerState<RideRequestView> {
  late final TextEditingController _pickupController;
  late final TextEditingController _destinationController;
  final ScrollController _composeScrollController = ScrollController();
  final GlobalKey _destinationProposalKey = GlobalKey();

  /// UI-only — expand/collapse must not touch pricing/Places/GPS/create.
  bool _mapExpanded = false;

  @override
  void initState() {
    super.initState();
    _pickupController = TextEditingController();
    _destinationController = TextEditingController();
    final category = widget.initialCategoryId;
    final serviceType = widget.initialServiceType;
    if (category != null || serviceType != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final vm = ref.read(rideRequestViewModelProvider.notifier);
        vm.seedCategory(category);
        vm.seedServiceType(serviceType);
      });
    }
  }

  @override
  void dispose() {
    _composeScrollController.dispose();
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _expandMap() {
    if (_mapExpanded) return;
    setState(() => _mapExpanded = true);
  }

  void _collapseMap() {
    if (!_mapExpanded) return;
    // Leaving the map abandons any pending pin-adjust target — the next
    // stray tap must not silently overwrite a proposal.
    ref.read(rideRequestViewModelProvider.notifier).cancelPinAdjust();
    setState(() => _mapExpanded = false);
  }

  void _onMapBack(RideRequestUiState state) {
    if (_mapExpanded) {
      _collapseMap();
      return;
    }
    if (state.phase == RideRequestPhase.review) {
      ref.read(rideRequestViewModelProvider.notifier).goToCompose();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _scrollDestinationProposalIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _destinationProposalKey.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: OraMotion.fade,
        curve: OraMotion.standard,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
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

  /// SAVED-PLACES: open the save sheet for the field's current
  /// proposed/confirmed point, persist via the ride VM, and surface the
  /// result. Coordinates are reused as-is — no extra lookup runs.
  Future<void> _saveFieldPlace(LocationField field) async {
    final request = await showSavePlaceSheet(context);
    if (request == null || !mounted) return;
    final error = await ref
        .read(rideRequestViewModelProvider.notifier)
        .savePlaceForField(
          field: field,
          name: request.name,
          id: request.slotId,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Saved as ${request.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// SAVED-PLACES: rename/remove an existing saved place.
  Future<void> _manageSavedPlace(SavedPlace place) async {
    final request = await showManagePlaceSheet(context, place: place);
    if (request == null || !mounted) return;
    final places = ref.read(passengerPlacesProvider.notifier);
    final error = switch (request.action) {
      'rename' =>
        await places.renamePlace(id: place.id, name: request.name),
      'remove' => await places.removePlace(place.id),
      _ => null,
    };
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (request.action == 'remove'
                  ? 'Removed ${place.name}'
                  : 'Renamed to ${request.name}'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rideRequestViewModelProvider);
    final vm = ref.read(rideRequestViewModelProvider.notifier);
    final placesState = ref.watch(passengerPlacesProvider);
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

      final destinationProposalReady = next.phase == RideRequestPhase.compose &&
          next.proposedDestination != null &&
          !next.hasConfirmedDestination &&
          (prev?.proposedDestination == null ||
              prev!.proposedDestination != next.proposedDestination);
      if (destinationProposalReady) {
        _scrollDestinationProposalIntoView();
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

    return PopScope(
      canPop: !_mapExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _mapExpanded) {
          _collapseMap();
        }
      },
      child: Scaffold(
        backgroundColor: OraColors.background,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardVisible =
                  MediaQuery.viewInsetsOf(context).bottom > 0;
              final mapHeight = _mapExpanded
                  ? RideRequestMapLayout.expandedMapHeight(
                      viewportHeight: constraints.maxHeight,
                    )
                  : RideRequestMapLayout.compactMapHeight(
                      viewportHeight: constraints.maxHeight,
                      keyboardVisible: keyboardVisible,
                    );

              return Column(
                children: [
                  RideMapPreview(
                    model: RideMapPreviewModel.fromRideRequest(
                      confirmedPickup: state.confirmedPickup,
                      confirmedDestination: state.confirmedDestination,
                      proposedPickup: state.proposedPickup,
                      proposedDestination: state.proposedDestination,
                      pricingStatus: state.pricingStatus,
                      pricingEstimate: state.pricingEstimate,
                      hasUsablePricing: state.hasUsablePricing,
                    ),
                    height: mapHeight,
                    isExpanded: _mapExpanded,
                    onExpand: _expandMap,
                    onCollapse: _collapseMap,
                    onBack: () => _onMapBack(state),
                    pinAdjustLabel: switch (state.pinAdjustTarget) {
                      LocationField.pickup => 'pickup',
                      LocationField.destination => 'destination',
                      null => null,
                    },
                    onMapPointSelected: (lat, lng) {
                      vm.setPinFromMapTap(lat, lng);
                      _collapseMap();
                    },
                    onCancelPinAdjust: _collapseMap,
                  ),
                  if (!_mapExpanded)
                    Expanded(
                      child: Transform.translate(
                        offset:
                            const Offset(0, -RideRequestMapLayout.sheetOverlap),
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
                                          canSubmit: vm.canSubmitRideRequest,
                                          onSelectCategory: vm.selectCategory,
                                          onSelectServiceType:
                                              vm.selectServiceType,
                                          onEditLocations: vm.goToCompose,
                                          onSubmit: vm.submit,
                                          onRetryPricing: vm.retryPricing,
                                          onSelectCity: vm.setCitySlug,
                                          onOfferDraftChanged:
                                              vm.setPassengerOfferDraft,
                                          onPaymentChange: () =>
                                              _showGateSheet(
                                            'Payments',
                                            'Wallet and online payment are not '
                                                'available in this build. Cash remains '
                                                'the only honest option.',
                                          ),
                                        )
                                      : _ComposePane(
                                          state: state,
                                          padding: padding,
                                          scrollController:
                                              _composeScrollController,
                                          destinationProposalKey:
                                              _destinationProposalKey,
                                          pickupController: _pickupController,
                                          destinationController:
                                              _destinationController,
                                          onPickupChanged: vm.setPickupText,
                                          onDestinationChanged:
                                              vm.setDestinationText,
                                          onSelectServiceType:
                                              vm.selectServiceType,
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
                                          onRetryPickupName:
                                              vm.retryPickupNameLookup,
                                          onAdjustPickupOnMap: () {
                                            vm.startPinAdjust(
                                              LocationField.pickup,
                                            );
                                            _expandMap();
                                          },
                                          onConfirmDestination:
                                              vm.confirmDestination,
                                          onRetryDestinationName:
                                              vm.retryDestinationNameLookup,
                                          onAdjustDestinationOnMap: () {
                                            vm.startPinAdjust(
                                              LocationField.destination,
                                            );
                                            _expandMap();
                                          },
                                          onContinue: vm.goToReview,
                                          savedPlaces: placesState.places,
                                          recents: placesState.recents,
                                          onSelectSavedPickup: (p) =>
                                              vm.applySavedPlace(
                                            field: LocationField.pickup,
                                            place: p,
                                          ),
                                          onSelectSavedDestination: (p) =>
                                              vm.applySavedPlace(
                                            field: LocationField.destination,
                                            place: p,
                                          ),
                                          onSelectRecent:
                                              vm.applyRecentDestination,
                                          onManageSaved: (p) =>
                                              _manageSavedPlace(p),
                                          onSavePickup: () => _saveFieldPlace(
                                            LocationField.pickup,
                                          ),
                                          onSaveDestination: () =>
                                              _saveFieldPlace(
                                            LocationField.destination,
                                          ),
                                        ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ComposePane extends StatelessWidget {
  const _ComposePane({
    required this.state,
    required this.padding,
    required this.scrollController,
    required this.destinationProposalKey,
    required this.pickupController,
    required this.destinationController,
    required this.onPickupChanged,
    required this.onDestinationChanged,
    required this.onSelectServiceType,
    required this.onUseCurrentLocation,
    required this.onSelectPickupSuggestion,
    required this.onSelectDestinationSuggestion,
    required this.onConfirmPickup,
    required this.onRetryPickupName,
    required this.onAdjustPickupOnMap,
    required this.onConfirmDestination,
    required this.onRetryDestinationName,
    required this.onAdjustDestinationOnMap,
    required this.onContinue,
    required this.savedPlaces,
    required this.recents,
    required this.onSelectSavedPickup,
    required this.onSelectSavedDestination,
    required this.onSelectRecent,
    required this.onManageSaved,
    required this.onSavePickup,
    required this.onSaveDestination,
  });

  final RideRequestUiState state;
  final double padding;
  final ScrollController scrollController;
  final GlobalKey destinationProposalKey;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onSelectServiceType;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<PlaceSuggestion> onSelectPickupSuggestion;
  final ValueChanged<PlaceSuggestion> onSelectDestinationSuggestion;
  final VoidCallback onConfirmPickup;
  final VoidCallback onRetryPickupName;

  /// MAP-PIN-ADJUST: expands the map in set-point mode for this endpoint.
  final VoidCallback onAdjustPickupOnMap;
  final VoidCallback onConfirmDestination;
  final VoidCallback onRetryDestinationName;
  final VoidCallback onAdjustDestinationOnMap;
  final VoidCallback onContinue;
  final List<SavedPlace> savedPlaces;
  final List<RecentDestination> recents;
  final ValueChanged<SavedPlace> onSelectSavedPickup;
  final ValueChanged<SavedPlace> onSelectSavedDestination;
  final ValueChanged<RecentDestination> onSelectRecent;
  final ValueChanged<SavedPlace> onManageSaved;
  final VoidCallback onSavePickup;
  final VoidCallback onSaveDestination;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scrollController,
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
              const SizedBox(height: OraSpacing.sm),
              _ServiceTypeSelector(
                selected: state.serviceType,
                onSelect: onSelectServiceType,
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
                        // SAVED-PLACES: instant pickup reuse — shown only for
                        // an untouched field (no text/proposal/confirmation).
                        if (!state.hasPickupText &&
                            state.proposedPickup == null &&
                            !state.hasConfirmedPickup &&
                            !state.pickupBusy)
                          SavedPlacesSection(
                            places: savedPlaces,
                            onSelect: onSelectSavedPickup,
                            onManage: onManageSaved,
                          ),
                        if (state.proposedPickup != null &&
                            !state.hasConfirmedPickup)
                          _ProposalCard(
                            title: 'Confirm pickup',
                            location: state.proposedPickup!,
                            onConfirm: onConfirmPickup,
                            nameUnresolved: state.pickupNameUnresolved,
                            onRetryName: onRetryPickupName,
                            onAdjustOnMap: onAdjustPickupOnMap,
                            onSave: onSavePickup,
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
                        // SAVED-PLACES + RECENTS: instant destination reuse.
                        if (!state.hasDestinationText &&
                            state.proposedDestination == null &&
                            !state.hasConfirmedDestination &&
                            !state.destinationBusy) ...[
                          SavedPlacesSection(
                            places: savedPlaces,
                            onSelect: onSelectSavedDestination,
                            onManage: onManageSaved,
                          ),
                          RecentDestinationsSection(
                            recents: recents,
                            onSelect: onSelectRecent,
                          ),
                        ],
                        if (state.proposedDestination != null &&
                            !state.hasConfirmedDestination)
                          KeyedSubtree(
                            key: destinationProposalKey,
                            child: _ProposalCard(
                              title: 'Confirm destination',
                              location: state.proposedDestination!,
                              onConfirm: onConfirmDestination,
                              nameUnresolved: state.destinationNameUnresolved,
                              onRetryName: onRetryDestinationName,
                              onAdjustOnMap: onAdjustDestinationOnMap,
                              onSave: onSaveDestination,
                            ),
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
    this.nameUnresolved = false,
    this.onRetryName,
    this.onAdjustOnMap,
    this.onSave,
  });

  final String title;
  final ResolvedPassengerLocation location;
  final VoidCallback onConfirm;

  /// Coordinates are authoritative but no place name resolved — explain and
  /// offer a name-only retry (never re-runs GPS or blocks confirm).
  final bool nameUnresolved;
  final VoidCallback? onRetryName;

  /// MAP-PIN-ADJUST: expands the map in set-point mode for this endpoint.
  final VoidCallback? onAdjustOnMap;

  /// SAVED-PLACES: save this proposed point as a favorite (optional).
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = switch (location.source) {
      PassengerLocationSource.gps => 'Current location',
      PassengerLocationSource.place => 'Place search',
      PassengerLocationSource.mapPin => 'Map pin',
      PassengerLocationSource.savedPlace => 'Saved place',
      PassengerLocationSource.recent => 'Recent destination',
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
              sourceLabel,
              style: OraTypography.caption(OraColors.textMuted),
            ),
            // GPS fix accuracy — shown only when the provider reported it.
            // Distinct from address accuracy; never invents a value.
            if (location.horizontalAccuracyMeters != null) ...[
              const SizedBox(height: OraSpacing.xxs),
              Text(
                'GPS fix accuracy ±'
                '${location.horizontalAccuracyMeters!.round()} m',
                style: OraTypography.caption(OraColors.textMuted),
              ),
            ],
            if (nameUnresolved) ...[
              const SizedBox(height: OraSpacing.xxs),
              Text(
                location.source == PassengerLocationSource.mapPin
                    ? 'Couldn\'t fetch a place name — the pinned point is '
                        'still used. Tap "Adjust on map" to move it, or '
                        'search above.'
                    : 'Couldn\'t fetch a place name — your exact position is '
                        'still used. Tap "Adjust on map" to move the pin, or '
                        'search above.',
                style: OraTypography.caption(OraColors.textMuted),
              ),
              if (onRetryName != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onRetryName,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Retry name lookup'),
                  ),
                ),
            ],
            const SizedBox(height: OraSpacing.sm),
            OraButton(label: title, onPressed: onConfirm),
            if (onAdjustOnMap != null || onSave != null)
              Row(
                children: [
                  if (onAdjustOnMap != null)
                    TextButton.icon(
                      onPressed: onAdjustOnMap,
                      icon: const Icon(Icons.edit_location_alt_outlined,
                          size: 18),
                      label: const Text('Adjust on map'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (onAdjustOnMap != null && onSave != null)
                    const SizedBox(width: OraSpacing.sm),
                  if (onSave != null)
                    TextButton.icon(
                      onPressed: onSave,
                      icon:
                          const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('Save place'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
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
    required this.canSubmit,
    required this.onSelectCategory,
    required this.onSelectServiceType,
    required this.onEditLocations,
    required this.onSubmit,
    required this.onRetryPricing,
    required this.onSelectCity,
    required this.onOfferDraftChanged,
    required this.onPaymentChange,
  });

  final RideRequestUiState state;
  final double padding;
  final bool canSubmit;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<String> onSelectServiceType;
  final VoidCallback onEditLocations;
  final VoidCallback onSubmit;
  final VoidCallback onRetryPricing;
  final ValueChanged<String> onSelectCity;
  final ValueChanged<String> onOfferDraftChanged;
  final VoidCallback onPaymentChange;

  String? get _selectedPriceLabel {
    final estimate = state.pricingEstimate;
    if (!state.hasUsablePricing || estimate == null) return null;
    // Category chip shows guidance fare (recommended), not the passenger offer.
    return formatOfferAmountMinor(
      estimate.recommendedFareMinor,
      estimate.currency,
    );
  }

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
              _ServiceTypeSelector(
                selected: state.serviceType,
                onSelect: onSelectServiceType,
              ),
              const SizedBox(height: OraSpacing.sm),
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
              _PricingCard(
                state: state,
                onRetry: onRetryPricing,
                onOfferDraftChanged: onOfferDraftChanged,
              ),
              const SizedBox(height: OraSpacing.md),
              _CityRow(
                citySlug: state.citySlug,
                onSelectCity: onSelectCity,
              ),
              const SizedBox(height: OraSpacing.md),
              RideCategorySelector(
                selectedId: state.categoryId,
                onSelect: onSelectCategory,
                selectedPriceLabel: _selectedPriceLabel,
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
            onPressed: canSubmit ? onSubmit : null,
          ),
        ),
      ],
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({
    required this.citySlug,
    required this.onSelectCity,
  });

  final String? citySlug;
  final ValueChanged<String> onSelectCity;

  @override
  Widget build(BuildContext context) {
    final label = passengerCityLabel(citySlug) ?? 'Select city';
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'City',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            label,
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
          if (citySlug == null) ...[
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Needed for pricing. Choose the city for this trip.',
              style: OraTypography.caption(OraColors.goldSoft),
            ),
          ],
          const SizedBox(height: OraSpacing.sm),
          Wrap(
            spacing: OraSpacing.xs,
            runSpacing: OraSpacing.xs,
            children: [
              for (final city in kPassengerCityOptions)
                OraChip(
                  label: city.label,
                  selected: citySlug == city.id,
                  onTap: () => onSelectCity(city.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.state,
    required this.onRetry,
    required this.onOfferDraftChanged,
  });

  final RideRequestUiState state;
  final VoidCallback onRetry;
  final ValueChanged<String> onOfferDraftChanged;

  @override
  Widget build(BuildContext context) {
    if (state.pricingStatus == PricingStatus.loading) {
      return OraCard(
        padding: const EdgeInsets.all(OraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estimated fare',
              style: OraTypography.label(OraColors.textSecondary),
            ),
            const SizedBox(height: OraSpacing.sm),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Getting a price for this trip…',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (state.hasUsablePricing && state.pricingEstimate != null) {
      final estimate = state.pricingEstimate!;
      final fare = formatOfferAmountMinor(
        estimate.recommendedFareMinor,
        estimate.currency,
      );
      final minFare = formatOfferAmountMinor(
        estimate.offerBoundMinMinor,
        estimate.currency,
      );
      final maxFare = formatOfferAmountMinor(
        estimate.offerBoundMaxMinor,
        estimate.currency,
      );
      final distance = _formatDistanceKm(estimate.distanceKm);
      final duration = _formatDurationMin(estimate.durationMin);

      return OraCard(
        padding: const EdgeInsets.all(OraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Estimated fare',
              style: OraTypography.label(OraColors.textSecondary),
            ),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              fare,
              style: OraTypography.headline(OraColors.textPrimary),
            ),
            const SizedBox(height: OraSpacing.xxs),
            Text(
              'Guidance only — set your offer below.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Offer range $minFare – $maxFare',
              style: OraTypography.body(OraColors.textSecondary),
            ),
            const SizedBox(height: OraSpacing.xs),
            Text(
              '$distance · $duration',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.md),
            _PassengerOfferField(
              key: ValueKey<String>(estimate.pricingSnapshotId),
              draftText: state.passengerOfferDraftText,
              errorText: state.passengerOfferError,
              enabled: state.phase != RideRequestPhase.submitting,
              onChanged: onOfferDraftChanged,
            ),
          ],
        ),
      );
    }

    final message = state.pricingDisplayError ??
        'Pricing isn\'t available right now. Please try again later.';
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Estimated fare',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            message,
            style: OraTypography.body(OraColors.danger),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(
            label: 'Retry pricing',
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

String _formatDistanceKm(double km) {
  final rounded = km >= 10 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
  return '$rounded km';
}

String _formatDurationMin(double minutes) {
  final whole = minutes.round();
  return '~$whole min';
}

/// Local text controller remounted when [key] (pricingSnapshotId) changes.
class _PassengerOfferField extends StatefulWidget {
  const _PassengerOfferField({
    super.key,
    required this.draftText,
    required this.errorText,
    required this.enabled,
    required this.onChanged,
  });

  final String draftText;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_PassengerOfferField> createState() => _PassengerOfferFieldState();
}

class _PassengerOfferFieldState extends State<_PassengerOfferField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draftText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // OraTextField paints the label as a sibling Text, so TalkBack would only
    // hear the bare digits. Attach identifier + label onto the child TextField
    // semantics — do NOT set textField/value here (that made Android expose a
    // non-clickable EditText and blocked physical focus/typing).
    return Semantics(
      identifier: 'passenger_offer_field',
      label: 'Your offer',
      child: OraTextField(
        controller: _controller,
        label: 'Your offer',
        hint: 'Amount in PKR',
        errorText: widget.errorText,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onChanged: widget.onChanged,
      ),
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

/// Service-kind chips (City ride / Intercity). Backend accepts
/// courier/move too but those stay unexposed until their product
/// semantics exist.
class _ServiceTypeSelector extends StatelessWidget {
  const _ServiceTypeSelector({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OraChip(
          label: rideRequestServiceTypeLabel('ride'),
          selected: selected == 'ride',
          onTap: () => onSelect('ride'),
        ),
        const SizedBox(width: OraSpacing.xs),
        OraChip(
          label: rideRequestServiceTypeLabel('intercity'),
          selected: selected == 'intercity',
          onTap: () => onSelect('intercity'),
          leading: const Icon(
            Icons.route_rounded,
            size: 16,
            color: OraColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
