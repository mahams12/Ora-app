import 'dart:async';

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
import '../../domain/models/delivery_stop_draft.dart';
import '../../domain/models/parcel_draft.dart';
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
          RideRequestBlockReason.parcelIncomplete => 'Parcel details needed',
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
                                          onUpdateParcel: vm.updateParcel,
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
                                          vm: vm,
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
                                          onUpdateParcel: vm.updateParcel,
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
    required this.vm,
    required this.padding,
    required this.scrollController,
    required this.destinationProposalKey,
    required this.pickupController,
    required this.destinationController,
    required this.onPickupChanged,
    required this.onDestinationChanged,
    required this.onSelectServiceType,
    required this.onUpdateParcel,
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

  /// Ora Courier v2 — stop editor needs the view-model's place-search
  /// methods; parcel/stop/shopping mutations go through it directly.
  final RideRequestViewModel vm;
  final double padding;
  final ScrollController scrollController;
  final GlobalKey destinationProposalKey;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onSelectServiceType;
  final ValueChanged<ParcelDraft> onUpdateParcel;
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
                'Search a place, use your current location, or set a point '
                'on the map. Confirm each point before continuing — text '
                'alone is not enough.',
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
                        // BUY & DELIVER: no separate pickup — the ride
                        // origin is the first shop entered below.
                        if (state.isBuyDeliver)
                          const Padding(
                            padding: EdgeInsets.only(
                              bottom: OraSpacing.sm,
                            ),
                            child: OraListRow(
                              title: 'Pickup is your first shop',
                              subtitle:
                                  'Buy & Deliver starts at the first shop you add below — no separate pickup needed.',
                              leading: Icon(
                                Icons.storefront_outlined,
                                color: OraColors.tealBright,
                                size: 20,
                              ),
                              showDivider: false,
                            ),
                          )
                        else ...[
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
                              onPressed: state.pickupBusy
                                  ? null
                                  : onUseCurrentLocation,
                              icon: const Icon(Icons.my_location, size: 18),
                              label: const Text('Use current location'),
                            ),
                          ),
                        ],
                        if (!state.isBuyDeliver && state.pickupBusy)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: OraSpacing.xs),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (!state.isBuyDeliver &&
                            state.pickupLookupError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: OraSpacing.xs),
                            child: Text(
                              state.pickupLookupError!,
                              style: OraTypography.caption(OraColors.danger),
                            ),
                          ),
                        if (!state.isBuyDeliver)
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
                        if (!state.isBuyDeliver &&
                            !state.hasPickupText &&
                            state.proposedPickup == null &&
                            !state.hasConfirmedPickup &&
                            !state.pickupBusy) ...[
                          SavedPlacesSection(
                            places: savedPlaces,
                            onSelect: onSelectSavedPickup,
                            onManage: onManageSaved,
                          ),
                          // ZERO-COST PICKUP: direct map pin entry — reachable
                          // even when place search is unavailable or GPS is
                          // denied. The tap expands the map in set-point mode;
                          // coordinates are authoritative, name resolves
                          // best-effort via the device geocoder.
                          OraListRow(
                            title: 'Set pickup on map',
                            subtitle:
                                'Tap the map to drop the pickup pin',
                            leading: const Icon(
                              Icons.edit_location_alt_outlined,
                              color: OraColors.tealBright,
                              size: 20,
                            ),
                            onTap: onAdjustPickupOnMap,
                            showDivider: false,
                          ),
                        ],
                        if (!state.isBuyDeliver &&
                            state.proposedPickup != null &&
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
                          // ZERO-COST DESTINATION: direct map pin entry — the
                          // fallback path when Places is unconfigured and no
                          // saved/recent places exist. Tap expands the map in
                          // set-point mode; coordinates are authoritative and
                          // the name resolves best-effort via the device
                          // geocoder (unresolved stays visibly unresolved).
                          OraListRow(
                            title: 'Set destination on map',
                            subtitle:
                                'Tap the map to drop the destination pin',
                            leading: const Icon(
                              Icons.edit_location_alt_outlined,
                              color: OraColors.primary,
                              size: 20,
                            ),
                            onTap: onAdjustDestinationOnMap,
                            showDivider: false,
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
                label: state.isBuyDeliver
                    ? (state.hasConfirmedPickup
                        ? 'Pickup starts at first shop'
                        : 'Add a shop to set pickup')
                    : state.hasConfirmedPickup
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
              // Ora Courier — parcel manifest form (courier only).
              if (state.isCourier) ...[
                const SizedBox(height: OraSpacing.lg),
                _ParcelSection(
                  parcel: state.parcel,
                  onChanged: onUpdateParcel,
                ),
              ],
              // Ora Courier v2 — intermediate stops + B&D shopping.
              if (state.isDelivery) ...[
                const SizedBox(height: OraSpacing.lg),
                _DeliveryStopsSection(state: state, vm: vm),
              ],
              if (state.isBuyDeliver) ...[
                const SizedBox(height: OraSpacing.md),
                _ShoppingSection(state: state, vm: vm),
              ],
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
    required this.onUpdateParcel,
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
  final ValueChanged<ParcelDraft> onUpdateParcel;
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
                title: state.isBuyDeliver
                    ? 'Buy & Deliver'
                    : state.isCourier
                        ? 'Parcel delivery'
                        : 'Select a ride',
                action: Text(
                  state.isDelivery
                      ? 'Same-day delivery'
                      : '${kRideCategoryOptions.length} options',
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
              // Ora Courier — parcel manifest is part of the booking. The
              // ride-category selector is hidden: courier has one vehicle
              // class ('courier'); parcel size drives the offer instead.
              if (state.isCourier) ...[
                const SizedBox(height: OraSpacing.md),
                _ParcelSummaryCard(
                  parcel: state.parcel,
                  onChanged: onUpdateParcel,
                ),
              ],
              // Ora Courier v2 — ordered itinerary + B&D shopping summary.
              if (state.isDelivery) ...[
                const SizedBox(height: OraSpacing.md),
                _ItinerarySummaryCard(state: state),
              ],
              if (state.isBuyDeliver) ...[
                const SizedBox(height: OraSpacing.md),
                _ShoppingSummaryCard(state: state),
              ],
              if (!state.isDelivery) ...[
                const SizedBox(height: OraSpacing.md),
                RideCategorySelector(
                  selectedId: state.categoryId,
                  onSelect: onSelectCategory,
                  selectedPriceLabel: _selectedPriceLabel,
                ),
              ],
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
            label: state.isBuyDeliver
                ? 'Request Buy & Deliver'
                : state.isCourier
                    ? 'Request courier'
                    : 'Request ${cat.name}',
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
    return Wrap(
      spacing: OraSpacing.xs,
      runSpacing: OraSpacing.xs,
      children: [
        OraChip(
          label: rideRequestServiceTypeLabel('ride'),
          selected: selected == 'ride',
          onTap: () => onSelect('ride'),
        ),
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
        OraChip(
          label: rideRequestServiceTypeLabel('courier'),
          selected: selected == 'courier',
          onTap: () => onSelect('courier'),
          leading: const Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: OraColors.textSecondary,
          ),
        ),
        OraChip(
          label: rideRequestServiceTypeLabel('buy_deliver'),
          selected: selected == 'buy_deliver',
          onTap: () => onSelect('buy_deliver'),
          leading: const Icon(
            Icons.shopping_bag_outlined,
            size: 16,
            color: OraColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Ora Courier ─────────────────────────────────────────────────────────────

/// Courier parcel manifest form — shown in the compose pane when
/// serviceType == 'courier'. Server re-validates every field on create.
class _ParcelSection extends StatelessWidget {
  const _ParcelSection({required this.parcel, required this.onChanged});

  final ParcelDraft parcel;
  final ValueChanged<ParcelDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parcel details',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'The courier confirms each stop in the app — no codes needed. '
            'You can acknowledge receipt or report an issue afterwards.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            label: 'Sender name',
            hint: 'Who hands over the parcel',
            initialValue: parcel.senderName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => onChanged(parcel.copyWith(senderName: v)),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Sender phone',
            hint: '+92 3XX XXXXXXX',
            initialValue: parcel.senderPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onChanged: (v) => onChanged(parcel.copyWith(senderPhone: v)),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Receiver name',
            hint: 'Who receives the parcel',
            initialValue: parcel.receiverName,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => onChanged(parcel.copyWith(receiverName: v)),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Receiver phone',
            hint: '+92 3XX XXXXXXX',
            initialValue: parcel.receiverPhone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onChanged: (v) => onChanged(parcel.copyWith(receiverPhone: v)),
          ),
          const SizedBox(height: OraSpacing.md),
          Text(
            'Parcel type',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Wrap(
            spacing: OraSpacing.xs,
            runSpacing: OraSpacing.xs,
            children: [
              for (final c in kParcelCategories)
                OraChip(
                  label: c[0].toUpperCase() + c.substring(1),
                  selected: parcel.parcelCategory == c,
                  onTap: () => onChanged(parcel.copyWith(parcelCategory: c)),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          Text(
            'Size',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          Wrap(
            spacing: OraSpacing.xs,
            children: [
              for (final s in kParcelSizes)
                OraChip(
                  label: switch (s) {
                    'SMALL' => 'Small · up to 5 kg',
                    'MEDIUM' => 'Medium · up to 15 kg',
                    _ => 'Large · up to 30 kg',
                  },
                  selected: parcel.size == s,
                  onTap: () => onChanged(parcel.copyWith(size: s)),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OraTextField(
                  label: 'Weight (kg)',
                  hint: 'e.g. 2.5',
                  initialValue: parcel.weightText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onChanged: (v) =>
                      onChanged(parcel.copyWith(weightText: v)),
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: OraTextField(
                  label: 'Quantity',
                  hint: '1',
                  initialValue: parcel.quantityText,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) =>
                      onChanged(parcel.copyWith(quantityText: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Description',
            hint: 'What is in the parcel?',
            initialValue: parcel.description,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) => onChanged(parcel.copyWith(description: v)),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Handling instructions (optional)',
            hint: 'e.g. keep upright, fragile',
            initialValue: parcel.handlingInstructions,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (v) =>
                onChanged(parcel.copyWith(handlingInstructions: v)),
          ),
          const SizedBox(height: OraSpacing.md),
          Text(
            'Not allowed: ${kParcelProhibitedItems.join(' · ')}',
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Courier parcel summary — shown on the review pane in place of the
/// ride-category selector. Inline size correction stays possible.
class _ParcelSummaryCard extends StatelessWidget {
  const _ParcelSummaryCard({required this.parcel, required this.onChanged});

  final ParcelDraft parcel;
  final ValueChanged<ParcelDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parcel',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          if (parcel.isValid)
            Text(
              '${parcel.description.trim()} — '
              '${parcel.size.toLowerCase()} · '
              '${parcel.weightKg} kg × ${parcel.quantity} · '
              '${parcel.parcelCategory}',
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            )
          else
            Text(
              parcel.firstError ?? 'Parcel details are incomplete.',
              style: OraTypography.body(OraColors.goldSoft),
            ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            '${parcel.senderName.trim()} → ${parcel.receiverName.trim()}',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.xs),
          Wrap(
            spacing: OraSpacing.xs,
            children: [
              for (final s in kParcelSizes)
                OraChip(
                  label: s.toLowerCase(),
                  selected: parcel.size == s,
                  onTap: () => onChanged(parcel.copyWith(size: s)),
                ),
            ],
          ),
          if (!parcel.isValid) ...[
            const SizedBox(height: OraSpacing.xs),
            Text(
              'Go back to complete sender, receiver and parcel details.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ora Courier v2 — multi-stop + Buy & Deliver ──────────────────────────────

/// Intermediate-stop editor section (courier: extra pickups/drop-offs;
/// buy_deliver: shops). Cap = server maxStops minus the two endpoints.
class _DeliveryStopsSection extends StatelessWidget {
  const _DeliveryStopsSection({required this.state, required this.vm});

  final RideRequestUiState state;
  final RideRequestViewModel vm;

  Future<void> _editStop(
    BuildContext context, {
    required String type,
    int? index,
  }) async {
    final draft = await showModalBottomSheet<DeliveryStopDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OraColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(OraRadius.xxl),
        ),
      ),
      builder: (_) => _StopEditorSheet(
        vm: vm,
        type: type,
        initial: index != null ? state.stops[index] : null,
      ),
    );
    if (draft == null) return;
    if (index != null) {
      vm.updateStopDraft(index, draft);
    } else {
      vm.addStopDraft(draft);
    }
  }

  IconData _iconFor(String type) => switch (type) {
        'SHOP' => Icons.storefront_outlined,
        'DROPOFF' => Icons.flag_outlined,
        _ => Icons.inventory_2_outlined,
      };

  String _labelFor(String type) => switch (type) {
        'SHOP' => 'Shop',
        'DROPOFF' => 'Drop-off',
        _ => 'Pickup',
      };

  @override
  Widget build(BuildContext context) {
    final stops = state.stops;
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.isBuyDeliver ? 'Shops & stops' : 'Extra stops',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            state.isBuyDeliver
                ? 'Add the shops the driver should visit, in order. '
                    'You approve the itemized prices before anything is bought.'
                : 'Add up to ${state.maxStops - 2} extra pickups or drop-offs '
                    'between your start and destination. The driver completes '
                    'them in order — no codes needed.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.sm),
          for (var i = 0; i < stops.length; i++)
            OraListRow(
              title: stops[i].label.isNotEmpty
                  ? stops[i].label
                  : _labelFor(stops[i].type),
              subtitle: [
                if (stops[i].locationText.isNotEmpty) stops[i].locationText,
                if (stops[i].type == 'SHOP')
                  '${stops[i].items.where((e) => e.isValid).length} items'
                      '${stops[i].shopBudgetMinor != null ? ' · cap Rs ${stops[i].shopBudgetMinor! ~/ 100}' : ''}',
                if (!stops[i].hasLocation) 'Location needed',
              ].join(' · '),
              leading: Icon(
                _iconFor(stops[i].type),
                size: 20,
                color: stops[i].isValid
                    ? OraColors.tealBright
                    : OraColors.danger,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: OraColors.textMuted,
                onPressed: () => vm.removeStopDraft(i),
              ),
              onTap: () => _editStop(context, type: stops[i].type, index: i),
              showDivider: true,
            ),
          if (state.canAddStop) ...[
            if (state.isBuyDeliver)
              OraListRow(
                title: 'Add a shop',
                subtitle: 'Search a store and list what to buy',
                leading: const Icon(
                  Icons.add_business_outlined,
                  size: 20,
                  color: OraColors.primary,
                ),
                onTap: () => _editStop(context, type: 'SHOP'),
              )
            else ...[
              OraListRow(
                title: 'Add a pickup',
                subtitle: 'Another parcel collection point',
                leading: const Icon(
                  Icons.add_location_alt_outlined,
                  size: 20,
                  color: OraColors.tealBright,
                ),
                onTap: () => _editStop(context, type: 'PICKUP'),
              ),
              OraListRow(
                title: 'Add a drop-off',
                subtitle: 'Deliver to another address on the way',
                leading: const Icon(
                  Icons.flag_outlined,
                  size: 20,
                  color: OraColors.primary,
                ),
                onTap: () => _editStop(context, type: 'DROPOFF'),
              ),
            ],
          ] else
            Text(
              'Maximum ${state.maxStops} stops reached.',
              style: OraTypography.caption(OraColors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet editor for one intermediate stop. Location is picked via the
/// same Places search the pickup/destination fields use — coordinates are
/// authoritative; the label is display-only.
class _StopEditorSheet extends StatefulWidget {
  const _StopEditorSheet({
    required this.vm,
    required this.type,
    this.initial,
  });

  final RideRequestViewModel vm;

  /// PICKUP | SHOP | DROPOFF.
  final String type;
  final DeliveryStopDraft? initial;

  @override
  State<_StopEditorSheet> createState() => _StopEditorSheetState();
}

class _StopEditorSheetState extends State<_StopEditorSheet> {
  late final TextEditingController _search;
  late final TextEditingController _label;
  late final TextEditingController _instructions;
  late final TextEditingController _budget;
  late List<ShopItemDraft> _items;
  late final List<Key> _itemKeys;
  List<PlaceSuggestion> _suggestions = const [];
  Timer? _debounce;
  double? _lat;
  double? _lng;
  bool _resolving = false;

  bool get _isShop => widget.type == 'SHOP';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _search = TextEditingController(text: initial?.locationText ?? '');
    _label = TextEditingController(text: initial?.label ?? '');
    _instructions =
        TextEditingController(text: initial?.instructions ?? '');
    _budget = TextEditingController(
      text: initial?.shopBudgetMinor != null
          ? '${initial!.shopBudgetMinor! ~/ 100}'
          : '',
    );
    _items = List.of(initial?.items ?? const <ShopItemDraft>[]);
    if (_isShop && _items.isEmpty) _items.add(const ShopItemDraft());
    // Item objects are immutable and replaced on every keystroke, so they
    // cannot be used as row keys — a changed key remounts the row and drops
    // keyboard focus mid-typing. Keep a stable key per row instead.
    _itemKeys = [for (var i = 0; i < _items.length; i++) UniqueKey()];
    _lat = initial?.lat;
    _lng = initial?.lng;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _label.dispose();
    _instructions.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _lat = null;
      _lng = null;
    });
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await widget.vm.searchStopPlaces(query);
        if (mounted) setState(() => _suggestions = results);
      } catch (_) {
        if (mounted) setState(() => _suggestions = const []);
      }
    });
  }

  Future<void> _selectSuggestion(PlaceSuggestion s) async {
    setState(() {
      _resolving = true;
      _suggestions = const [];
    });
    try {
      final resolved = await widget.vm.resolveStopPlace(s);
      if (!mounted) return;
      setState(() {
        _lat = resolved.lat;
        _lng = resolved.lng;
        _search.text = resolved.address ?? s.displayText;
        if (_label.text.trim().isEmpty) {
          _label.text = s.primaryText;
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resolve that place.')),
        );
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  DeliveryStopDraft _buildDraft() {
    final budgetRupees = int.tryParse(_budget.text.trim());
    return DeliveryStopDraft(
      type: widget.type,
      locationText: _search.text.trim(),
      lat: _lat,
      lng: _lng,
      label: _label.text.trim(),
      instructions: _instructions.text.trim(),
      items: _items,
      shopBudgetMinor:
          _isShop && budgetRupees != null && budgetRupees > 0
              ? budgetRupees * 100
              : null,
    );
  }

  bool get _canSave => _buildDraft().isValid;

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.type) {
      'SHOP' => 'Add a shop',
      'DROPOFF' => 'Add a drop-off',
      _ => 'Add a pickup',
    };
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md,
        OraSpacing.md + bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: OraTypography.title(OraColors.textPrimary)),
            const SizedBox(height: OraSpacing.md),
            OraTextField(
              controller: _search,
              label: _isShop ? 'Shop location' : 'Stop location',
              hint: 'Search a place',
              textInputAction: TextInputAction.search,
              prefixIcon: Icons.search,
              onChanged: _onSearchChanged,
            ),
            if (_resolving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: OraSpacing.xs),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ..._suggestions.map(
              (s) => OraListRow(
                title: s.primaryText,
                subtitle: s.secondaryText,
                leading: const Icon(
                  Icons.place_outlined,
                  size: 20,
                  color: OraColors.tealBright,
                ),
                onTap: () => _selectSuggestion(s),
                showDivider: true,
              ),
            ),
            if (_lat != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: OraSpacing.xxs),
                child: _StatusChip(label: 'Location confirmed', ok: true),
              ),
            const SizedBox(height: OraSpacing.sm),
            OraTextField(
              controller: _label,
              label: 'Name (optional)',
              hint: _isShop ? 'e.g. Al-Fatah, DHA Pharmacy' : 'e.g. Office',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: OraSpacing.sm),
            OraTextField(
              controller: _instructions,
              label: 'Instructions (optional)',
              hint: 'Anything the driver should know',
            ),
            if (_isShop) ...[
              const SizedBox(height: OraSpacing.md),
              Text(
                'Shopping list',
                style: OraTypography.label(OraColors.textSecondary),
              ),
              const SizedBox(height: OraSpacing.xs),
              for (var i = 0; i < _items.length; i++)
                _ShopItemRow(
                  key: _itemKeys[i],
                  item: _items[i],
                  onChanged: (item) => setState(() => _items[i] = item),
                  onRemove: _items.length > 1
                      ? () => setState(() {
                            _items.removeAt(i);
                            _itemKeys.removeAt(i);
                          })
                      : null,
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _items.add(const ShopItemDraft());
                    _itemKeys.add(UniqueKey());
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add item'),
                ),
              ),
              const SizedBox(height: OraSpacing.xs),
              OraTextField(
                controller: _budget,
                label: 'Shop budget — Rs (optional)',
                hint: 'Max spend at this shop',
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: OraSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OraButton(
                label: 'Save stop',
                onPressed: _canSave
                    ? () => Navigator.of(context).pop(_buildDraft())
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopItemRow extends StatefulWidget {
  const _ShopItemRow({
    super.key,
    required this.item,
    required this.onChanged,
    this.onRemove,
  });

  final ShopItemDraft item;
  final ValueChanged<ShopItemDraft> onChanged;
  final VoidCallback? onRemove;

  @override
  State<_ShopItemRow> createState() => _ShopItemRowState();
}

class _ShopItemRowState extends State<_ShopItemRow> {
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _qty = TextEditingController(text: '${widget.item.quantity}');
    _note = TextEditingController(text: widget.item.note);
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      ShopItemDraft(
        name: _name.text,
        quantity: int.tryParse(_qty.text.trim()) ?? 1,
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: OraTextField(
              controller: _name,
              hint: 'Item name',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: OraSpacing.xs),
          SizedBox(
            width: 64,
            child: OraTextField(
              controller: _qty,
              hint: 'Qty',
              keyboardType: TextInputType.number,
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: OraSpacing.xs),
          Expanded(
            flex: 2,
            child: OraTextField(
              controller: _note,
              hint: 'Note',
              onChanged: (_) => _emit(),
            ),
          ),
          if (widget.onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: OraColors.textMuted,
              onPressed: widget.onRemove,
            ),
        ],
      ),
    );
  }
}

/// buy_deliver — booking-level shopping budget, restricted-items attestation,
/// and the cash disclosure.
class _ShoppingSection extends StatelessWidget {
  const _ShoppingSection({required this.state, required this.vm});

  final RideRequestUiState state;
  final RideRequestViewModel vm;

  @override
  Widget build(BuildContext context) {
    final capRupees = state.maxShoppingBudgetMinor ~/ 100;
    final budget = state.shoppingBudgetMinor;
    final overCap = budget != null && budget > state.maxShoppingBudgetMinor;
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shopping budget',
            style: OraTypography.title(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'You pay the driver in cash for the items plus the delivery '
            'fare. The driver sends you itemized prices for approval '
            'before buying — the total can never exceed your budget.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            label: 'Total budget — Rs (max $capRupees)',
            hint: 'e.g. 1500',
            initialValue: state.shoppingBudgetText,
            keyboardType: TextInputType.number,
            onChanged: vm.setShoppingBudgetText,
          ),
          if (overCap)
            Padding(
              padding: const EdgeInsets.only(top: OraSpacing.xs),
              child: Text(
                'Budget is capped at Rs $capRupees for rider-paid shopping.',
                style: OraTypography.caption(OraColors.danger),
              ),
            ),
          const SizedBox(height: OraSpacing.sm),
          InkWell(
            onTap: () => vm.setAttestationAccepted(!state.attestationAccepted),
            borderRadius: BorderRadius.circular(OraRadius.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  state.attestationAccepted
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: state.attestationAccepted
                      ? OraColors.tealBright
                      : OraColors.textMuted,
                ),
                const SizedBox(width: OraSpacing.xs),
                Expanded(
                  child: Text(
                    'My list contains no prohibited, controlled, '
                    'prescription-only, or age-restricted items.',
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

/// Review-pane itinerary summary — ordered waypoint list between pickup and
/// destination, plus per-stop shopping item counts for buy_deliver.
class _ItinerarySummaryCard extends StatelessWidget {
  const _ItinerarySummaryCard({required this.state});

  final RideRequestUiState state;

  @override
  Widget build(BuildContext context) {
    final stops = state.stops;
    if (stops.isEmpty) {
      return const SizedBox.shrink();
    }
    IconData iconFor(String type) => switch (type) {
          'SHOP' => Icons.storefront_outlined,
          'DROPOFF' => Icons.flag_outlined,
          _ => Icons.inventory_2_outlined,
        };
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${stops.length + 2} stops',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          for (final s in stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    iconFor(s.type),
                    size: 16,
                    color: OraColors.tealBright,
                  ),
                  const SizedBox(width: OraSpacing.xs),
                  Expanded(
                    child: Text(
                      [
                        if (s.label.isNotEmpty) s.label else s.locationText,
                        if (s.type == 'SHOP')
                          '(${s.items.where((i) => i.isValid).length} items)',
                      ].join(' '),
                      style: OraTypography.body(OraColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// Review-pane cash breakdown for buy_deliver — delivery offer + shopping
/// budget + disclosed service fee (server-computed when available).
class _ShoppingSummaryCard extends StatelessWidget {
  const _ShoppingSummaryCard({required this.state});

  final RideRequestUiState state;

  @override
  Widget build(BuildContext context) {
    final budget = state.shoppingBudgetMinor;
    final serviceFee = state.pricingEstimate?.serviceFeeMinor;
    final stopFees = state.pricingEstimate?.stopFeesMinor;
    String fmt(int minor) =>
        formatOfferAmountMinor(minor, state.pricingEstimate?.currency ?? 'PKR');
    return OraCard(
      padding: const EdgeInsets.all(OraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cash on delivery',
            style: OraTypography.label(OraColors.textSecondary),
          ),
          const SizedBox(height: OraSpacing.xs),
          _MoneyRow(
            label: 'Shopping budget',
            value: budget != null ? fmt(budget) : '—',
          ),
          if (serviceFee != null && serviceFee > 0)
            _MoneyRow(label: 'Service fee', value: fmt(serviceFee)),
          if (stopFees != null && stopFees > 0)
            _MoneyRow(label: 'Extra-stop fee', value: fmt(stopFees)),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'Paid to the driver in cash after you approve itemized prices. '
            'Delivery fare is your negotiated offer above.',
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: OraTypography.body(OraColors.textSecondary)),
          Text(
            value,
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
