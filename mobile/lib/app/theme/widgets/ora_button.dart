import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ora_colors.dart';
import '../ora_elevation.dart';
import '../ora_motion.dart';
import '../ora_radius.dart';
import '../ora_spacing.dart';
import '../ora_typography.dart';

enum OraButtonVariant { primary, secondary, ghost, danger, outline }

/// Prototype-faithful Ora button with press scale and loading state.
class OraButton extends StatefulWidget {
  const OraButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = OraButtonVariant.primary,
    this.isLoading = false,
    this.expand = true,
    this.leadingIcon,
    this.trailingIcon,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final OraButtonVariant variant;
  final bool isLoading;
  final bool expand;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final String? semanticLabel;

  @override
  State<OraButton> createState() => _OraButtonState();
}

class _OraButtonState extends State<OraButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (!_enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foreground,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(widget.leadingIcon, size: 18, color: _foreground),
                const SizedBox(width: OraSpacing.xs),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.button(_foreground),
                ),
              ),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: OraSpacing.xs),
                Icon(widget.trailingIcon, size: 18, color: _foreground),
              ],
            ],
          );

    final button = AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: OraMotion.press,
      curve: OraMotion.standard,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _enabled
                ? () {
                    HapticFeedback.selectionClick();
                    widget.onPressed?.call();
                  }
                : null,
            onTapDown: _enabled ? (_) => _setPressed(true) : null,
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            borderRadius: BorderRadius.circular(OraRadius.button),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(OraRadius.button),
                gradient: _gradient,
                color: _gradient == null ? _background : null,
                border: _border,
                boxShadow: _enabled ? _shadow : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: OraSpacing.md,
                  vertical: OraSpacing.sm,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );

    final semantics = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      child: button,
    );

    if (!widget.expand) return semantics;
    return SizedBox(width: double.infinity, child: semantics);
  }

  Color get _foreground {
    if (!_enabled) return OraColors.disabledForeground;
    return switch (widget.variant) {
      OraButtonVariant.primary => OraColors.primaryForeground,
      OraButtonVariant.secondary => OraColors.secondaryForeground,
      OraButtonVariant.ghost ||
      OraButtonVariant.outline => OraColors.textSecondary,
      OraButtonVariant.danger => OraColors.dangerForeground,
    };
  }

  Color? get _background {
    if (!_enabled) return OraColors.disabled.withValues(alpha: 0.35);
    return switch (widget.variant) {
      OraButtonVariant.primary || OraButtonVariant.secondary => null,
      OraButtonVariant.ghost ||
      OraButtonVariant.outline => const Color(0x14FFFFFF),
      OraButtonVariant.danger => OraColors.dangerMuted,
    };
  }

  Gradient? get _gradient {
    if (!_enabled) return null;
    return switch (widget.variant) {
      OraButtonVariant.primary => const LinearGradient(
        colors: [OraColors.gold, OraColors.goldDeep, OraColors.gold],
        stops: [0, 0.5, 1],
      ),
      OraButtonVariant.secondary => const LinearGradient(
        colors: [OraColors.teal, OraColors.tealDeep],
      ),
      _ => null,
    };
  }

  Border? get _border {
    if (widget.variant == OraButtonVariant.outline) {
      return Border.all(color: OraColors.border, width: 1.5);
    }
    return null;
  }

  List<BoxShadow>? get _shadow {
    return switch (widget.variant) {
      OraButtonVariant.primary => OraElevation.primaryButtonShadow,
      OraButtonVariant.secondary => OraElevation.secondaryButtonShadow,
      _ => null,
    };
  }
}

class OraButtonRow extends StatelessWidget {
  const OraButtonRow({
    required this.children,
    super.key,
    this.spacing = OraSpacing.sm,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: spacing, runSpacing: spacing, children: children);
  }
}
