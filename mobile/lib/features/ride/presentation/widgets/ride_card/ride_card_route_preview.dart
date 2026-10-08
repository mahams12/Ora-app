import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';

/// Lightweight stylized route preview — no GoogleMap / no network tiles.
///
/// Uses real pickup/destination coordinates only to shape the curve when
/// available. Safe for scrolling lists (CustomPainter only).
class RideCardRoutePreview extends StatelessWidget {
  const RideCardRoutePreview({
    required this.pickupLabel,
    required this.destinationLabel,
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.compact = false,
  });

  final String pickupLabel;
  final String destinationLabel;
  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 72.0 : 96.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.md),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0E1528),
            Color(0xFF152040),
            Color(0xFF1A2A4A),
          ],
        ),
        border: Border.all(color: OraColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _RoutePreviewPainter(
                pickupLat: pickupLat,
                pickupLng: pickupLng,
                destinationLat: destinationLat,
                destinationLng: destinationLng,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              OraSpacing.sm,
              OraSpacing.xs,
              OraSpacing.sm,
              OraSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: OraColors.navy.withValues(alpha: 0.72),
              border: Border(
                top: BorderSide(color: OraColors.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EndpointRow(
                  color: OraColors.info,
                  label: 'Pickup',
                  value: pickupLabel,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Container(
                    width: 2,
                    height: 10,
                    color: OraColors.info.withValues(alpha: 0.35),
                  ),
                ),
                _EndpointRow(
                  color: OraColors.tealBright,
                  label: 'Dropoff',
                  value: destinationLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: OraTypography.caption(OraColors.textMuted),
              ),
              Text(
                value,
                style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x22152A4A), Color(0x00101828)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Soft grid
    final grid = Paint()
      ..color = OraColors.info.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final start = _mapPoint(size, pickupLat, pickupLng, isStart: true);
    final end = _mapPoint(size, destinationLat, destinationLng, isStart: false);
    final mid = Offset(
      (start.dx + end.dx) / 2,
      math.min(start.dy, end.dy) - size.height * 0.28,
    );

    final glow = Paint()
      ..color = OraColors.info.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
    canvas.drawPath(path, glow);

    final line = Paint()
      ..shader = LinearGradient(
        colors: [
          OraColors.info,
          OraColors.info.withValues(alpha: 0.85),
          OraColors.tealBright.withValues(alpha: 0.9),
        ],
      ).createShader(Rect.fromPoints(start, end))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    _drawPin(canvas, start, OraColors.info);
    _drawPin(canvas, end, OraColors.tealBright);
  }

  Offset _mapPoint(
    Size size,
    double? lat,
    double? lng, {
    required bool isStart,
  }) {
    final hasAll = pickupLat != null &&
        pickupLng != null &&
        destinationLat != null &&
        destinationLng != null &&
        lat != null &&
        lng != null;
    if (!hasAll) {
      return Offset(
        isStart ? size.width * 0.18 : size.width * 0.82,
        isStart ? size.height * 0.68 : size.height * 0.42,
      );
    }

    final minLat = math.min(pickupLat!, destinationLat!);
    final maxLat = math.max(pickupLat!, destinationLat!);
    final minLng = math.min(pickupLng!, destinationLng!);
    final maxLng = math.max(pickupLng!, destinationLng!);
    final latSpan = (maxLat - minLat).abs() < 1e-6 ? 1e-6 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng).abs() < 1e-6 ? 1e-6 : (maxLng - minLng);

    final nx = (lng - minLng) / lngSpan;
    final ny = 1 - ((lat - minLat) / latSpan);
    final padX = size.width * 0.14;
    final padY = size.height * 0.22;
    return Offset(
      padX + nx * (size.width - padX * 2),
      padY + ny * (size.height - padY * 2),
    );
  }

  void _drawPin(Canvas canvas, Offset center, Color color) {
    canvas.drawCircle(
      center,
      7,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(center, 4.5, Paint()..color = color);
    canvas.drawCircle(center, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.pickupLat != pickupLat ||
        oldDelegate.pickupLng != pickupLng ||
        oldDelegate.destinationLat != destinationLat ||
        oldDelegate.destinationLng != destinationLng;
  }
}
