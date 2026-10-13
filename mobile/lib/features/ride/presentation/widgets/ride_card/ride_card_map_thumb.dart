import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import 'ride_card_assets.dart';

/// Compact glowing map thumbnail — CustomPainter only (no map engine / no watermark).
///
/// Matches the inDrive-style Ora route preview: dark terrain, neon blue path,
/// pulsed pickup glow, white destination pin.
class RideCardMapThumb extends StatelessWidget {
  const RideCardMapThumb({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.width = 72,
    this.height = 96,
    this.showCar = false,
    this.carAssetPath,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final double width;
  final double height;
  final bool showCar;
  final String? carAssetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.md),
        border: Border.all(
          color: OraColors.info.withValues(alpha: 0.45),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _ThumbRoutePainter(
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              destinationLat: destinationLat,
              destinationLng: destinationLng,
            ),
          ),
          if (showCar && carAssetPath != null)
            Positioned(
              left: width * 0.08,
              right: width * 0.08,
              bottom: height * 0.08,
              child: RideCardAssetImage(
                assetPath: carAssetPath!,
                width: width * 0.84,
                height: height * 0.42,
              ),
            ),
        ],
      ),
    );
  }
}

/// Wide banner map used on active driver job cards.
class RideCardMapBanner extends StatelessWidget {
  const RideCardMapBanner({
    super.key,
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.height = 132,
    this.carAssetPath,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final double height;
  final String? carAssetPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OraRadius.md),
        border: Border.all(color: OraColors.info.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: OraColors.info.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _ThumbRoutePainter(
              pickupLat: pickupLat,
              pickupLng: pickupLng,
              destinationLat: destinationLat,
              destinationLng: destinationLng,
              wide: true,
            ),
          ),
          if (carAssetPath != null)
            Align(
              alignment: const Alignment(0.15, 0.35),
              child: RideCardAssetImage(
                assetPath: carAssetPath!,
                width: 160,
                height: height * 0.55,
              ),
            ),
        ],
      ),
    );
  }
}

class _ThumbRoutePainter extends CustomPainter {
  const _ThumbRoutePainter({
    this.pickupLat,
    this.pickupLng,
    this.destinationLat,
    this.destinationLng,
    this.wide = false,
  });

  final double? pickupLat;
  final double? pickupLng;
  final double? destinationLat;
  final double? destinationLng;
  final bool wide;

  static const _routeBlue = Color(0xFF4FA3D9);
  static const _routeGlow = Color(0xFF7CC8F5);
  static const _bgDeep = Color(0xFF070B14);
  static const _bgMid = Color(0xFF10182A);
  static const _bgLit = Color(0xFF1A2740);

  @override
  void paint(Canvas canvas, Size size) {
    _paintTerrain(canvas, size);
    _paintFaintGrid(canvas, size);

    final points = _routePoints(size);
    if (points.length < 2) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Outer bloom
    canvas.drawPath(
      path,
      Paint()
        ..color = _routeGlow.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = wide ? 12 : 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Mid glow
    canvas.drawPath(
      path,
      Paint()
        ..color = _routeBlue.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = wide ? 6.5 : 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    // Core neon line
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          points.first,
          points.last,
          const [
            _routeGlow,
            _routeBlue,
            Color(0xFF3D82FF),
          ],
          const [0.0, 0.55, 1.0],
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = wide ? 3.2 : 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Waypoint pips at interior vertices (skip start/end)
    for (var i = 1; i < points.length - 1; i++) {
      final p = points[i];
      canvas.drawCircle(
        p,
        wide ? 2.4 : 1.8,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
    }

    _pickupGlow(canvas, points.first, wide: wide);
    _destinationPin(canvas, points.last, wide: wide);
  }

  void _paintTerrain(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [_bgDeep, _bgMid, _bgLit, _bgDeep],
          const <double>[0.0, 0.35, 0.7, 1.0],
        ),
    );

    // Soft “block” patches — abstract dark cityread without labels.
    final block = Paint()..color = const Color(0xFF162033).withValues(alpha: 0.55);
    final lit = Paint()..color = const Color(0xFF243556).withValues(alpha: 0.35);
    final rng = math.Random(_seed);
    for (var i = 0; i < (wide ? 18 : 12); i++) {
      final w = size.width * (0.12 + rng.nextDouble() * 0.18);
      final h = size.height * (0.06 + rng.nextDouble() * 0.12);
      final x = rng.nextDouble() * (size.width - w);
      final y = rng.nextDouble() * (size.height - h);
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(r, i.isEven ? block : lit);
    }

    // Vignette
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.45, size.height * 0.55),
          size.longestSide * 0.85,
          [
            Colors.transparent,
            _bgDeep.withValues(alpha: 0.55),
          ],
        ),
    );
  }

  void _paintFaintGrid(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 0.8;
    final stepY = size.height / 7;
    final stepX = size.width / 5;
    for (var i = 1; i < 7; i++) {
      final y = stepY * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 1; i < 5; i++) {
      final x = stepX * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
  }

  int get _seed {
    final a = ((pickupLat ?? 0) * 1000).round();
    final b = ((pickupLng ?? 0) * 1000).round();
    final c = ((destinationLat ?? 0) * 1000).round();
    return a ^ (b << 3) ^ (c << 5) ^ (wide ? 17 : 0);
  }

  /// Segmented path with a few turns (matches stylized preview, not a road polyline).
  List<Offset> _routePoints(Size size) {
    final start = _endpoint(size, isStart: true);
    final end = _endpoint(size, isStart: false);

    // Deterministic bends between projected endpoints.
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final mid1 = Offset(
      start.dx + dx * 0.28 + (wide ? size.width * 0.06 : size.width * 0.04),
      start.dy + dy * 0.18,
    );
    final mid2 = Offset(
      start.dx + dx * 0.52 - (wide ? size.width * 0.05 : size.width * 0.03),
      start.dy + dy * 0.48,
    );
    final mid3 = Offset(
      start.dx + dx * 0.78 + (wide ? size.width * 0.02 : 0),
      start.dy + dy * 0.72,
    );
    return [start, mid1, mid2, mid3, end];
  }

  Offset _endpoint(Size size, {required bool isStart}) {
    final hasAll = pickupLat != null &&
        pickupLng != null &&
        destinationLat != null &&
        destinationLng != null;
    if (!hasAll) {
      return Offset(
        isStart ? size.width * 0.22 : size.width * 0.78,
        isStart ? size.height * 0.78 : size.height * 0.18,
      );
    }
    final minLat = math.min(pickupLat!, destinationLat!);
    final maxLat = math.max(pickupLat!, destinationLat!);
    final minLng = math.min(pickupLng!, destinationLng!);
    final maxLng = math.max(pickupLng!, destinationLng!);
    final latSpan = (maxLat - minLat).abs() < 1e-6 ? 1e-6 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng).abs() < 1e-6 ? 1e-6 : (maxLng - minLng);
    final lat = isStart ? pickupLat! : destinationLat!;
    final lng = isStart ? pickupLng! : destinationLng!;
    final nx = (lng - minLng) / lngSpan;
    final ny = 1 - ((lat - minLat) / latSpan);
    final padX = size.width * 0.18;
    final padY = size.height * 0.16;
    return Offset(
      padX + nx * (size.width - padX * 2),
      padY + ny * (size.height - padY * 2),
    );
  }

  void _pickupGlow(Canvas canvas, Offset c, {required bool wide}) {
    final outer = wide ? 14.0 : 11.0;
    final mid = wide ? 8.0 : 6.5;
    final core = wide ? 4.2 : 3.4;
    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..color = _routeGlow.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      mid,
      Paint()..color = _routeBlue.withValues(alpha: 0.85),
    );
    canvas.drawCircle(c, core, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      core * 0.45,
      Paint()..color = _routeGlow,
    );
  }

  void _destinationPin(Canvas canvas, Offset tip, {required bool wide}) {
    final scale = wide ? 1.25 : 1.0;
    final pinH = 14.0 * scale;
    final pinW = 10.0 * scale;
    // Tip sits on the route end; body extends upward.
    final top = tip.translate(0, -pinH);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        tip.dx - pinW * 0.55,
        tip.dy - pinH * 0.45,
        tip.dx - pinW * 0.5,
        tip.dy - pinH * 0.72,
      )
      ..arcToPoint(
        Offset(tip.dx + pinW * 0.5, tip.dy - pinH * 0.72),
        radius: Radius.circular(pinW * 0.5),
        clockwise: true,
      )
      ..quadraticBezierTo(
        tip.dx + pinW * 0.55,
        tip.dy - pinH * 0.45,
        tip.dx,
        tip.dy,
      )
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(top.dx, tip.dy - pinH * 0.72),
      pinW * 0.22,
      Paint()..color = const Color(0xFF0B0F1C),
    );
  }

  @override
  bool shouldRepaint(covariant _ThumbRoutePainter oldDelegate) {
    return oldDelegate.pickupLat != pickupLat ||
        oldDelegate.pickupLng != pickupLng ||
        oldDelegate.destinationLat != destinationLat ||
        oldDelegate.destinationLng != destinationLng ||
        oldDelegate.wide != wide;
  }
}
