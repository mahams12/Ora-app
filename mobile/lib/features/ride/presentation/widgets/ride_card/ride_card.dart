import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_actions.dart';
import 'ride_card_fare.dart';
import 'ride_card_header.dart';
import 'ride_card_metrics.dart';
import 'ride_card_model.dart';
import 'ride_card_participant.dart';
import 'ride_card_route_compact.dart';
import 'ride_card_route_preview.dart';
import 'ride_card_vehicle.dart';

export 'ride_card_adapters.dart';
export 'ride_card_location_label.dart';
export 'ride_card_model.dart';

/// Shared premium Ora ride card — compact marketplace density by variant.
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
        borderRadius: BorderRadius.circular(OraRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? const [
                  Color(0xFF1A2748),
                  Color(0xFF152040),
                  Color(0xFF12182B),
                ]
              : const [
                  Color(0xFF1B2340),
                  Color(0xFF161E36),
                  Color(0xFF12182B),
                ],
        ),
        border: Border.all(
          color: active
              ? OraColors.info.withValues(alpha: 0.4)
              : OraColors.border,
          width: active ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 14,
            offset: const Offset(0, 6),
            spreadRadius: -8,
          ),
          if (active)
            BoxShadow(
              color: OraColors.info.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          OraSpacing.md,
          OraSpacing.sm + 2,
          OraSpacing.md,
          OraSpacing.sm + 2,
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
      case RideCardVariant.passengerHistory:
        return _HistoryBody(model: model);
      case RideCardVariant.offer:
        return _OfferBody(model: model);
    }
  }
}

/// Driver Open Rides — ultra compact decision card.
class _OpenRideBody extends StatelessWidget {
  const _OpenRideBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideCardHeader(
          statusLabel: model.statusLabel,
          emphasized: model.isActiveTone,
          trailing: model.expiresLabel == null
              ? null
              : Text(
                  model.expiresLabel!,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
        ),
        const SizedBox(height: OraSpacing.sm),
        RideCardRouteCompact(
          pickupLabel: model.pickupLabel,
          destinationLabel: model.destinationLabel,
        ),
        const SizedBox(height: OraSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RideCardMetrics(
                distanceLabel: model.distanceLabel,
                durationLabel: model.durationLabel,
                paymentLabel: model.paymentLabel,
              ),
            ),
            if (model.fareLabel != null)
              RideCardFare(
                fareLabel: model.fareLabel,
                emphasized: model.isActiveTone,
                inline: true,
              ),
          ],
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.sm),
          RideCardActions(actions: model.actions, compact: true),
        ],
      ],
    );
  }
}

/// Driver / passenger my-rides — compact history density.
class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (model.fareLabel != null) model.fareLabel!,
      if (model.distanceLabel != null) model.distanceLabel!,
      if (model.durationLabel != null) model.durationLabel!,
      if (model.paymentLabel != null) model.paymentLabel!,
      if (model.timestampLabel != null) model.timestampLabel!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideCardHeader(
          statusLabel: model.statusLabel,
          emphasized: model.isActiveTone,
          trailing: model.timestampLabel == null || model.fareLabel != null
              ? null
              : Text(
                  model.timestampLabel!,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
        ),
        const SizedBox(height: OraSpacing.xs + 2),
        RideCardRouteCompact(
          pickupLabel: model.pickupLabel,
          destinationLabel: model.destinationLabel,
          inline: true,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.xs + 2),
          Text(
            meta.join('  ·  '),
            style: OraTypography.caption(OraColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (model.participant != null &&
            (model.participant!.hasIdentity || model.participant!.hasStats)) ...[
          const SizedBox(height: OraSpacing.xs),
          RideCardParticipantRow(participant: model.participant!),
        ],
        if (model.vehicle != null && model.vehicle!.hasAnyField) ...[
          const SizedBox(height: OraSpacing.xs),
          RideCardVehicleRow(vehicle: model.vehicle!),
        ],
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.sm),
          RideCardActions(actions: model.actions, compact: true),
        ],
      ],
    );
  }
}

/// Offers inbox — fare-forward; identity only when API supplies it.
class _OfferBody extends StatelessWidget {
  const _OfferBody({required this.model});

  final RideCardModel model;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RideCardHeader(
          title: model.title,
          statusLabel: model.statusLabel,
          emphasized: model.isActiveTone,
          trailing: model.expiresLabel == null
              ? null
              : Text(
                  model.expiresLabel!,
                  style: OraTypography.caption(OraColors.textMuted),
                ),
        ),
        if (model.participant != null && model.participant!.hasIdentity) ...[
          const SizedBox(height: OraSpacing.xs),
          RideCardParticipantRow(participant: model.participant!),
        ],
        if (model.showRoutePreview &&
            model.pickupLabel.isNotEmpty &&
            model.destinationLabel.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.xs),
          RideCardRoutePreview(
            pickupLabel: model.pickupLabel,
            destinationLabel: model.destinationLabel,
            pickupLat: model.pickupLat,
            pickupLng: model.pickupLng,
            destinationLat: model.destinationLat,
            destinationLng: model.destinationLng,
            compact: true,
          ),
        ],
        const SizedBox(height: OraSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RideCardMetrics(
                paymentLabel: model.paymentLabel,
                serviceLabel: model.serviceLabel,
              ),
            ),
            if (model.fareLabel != null)
              RideCardFare(
                fareLabel: model.fareLabel,
                emphasized: model.isActiveTone,
                inline: true,
              ),
          ],
        ),
        if (model.actions.isNotEmpty) ...[
          const SizedBox(height: OraSpacing.sm),
          RideCardActions(actions: model.actions, compact: true),
        ],
      ],
    );
  }
}
