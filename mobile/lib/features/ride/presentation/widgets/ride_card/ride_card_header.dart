import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';
import 'ride_card_status.dart';

class RideCardHeader extends StatelessWidget {
  const RideCardHeader({
    super.key,
    this.title,
    this.statusLabel,
    this.statusKind = RideCardStatusKind.neutral,
    this.emphasized = false,
    this.secondaryStatusLabel,
    this.trailing,
  });

  final String? title;
  final String? statusLabel;
  final RideCardStatusKind statusKind;
  final bool emphasized;
  final String? secondaryStatusLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.trim().isNotEmpty;
    final hasStatus = statusLabel != null && statusLabel!.trim().isNotEmpty;
    final hasSecondary =
        secondaryStatusLabel != null && secondaryStatusLabel!.trim().isNotEmpty;
    if (!hasTitle && !hasStatus && !hasSecondary && trailing == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasStatus)
          RideCardStatus(
            label: statusLabel!,
            emphasized: emphasized,
            kind: statusKind,
          ),
        if (hasSecondary) ...[
          if (hasStatus) const SizedBox(width: OraSpacing.xs),
          RideCardSecondaryStatus(label: secondaryStatusLabel!),
        ],
        if (hasTitle) ...[
          if (hasStatus || hasSecondary) const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: Text(
              title!,
              style: OraTypography.bodyEmphasis(OraColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (trailing != null) ...[
          const SizedBox(width: OraSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}
