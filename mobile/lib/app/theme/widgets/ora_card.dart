import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_elevation.dart';
import '../ora_motion.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';

enum OraCardVariant { standard, elevated, selectable }

/// Surface / card primitive matching prototype section cards.
class OraCard extends StatefulWidget {
  const OraCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(OraSpacing.md),
    this.onTap,
    this.variant = OraCardVariant.standard,
    this.selected = false,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final OraCardVariant variant;
  final bool selected;
  final double? borderRadius;

  @override
  State<OraCard> createState() => _OraCardState();
}

class _OraCardState extends State<OraCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = widget.borderRadius ?? OraRadius.card;
    final interactive = widget.onTap != null;

    final bg = widget.selected
        ? OraColors.primaryMuted
        : isDark
        ? OraColors.surfaceElevated
        : Colors.white;

    final borderColor = widget.selected
        ? OraColors.primary
        : isDark
        ? OraColors.border
        : theme.colorScheme.outline.withValues(alpha: 0.5);

    final shadows = widget.variant == OraCardVariant.elevated
        ? OraElevation.raisedShadow
        : null;

    final surface = AnimatedContainer(
      duration: OraMotion.select,
      curve: OraMotion.standard,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor,
          width: widget.selected ? 1.5 : 1,
        ),
        boxShadow: shadows,
      ),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (!interactive) return surface;

    return Semantics(
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: surface,
        ),
      ),
    );
  }
}

/// Lightweight section container (padding + optional title slot via child).
class OraSectionContainer extends StatelessWidget {
  const OraSectionContainer({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.fromLTRB(
      OraSpacing.md,
      OraSpacing.md,
      OraSpacing.md,
      OraSpacing.xs,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return OraCard(padding: padding, child: child);
  }
}
