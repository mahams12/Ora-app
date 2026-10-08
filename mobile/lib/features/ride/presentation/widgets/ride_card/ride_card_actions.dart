import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import 'ride_card_model.dart';

class RideCardActions extends StatelessWidget {
  const RideCardActions({
    required this.actions,
    super.key,
    this.compact = true,
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
          if (i > 0) const SizedBox(width: OraSpacing.xs),
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
    this.compact = true,
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
    final height = widget.compact ? 40.0 : 44.0;

    final bg = action.isDestructive
        ? OraColors.dangerMuted
        : isPrimary
            ? OraColors.info
            : Colors.transparent;
    final fg = action.isDestructive
        ? OraColors.dangerForeground
        : isPrimary
            ? Colors.white
            : OraColors.textSecondary;
    final border = action.isDestructive
        ? OraColors.danger.withValues(alpha: 0.5)
        : isPrimary
            ? OraColors.info
            : OraColors.border;

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
                color: bg,
                borderRadius: BorderRadius.circular(OraRadius.button),
                border: Border.all(color: border),
                boxShadow: isPrimary && enabled
                    ? [
                        BoxShadow(
                          color: OraColors.info.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: action.isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Text(
                      action.label,
                      style: OraTypography.button(fg).copyWith(fontSize: 13),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
