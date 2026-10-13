import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Fare block — large white number + muted caption (Your earnings / Agreed fare).
class RideCardFare extends StatelessWidget {
  const RideCardFare({
    super.key,
    this.fareLabel,
    this.fareCaption,
    this.secondaryFareLabel,
    this.emphasized = false,
    this.inline = false,
    this.alignEnd = true,
  });

  final String? fareLabel;
  final String? fareCaption;
  final String? secondaryFareLabel;
  final bool emphasized;
  final bool inline;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    if (fareLabel == null && secondaryFareLabel == null) {
      return const SizedBox.shrink();
    }

    final fareStyle = OraTypography.numeric(
      OraColors.textPrimary,
    ).copyWith(
      fontSize: inline ? 18 : 20,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: emphasized ? Colors.white : OraColors.textPrimary,
    );

    if (inline && fareCaption == null && secondaryFareLabel == null) {
      return Text(fareLabel ?? secondaryFareLabel!, style: fareStyle);
    }

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (fareLabel != null) Text(fareLabel!, style: fareStyle),
        if (fareCaption != null) ...[
          const SizedBox(height: 2),
          Text(
            fareCaption!,
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
        if (secondaryFareLabel != null)
          Text(
            secondaryFareLabel!,
            style: OraTypography.caption(OraColors.textMuted),
          ),
      ],
    );
  }
}
