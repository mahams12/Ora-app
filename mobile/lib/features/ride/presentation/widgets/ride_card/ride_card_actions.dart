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
            child: _ActionButton(action: actions[i], compact: compact),
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
      bg = OraColors.surfaceElevated;
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
      bg = OraColors.surfaceElevated;
      fg = OraColors.textPrimary;
      border = OraColors.border;
      shadows = [
        const BoxShadow(
          color: OraColors.shadow,
          blurRadius: 8,
          offset: Offset(0, 3),
          spreadRadius: -2,
        ),
      ];
    }

    final label = action.isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
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
                style: OraTypography.button(fg).copyWith(fontSize: 14),
              ),
            ],
          );

    Widget buttonBody = Container(
      height: height,
      width: widget.expand ? double.infinity : null,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: enabled ? gradient : null,
        color: enabled ? bg : OraColors.disabled.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(OraRadius.button),
        border: Border.all(color: border),
        boxShadow: enabled ? shadows : null,
      ),
      child: label,
    );

    // Dispatch-invite countdown — smooth perimeter sweep depleting with the
    // server-authoritative invite window. Reduced-motion users get the same
    // ring, stepped once per second instead of eased continuously.
    if (action.progress != null) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      // Capture the container by value — the closure must see the inner
      // body, not this variable after reassignment (else the painter wraps
      // the TweenAnimationBuilder in itself and the build recurses forever).
      final paintedChild = buttonBody;
      buttonBody = TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: action.progress,
          end: action.progress!.clamp(0.0, 1.0),
        ),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 950),
        curve: Curves.linear,
        builder: (context, value, _) => CustomPaint(
          foregroundPainter: _CountdownPerimeterPainter(
            progress: value,
            radius: OraRadius.button,
            trackColor: fg.withValues(alpha: 0.25),
            progressColor: fg,
          ),
          child: paintedChild,
        ),
      );
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
            child: buttonBody,
          ),
        ),
      ),
    );
  }
}

/// Sweeps a rounded-rect perimeter clockwise from the top-left, depleting as
/// `progress` → 0. Faint track shows the full border so the drain is legible.
class _CountdownPerimeterPainter extends CustomPainter {
  _CountdownPerimeterPainter({
    required this.progress,
    required this.radius,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final double radius;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(1.2),
      Radius.circular(radius),
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = trackColor;
    canvas.drawRRect(rrect, track);
    if (progress <= 0) return;
    final path = Path()..addRRect(rrect);
    final metric = path.computeMetrics().first;
    final draw = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
      draw,
    );
  }

  @override
  bool shouldRepaint(_CountdownPerimeterPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}
