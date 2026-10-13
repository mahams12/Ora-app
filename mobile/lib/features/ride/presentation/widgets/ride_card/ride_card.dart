import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_actions.dart';
import 'ride_card_assets.dart';
import 'ride_card_category.dart';
import 'ride_card_fare.dart';
import 'ride_card_header.dart';
import 'ride_card_map_thumb.dart';
import 'ride_card_metrics.dart';
import 'ride_card_model.dart';
import 'ride_card_participant.dart';
import 'ride_card_route_compact.dart';
import 'ride_card_vehicle.dart';

export 'ride_card_adapters.dart';
export 'ride_card_location_label.dart';
export 'ride_card_model.dart';

/// Shared premium Ora ride card — epic layout with empty slots when data absent.
class RideCard extends StatefulWidget {
  const RideCard({
    required this.model,
    super.key,
  });

  final RideCardModel model;

  @override
  State<RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<RideCard> {
  bool _pressed = false;

  RideCardModel get model => widget.model;

  @override
  Widget build(BuildContext context) {
    final interactive = model.onTap != null;
    final active = model.isActiveTone;

    final surface = AnimatedContainer(
      duration: OraMotion.select,
      curve: OraMotion.standard,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? const [
                  Color(0xFF1A2748),
                  Color(0xFF141E36),
                  Color(0xFF0F1628),
                ]
              : const [
                  Color(0xFF181F36),
                  Color(0xFF141A2E),
                  Color(0xFF101624),
                ],
        ),
        border: Border.all(
          color: active
              ? OraColors.info.withValues(alpha: 0.55)
              : OraColors.border.withValues(alpha: 0.9),
          width: active ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 10),
            spreadRadius: -10,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.04),
            blurRadius: 0,
            offset: const Offset(0, 1),
          ),
          if (active)
            BoxShadow(
              color: OraColors.info.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OraSpacing.md,
          OraSpacing.md,
          OraSpacing.md,
          OraSpacing.md,
        ),
        child: _RideCardBody(model: model),
      ),
    );

    final labeled = Semantics(
      container: true,
      explicitChildNodes: true,
      label: model.semanticsLabel ?? 'Ride ${model.rideId}',
      child: surface,
    );

    if (!interactive) return labeled;

    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: model.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: labeled,
        ),
      ),
    );
  }
}

class _RideCardBody extends StatelessWidget {
  const _RideCardBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    switch (model.variant) {
      case RideCardVariant.openRequest:
        return _OpenRideBody(model: model);
      case RideCardVariant.driverJob:
        return model.isActiveTone
            ? _ActiveDriverJobBody(model: model)
            : _HistoryBody(
                model: model,
                fareCaptionFallback: 'Your earnings',
                showPhoneSlot: true,
              );
      case RideCardVariant.passengerHistory:
        return _HistoryBody(
          model: model,
          fareCaptionFallback: model.statusKind == RideCardStatusKind.danger
              ? 'Cancelled'
              : (model.paymentLabel == null
                  ? null
                  : 'Paid (${model.paymentLabel})'),
          showPhoneSlot: true,
        );
      case RideCardVariant.offer:
        return _OfferBody(model: model);
    }
  }
}

/// Open rides — epic request card with empty profile slots when unknown.
class _OpenRideBody extends StatelessWidget {
  const _OpenRideBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (model.showMapThumb)
              RideCardMapThumb(
                pickupLat: model.pickupLat,
                pickupLng: model.pickupLng,
                destinationLat: model.destinationLat,
                destinationLng: model.destinationLng,
                width: 84,
                height: 124,
              ),
            if (model.showMapThumb) const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      if (model.expiresLabel != null)
                        Text(
                          model.expiresLabel!,
                          style: OraTypography.caption(OraColors.textMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  // Always show profile slot (empty avatar / blank name / star slot).
                  RideCardParticipantRow(
                    participant: model.participant,
                    compact: true,
                    showRatingSlot: true,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  RideCardRouteCompact(
                    pickupLabel: model.pickupLabel,
                    destinationLabel: model.destinationLabel,
                    showPickupCaption: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.md),
        // Metrics on their own row so distance/duration are not clipped by
        // the car + fare competition for horizontal space.
        RideCardMetrics(
          distanceLabel: model.distanceLabel,
          durationLabel: model.durationLabel,
          withIcons: true,
        ),
        const SizedBox(height: OraSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (model.showCarAccent) ...[
              RideCardAssetImage(
                assetPath: model.carAssetPath,
                width: 76,
                height: 44,
              ),
              const SizedBox(width: OraSpacing.sm),
            ],
            Expanded(
              child: model.categoryLabel != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: RideCardCategoryBadge(
                        label: model.categoryLabel!,
                        tone: model.categoryTone,
                      ),
                    )
                  : const SizedBox(height: 22),
            ),
            const SizedBox(width: OraSpacing.sm),
            RideCardFare(
              fareLabel: model.fareLabel,
              fareCaption: model.fareCaption ?? 'Your earnings',
              emphasized: true,
            ),
          ],
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.md),
          RideCardActions(actions: model.actions),
        ],
      ],
    );
  }
}

/// Active driver job — map banner + empty passenger/vehicle slots.
class _ActiveDriverJobBody extends StatelessWidget {
  const _ActiveDriverJobBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            RideCardMapBanner(
              pickupLat: model.pickupLat,
              pickupLng: model.pickupLng,
              destinationLat: model.destinationLat,
              destinationLng: model.destinationLng,
              carAssetPath: model.showCarAccent ? model.carAssetPath : null,
            ),
            Positioned(
              top: OraSpacing.sm,
              left: OraSpacing.sm,
              right: OraSpacing.sm,
              child: RideCardHeader(
                statusLabel: model.statusLabel,
                statusKind: model.statusKind,
                emphasized: true,
                secondaryStatusLabel: model.secondaryStatusLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        Text(
          '${model.pickupLabel} → ${model.destinationLabel}',
          style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (model.timestampLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            model.timestampLabel!,
            style: OraTypography.caption(OraColors.info),
          ),
        ],
        const SizedBox(height: OraSpacing.sm),
        RideCardParticipantRow(
          participant: model.participant,
          showRatingSlot: true,
          showPhoneSlot: true,
          showChatSlot: true,
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardVehicleRow(
          vehicle: model.vehicle,
          fallbackAssetPath: model.showCarAccent ? model.carAssetPath : null,
          showPlateSlot: model.vehicle?.registration?.trim().isNotEmpty == true,
        ),
        const SizedBox(height: OraSpacing.md),
        RideCardMetricsGrid(
          fareLabel: model.fareLabel,
          fareCaption: model.fareCaption ?? 'Agreed fare',
          distanceLabel: model.distanceLabel,
          distanceCaption: 'Total distance',
          durationLabel: model.durationLabel,
          durationCaption: 'Est. time',
          forceThreeSlots: true,
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.md),
          RideCardActions(actions: model.actions),
        ],
      ],
    );
  }
}

/// History cards — status, route, empty person/vehicle slots, 3 metrics.
class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.model,
    this.fareCaptionFallback,
    this.showPhoneSlot = false,
  });

  final RideCardModel model;
  final String? fareCaptionFallback;
  final bool showPhoneSlot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideCardHeader(
          statusLabel: model.statusLabel,
          statusKind: model.statusKind,
          emphasized: model.isActiveTone,
          trailing: model.timestampLabel == null
              ? null
              : Text(
                  model.timestampLabel!,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardRouteCompact(
          pickupLabel: model.pickupLabel,
          destinationLabel: model.destinationLabel,
          inline: true,
          showChevron: model.onTap != null,
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardParticipantRow(
          participant: model.participant,
          compact: true,
          showRatingSlot: true,
          showPhoneSlot: showPhoneSlot,
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardVehicleRow(
          vehicle: model.vehicle,
          fallbackAssetPath:
              model.showCarAccent ? model.carAssetPath : model.carAssetPath,
          // Empty plate outline looked like hidden registration — only when real.
          showPlateSlot: model.vehicle?.registration?.trim().isNotEmpty == true,
        ),
        const SizedBox(height: OraSpacing.md),
        RideCardMetricsGrid(
          fareLabel: model.fareLabel,
          fareCaption: model.fareCaption ?? fareCaptionFallback,
          distanceLabel: model.distanceLabel,
          durationLabel: model.durationLabel,
          durationCaption: model.isActiveTone ? 'Est. time' : 'Duration',
          forceThreeSlots: true,
          fareCaptionColor: model.statusKind == RideCardStatusKind.danger
              ? OraColors.dangerForeground
              : null,
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.md),
          RideCardActions(actions: model.actions),
        ],
      ],
    );
  }
}

/// Offers inbox — empty driver slot when snapshot has no name.
class _OfferBody extends StatelessWidget {
  const _OfferBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideCardHeader(
          statusLabel: model.statusLabel,
          statusKind: model.statusKind,
          emphasized: model.isActiveTone,
          trailing: model.expiresLabel == null
              ? null
              : Text(
                  model.expiresLabel!,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardParticipantRow(
          participant: model.participant,
          showRatingSlot: true,
        ),
        const SizedBox(height: OraSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (model.showCarAccent)
              RideCardAssetImage(
                assetPath: model.carAssetPath,
                width: 80,
                height: 44,
              ),
            if (model.showCarAccent) const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: RideCardMetrics(
                paymentLabel: model.paymentLabel,
                serviceLabel: model.serviceLabel,
              ),
            ),
            RideCardFare(
              fareLabel: model.fareLabel,
              fareCaption: model.fareCaption ?? 'Driver offer',
              emphasized: true,
            ),
          ],
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.md),
          RideCardActions(actions: model.actions),
        ],
      ],
    );
  }
}
