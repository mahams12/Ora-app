import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ora_colors.dart';
import '../ora_motion.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

/// Stars-only rating control (1–5). No tips/tags — matches Phase 2N contract.
///
/// Not wired to the backend in Slice A; presentation primitive only.
class OraStarRating extends StatelessWidget {
  const OraStarRating({
    super.key,
    this.value = 0,
    this.onChanged,
    this.size = 28,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Current selection in `0…5` (`0` = none selected).
  final int value;

  /// When null, the control is display-only.
  final ValueChanged<int>? onChanged;

  final double size;
  final bool enabled;
  final String? semanticLabel;

  bool get _interactive => enabled && onChanged != null;

  @override
  Widget build(BuildContext context) {
    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final filled = starValue <= value;
        final icon = Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? OraColors.primary : OraColors.starEmpty,
        );

        if (!_interactive) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: icon,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Semantics(
            button: true,
            selected: filled,
            label: '$starValue star${starValue == 1 ? '' : 's'}',
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged?.call(starValue);
              },
              customBorder: const CircleBorder(),
              child: AnimatedScale(
                scale: filled && starValue == value ? 1.08 : 1,
                duration: OraMotion.select,
                curve: OraMotion.standard,
                child: icon,
              ),
            ),
          ),
        );
      }),
    );

    return Semantics(
      label: semanticLabel ?? 'Rating $value of 5',
      value: '$value',
      child: stars,
    );
  }
}

/// Compact read-only star + numeric label (e.g. "4.9").
class OraStarLabel extends StatelessWidget {
  const OraStarLabel({required this.ratingText, super.key, this.iconSize = 12});

  final String ratingText;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? OraColors.textMuted : OraColors.textSecondaryLight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: iconSize, color: OraColors.primary),
        const SizedBox(width: OraSpacing.xxs),
        Text(ratingText, style: OraTypography.caption(color)),
      ],
    );
  }
}
