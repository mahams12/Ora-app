import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Text-only pickup → dropoff — no painter, no map engine.
///
/// Preferred for marketplace list density (Open Rides / history).
class RideCardRouteCompact extends StatelessWidget {
  const RideCardRouteCompact({
    required this.pickupLabel,
    required this.destinationLabel,
    super.key,
    this.inline = false,
  });

  final String pickupLabel;
  final String destinationLabel;

  /// Single-line "A → B" for history density.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return Text(
        '$pickupLabel → $destinationLabel',
        style: OraTypography.body(OraColors.textSecondary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Endpoint(
          color: OraColors.info,
          label: pickupLabel,
          isLast: false,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Container(
            width: 2,
            height: 10,
            color: OraColors.info.withValues(alpha: 0.35),
          ),
        ),
        _Endpoint(
          color: OraColors.tealBright,
          label: destinationLabel,
          isLast: true,
        ),
      ],
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.color,
    required this.label,
    required this.isLast,
  });

  final Color color;
  final String label;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
