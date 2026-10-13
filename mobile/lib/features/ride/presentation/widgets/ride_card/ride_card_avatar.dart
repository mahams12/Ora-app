import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';

/// Flutter-built empty avatar — navy circle + Ora-blue silhouette.
///
/// Frozen product decision: do not use a PNG for the empty photo slot.
class RideCardAvatarPlaceholder extends StatelessWidget {
  const RideCardAvatarPlaceholder({
    super.key,
    this.size = 40,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF12182B),
        border: Border.all(
          color: OraColors.info.withValues(alpha: 0.55),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const CustomPaint(
        painter: _SilhouettePainter(color: OraColors.info),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.85);
    final cx = size.width / 2;
    final headR = size.width * 0.18;
    canvas.drawCircle(Offset(cx, size.height * 0.36), headR, paint);

    final body = Path()
      ..moveTo(size.width * 0.22, size.height * 0.88)
      ..quadraticBezierTo(
        cx,
        size.height * 0.52,
        size.width * 0.78,
        size.height * 0.88,
      )
      ..close();
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant _SilhouettePainter oldDelegate) =>
      oldDelegate.color != color;
}
