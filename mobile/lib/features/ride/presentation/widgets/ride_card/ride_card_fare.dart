import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Compact fare — single numeric emphasis, optional muted caption.
class RideCardFare extends StatelessWidget {
  const RideCardFare({
    super.key,
    this.fareLabel,
    this.fareCaption,
    this.secondaryFareLabel,
    this.emphasized = false,
    this.inline = false,
  });

  final String? fareLabel;
  final String? fareCaption;
  final String? secondaryFareLabel;
  final bool emphasized;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (fareLabel == null && secondaryFareLabel == null) {
      return const SizedBox.shrink();
    }

    final fareStyle = OraTypography.numeric(
      emphasized ? OraColors.info : OraColors.textPrimary,
    ).copyWith(fontSize: inline ? 16 : 18, height: 1.1);

    if (inline) {
      return Text(fareLabel ?? secondaryFareLabel!, style: fareStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (fareCaption != null)
          Text(
            fareCaption!,
            style: OraTypography.caption(OraColors.textMuted),
          ),
        if (fareLabel != null) Text(fareLabel!, style: fareStyle),
        if (secondaryFareLabel != null)
          Text(
            secondaryFareLabel!,
            style: OraTypography.caption(OraColors.textMuted),
          ),
      ],
    );
  }
}
