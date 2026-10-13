import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_elevation.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';

class RideCardActions extends StatelessWidget {
  const RideCardActions({
    required this.actions,
    super.key,
    this.compact = false,
  });

  final List<RideCardActionSpec> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    if (actions.length == 1) {
      return _ActionButton(
        action: actions.first,
        expand: true,
        compact: compact,
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: OraSpacing.sm),
          Expanded(
            child: _ActionButton(
              action: actions[i],
              compact: compact,
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.action,
    this.expand = false,
    this.compact = false,
  });

  final RideCardActionSpec action;
  final bool expand;
  final bool compact;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final enabled = action.onPressed != null && !action.isLoading;
    final isPrimary = action.isPrimary && !action.isDestructive;
    final height = widget.compact ? 44.0 : 48.0;

    final Color fg;
    final Color border;
    Gradient? gradient;
    Color? bg;
    List<BoxShadow>? shadows;

    if (action.isDestructive) {
      bg = const Color(0xFF1A1520);
      fg = OraColors.dangerForeground;
      border = OraColors.danger.withValues(alpha: 0.45);
    } else if (isPrimary) {
      // Match OraButton primary — app gold/yellow.
      gradient = const LinearGradient(
        colors: [OraColors.gold, OraColors.goldDeep, OraColors.gold],
        stops: [0, 0.5, 1],
      );
      fg = OraColors.primaryForeground;
      border = OraColors.goldDeep;
      shadows = OraElevation.primaryButtonShadow;
    } else {
      // Sunken secondary (Decline / Navigate).
      bg = const Color(0xFF151A28);
      fg = OraColors.textPrimary;
      border = OraColors.border;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 8,
          offset: const Offset(0, 3),
          spreadRadius: -2,
        ),
      ];
    }

    return Semantics(
      button: true,
      label: action.semanticLabel ?? action.label,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? action.onPressed : null,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: OraMotion.press,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: OraMotion.fade,
            child: Container(
              height: height,
              width: widget.expand ? double.infinity : null,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: enabled ? gradient : null,
                color: enabled
                    ? bg
                    : OraColors.disabled.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(OraRadius.button),
                border: Border.all(color: border),
                boxShadow: enabled ? shadows : null,
              ),
              child: action.isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (action.icon != null) ...[
                          Icon(action.icon, size: 16, color: fg),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          action.label,
                          style:
                              OraTypography.button(fg).copyWith(fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
