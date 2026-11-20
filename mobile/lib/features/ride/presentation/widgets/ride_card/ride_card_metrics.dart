import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_assets.dart';

/// Inline metrics — distance · duration · payment.
class RideCardMetrics extends StatelessWidget {
  const RideCardMetrics({
    super.key,
    this.distanceLabel,
    this.durationLabel,
    this.paymentLabel,
    this.passengerCountLabel,
    this.serviceLabel,
    this.withIcons = false,
  });

  final String? distanceLabel;
  final String? durationLabel;
  final String? paymentLabel;
  final String? passengerCountLabel;
  final String? serviceLabel;
  final bool withIcons;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (distanceLabel != null && distanceLabel!.isNotEmpty) distanceLabel!,
      if (durationLabel != null && durationLabel!.isNotEmpty) durationLabel!,
      if (paymentLabel != null && paymentLabel!.isNotEmpty) paymentLabel!,
      if (passengerCountLabel != null && passengerCountLabel!.isNotEmpty)
        passengerCountLabel!,
      if (serviceLabel != null && serviceLabel!.isNotEmpty) serviceLabel!,
    ];

    if (!withIcons) {
      if (parts.isEmpty) return const SizedBox.shrink();
      return Text(
        parts.join('  ·  '),
        style: OraTypography.caption(OraColors.textSecondary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Epic open-ride metrics: one steering icon + ellipsized distance/duration.
    // Keep a single Flexible text child so narrow cards never overflow.
    final line = [
      if (distanceLabel != null && distanceLabel!.isNotEmpty) distanceLabel!,
      if (durationLabel != null && durationLabel!.isNotEmpty) durationLabel!,
    ].join('  ·  ');
    final empty = line.isEmpty;

    return Row(
      children: [
        RideCardAssetImage(
          assetPath: RideCardAssets.steering,
          width: 16,
          height: 16,
          opacity: empty ? 0.35 : 1,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            line,
            style: OraTypography.caption(OraColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Three-column metrics footer — always three slots.
///
/// Missing values render as a visible em dash ("—"), never blank space that
/// looks like hidden/clipped text.
class RideCardMetricsGrid extends StatelessWidget {
  const RideCardMetricsGrid({
    super.key,
    this.fareLabel,
    this.fareCaption,
    this.distanceLabel,
    this.distanceCaption = 'Distance',
    this.durationLabel,
    this.durationCaption = 'Duration',
    this.forceThreeSlots = true,
    this.fareCaptionColor,
  });

  final String? fareLabel;
  final String? fareCaption;
  final String? distanceLabel;
  final String distanceCaption;
  final String? durationLabel;
  final String durationCaption;
  final bool forceThreeSlots;
  final Color? fareCaptionColor;

  static const missingValue = '—';

  @override
  Widget build(BuildContext context) {
    final cancelledCaption =
        (fareCaption ?? '').trim().toLowerCase() == 'cancelled';
    final resolvedFareCaptionColor = fareCaptionColor ??
        (cancelledCaption
            ? OraColors.dangerForeground
            : OraColors.info);

    final cells = forceThreeSlots
        ? [
            _MetricCell(
              value: _visibleValue(fareLabel),
              caption: fareCaption ?? '',
              captionColor: resolvedFareCaptionColor,
              valueMuted: !_hasText(fareLabel),
            ),
            _MetricCell(
              value: _visibleValue(distanceLabel),
              caption: distanceCaption,
              valueMuted: !_hasText(distanceLabel),
            ),
            _MetricCell(
              value: _visibleValue(durationLabel),
              caption: durationCaption,
              valueMuted: !_hasText(durationLabel),
            ),
          ]
        : <_MetricCell>[
            if (_hasText(fareLabel))
              _MetricCell(
                value: fareLabel!.trim(),
                caption: fareCaption ?? '',
                captionColor: resolvedFareCaptionColor,
              ),
            if (_hasText(distanceLabel))
              _MetricCell(value: distanceLabel!.trim(), caption: distanceCaption),
            if (_hasText(durationLabel))
              _MetricCell(value: durationLabel!.trim(), caption: durationCaption),
          ];
    if (cells.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: OraColors.border.withValues(alpha: 0.55),
            ),
          Expanded(child: cells[i]),
        ],
      ],
    );
  }

  static bool _hasText(String? raw) =>
      raw != null && raw.trim().isNotEmpty;

  static String _visibleValue(String? raw) =>
      _hasText(raw) ? raw!.trim() : missingValue;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.value,
    required this.caption,
    this.captionColor,
    this.valueMuted = false,
  });

  final String value;
  final String caption;
  final Color? captionColor;
  final bool valueMuted;

  @override
  Widget build(BuildContext context) {
    // Avoid fixed heights that clip caption glyphs (11.5px @ 1.35 line-height).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: OraTypography.numeric(
            valueMuted ? OraColors.textMuted : OraColors.textPrimary,
          ).copyWith(
            fontSize: 16,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            caption,
            style: OraTypography.caption(
              captionColor ?? OraColors.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
