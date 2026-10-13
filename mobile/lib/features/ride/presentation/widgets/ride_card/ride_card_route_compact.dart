import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Epic-style pickup → destination with glowing route spine.
class RideCardRouteCompact extends StatelessWidget {
  const RideCardRouteCompact({
    required this.pickupLabel,
    required this.destinationLabel,
    super.key,
    this.inline = false,
    this.showPickupCaption = false,
    this.showChevron = false,
  });

  final String pickupLabel;
  final String destinationLabel;

  /// Single-line "A → B" for dense history.
  final bool inline;
  final bool showPickupCaption;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _RouteSpine(height: 36),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Text(
                    '$pickupLabel → $destinationLabel',
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (showChevron)
            const Icon(
              Icons.chevron_right_rounded,
              color: OraColors.textMuted,
              size: 22,
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _RouteSpine(height: 52),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showPickupCaption)
                Text(
                  'Pickup',
                  style: OraTypography.caption(OraColors.info),
                ),
              Text(
                pickupLabel,
                style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: OraSpacing.xs),
              Text(
                destinationLabel,
                style: OraTypography.body(OraColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (showChevron)
          const Icon(
            Icons.chevron_right_rounded,
            color: OraColors.textMuted,
            size: 22,
          ),
      ],
    );
  }
}

class _RouteSpine extends StatelessWidget {
  const _RouteSpine({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: height,
      child: CustomPaint(painter: _SpinePainter()),
    );
  }
}

class _SpinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final top = Offset(cx, 6);
    final bottom = Offset(cx, size.height - 6);
    final mid = Offset(cx + 3, size.height * 0.5);

    final glow = Paint()
      ..color = OraColors.info.withValues(alpha: 0.35)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final line = Paint()
      ..color = OraColors.info
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, bottom.dx, bottom.dy);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);

    canvas.drawCircle(top, 5, Paint()..color = OraColors.info);
    canvas.drawCircle(top, 2, Paint()..color = Colors.white);

    canvas.drawCircle(
      bottom,
      5,
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
