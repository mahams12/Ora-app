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
import '../../domain/models/ride_category_option.dart';
import '../view_models/ride_request_view_model.dart';
import '../widgets/ride_category_selector.dart';
import '../widgets/ride_location_placeholder.dart';

/// Passenger ride compose + review. Create is gated without real pricing/GPS.
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

    ref.listen(rideRequestViewModelProvider, (prev, next) {
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
    required this.onContinue,
  });

  final RideRequestUiState state;
  final double padding;
  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final ValueChanged<String> onPickupChanged;
  final ValueChanged<String> onDestinationChanged;
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
                'Enter places as text. Coordinates stay unresolved until '
                'location services are ready.',
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
                          hint: 'Pickup area or landmark',
                          textInputAction: TextInputAction.next,
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.radio_button_checked,
                          onChanged: onPickupChanged,
                        ),
                        const SizedBox(height: OraSpacing.sm),
                        OraTextField(
                          controller: destinationController,
                          label: 'Destination',
                          hint: 'Where are you headed?',
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.words,
                          prefixIcon: Icons.location_on_outlined,
                          onChanged: onDestinationChanged,
                          onSubmitted: (_) {
                            if (state.canAdvanceToReview) onContinue();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OraSpacing.sm),
              _StatusChip(
                label: state.hasPickupText
                    ? 'Pickup entered · unresolved'
                    : 'Pickup needed',
                ok: state.hasPickupText,
              ),
              const SizedBox(height: OraSpacing.xs),
              _StatusChip(
                label: state.hasDestinationText
                    ? 'Destination entered · unresolved'
                    : 'Destination needed',
                ok: state.hasDestinationText,
              ),
              const SizedBox(height: OraSpacing.lg),
              const OraSectionHeader(
                title: 'Saved & recent',
                description:
                    'Saved places are not connected. Nothing is invented locally.',
              ),
              const SizedBox(height: OraSpacing.sm),
              const OraEmptyState(
                icon: Icons.bookmark_border_rounded,
                title: 'No saved places',
                message:
                    'When saved places ship, they will appear here. '
                    'Continue with typed locations for now.',
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
            label: 'Confirm destination',
            onPressed: state.canAdvanceToReview ? onContinue : null,
          ),
        ),
      ],
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
                      state.pickupText.trim(),
                      style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    ),
                    Text(
                      'to ${state.destinationText.trim()}',
                      style: OraTypography.body(OraColors.textSecondary),
                    ),
                    const SizedBox(height: OraSpacing.xxs),
                    Text(
                      'Locations are text-only until GPS/geocoding ships',
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
