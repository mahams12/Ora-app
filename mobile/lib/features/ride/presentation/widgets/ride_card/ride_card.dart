import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_radius.dart';
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
  const RideCard({required this.model, super.key});

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
                  OraColors.surfaceElevated,
                  OraColors.surfaceElevated,
                  OraColors.surfaceElevated,
                ]
              : const [
                  OraColors.surfaceElevated,
                  OraColors.surfaceElevated,
                  OraColors.surfaceElevated,
                ],
        ),
        border: Border.all(
          color: active
              ? OraColors.info.withValues(alpha: 0.55)
              : OraColors.border.withValues(alpha: 0.9),
          width: active ? 1.4 : 1,
        ),
        boxShadow: [
          const BoxShadow(
            color: OraColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 10),
            spreadRadius: -10,
          ),
          const BoxShadow(
            color: Colors.transparent,
            blurRadius: 0,
            offset: Offset(0, 1),
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
                fareCaptionFallback: 'Trip fare',
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
                width: 86,
                height: 118,
              ),
            if (model.showMapThumb) const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Always show profile slot (empty avatar / role
                      // label / star slot) — no invented identity.
                      Expanded(
                        child: RideCardParticipantRow(
                          participant:
                              model.participant ??
                              const RideCardParticipant(roleLabel: 'Rider'),
                          compact: true,
                          showRatingSlot: true,
                        ),
                      ),
                      if (model.expiresLabel != null)
                        _ExpiresPill(label: model.expiresLabel!),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.xs),
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
        const SizedBox(height: OraSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: model.distanceLabel != null || model.durationLabel != null
                  ? Row(
                      children: [
                        if (model.distanceLabel != null) ...[
                          const Icon(
                            Icons.directions_car_rounded,
                            size: 15,
                            color: OraColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              model.distanceLabel!,
                              style: OraTypography.caption(
                                OraColors.textSecondary,
                              ).copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (model.durationLabel != null) ...[
                          const SizedBox(width: OraSpacing.sm),
                          const Icon(
                            Icons.schedule_rounded,
                            size: 14,
                            color: OraColors.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              model.durationLabel!,
                              style: OraTypography.caption(
                                OraColors.textSecondary,
                              ).copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            if (model.categoryLabel != null) ...[
              const SizedBox(width: OraSpacing.xs),
              RideCardCategoryBadge(
                label: model.categoryLabel!,
                tone: model.categoryTone,
              ),
            ],
            const SizedBox(width: OraSpacing.sm),
            RideCardFare(
              fareLabel: model.fareLabel,
              fareCaption: model.fareCaption ?? 'Trip fare',
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

/// Orange-tinted countdown pill — "Respond within 14s" / age labels.
class _ExpiresPill extends StatelessWidget {
  const _ExpiresPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: OraColors.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(OraRadius.pill),
        border: Border.all(color: OraColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 12,
            color: OraColors.goldSharp,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: OraTypography.caption(
                OraColors.goldDeep,
              ).copyWith(fontWeight: FontWeight.w700, fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
          fallbackAssetPath: model.showCarAccent
              ? model.carAssetPath
              : model.carAssetPath,
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
