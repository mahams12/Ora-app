import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_status.dart';

class RideCardHeader extends StatelessWidget {
  const RideCardHeader({
    super.key,
    this.title,
    this.statusLabel,
    this.emphasized = false,
    this.trailing,
  });

  final String? title;
  final String? statusLabel;
  final bool emphasized;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title != null && title!.trim().isNotEmpty;
    final hasStatus = statusLabel != null && statusLabel!.trim().isNotEmpty;
    if (!hasTitle && !hasStatus && trailing == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (hasStatus) RideCardStatus(label: statusLabel!, emphasized: emphasized),
        if (hasTitle) ...[
          if (hasStatus) const SizedBox(width: OraSpacing.sm),
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
