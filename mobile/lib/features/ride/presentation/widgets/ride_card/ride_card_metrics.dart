import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Compact single-line metrics — distance · duration · payment.
class RideCardMetrics extends StatelessWidget {
  const RideCardMetrics({
    super.key,
    this.distanceLabel,
    this.durationLabel,
    this.paymentLabel,
    this.passengerCountLabel,
    this.serviceLabel,
  });

  final String? distanceLabel;
  final String? durationLabel;
  final String? paymentLabel;
  final String? passengerCountLabel;
  final String? serviceLabel;

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
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join('  ·  '),
      style: OraTypography.caption(OraColors.textSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
