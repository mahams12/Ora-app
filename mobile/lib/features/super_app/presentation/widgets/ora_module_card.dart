import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_typography.dart';

/// Organic glass-blob module card with the orange sun accent — matches the
/// ORA prototype shape (svg path ported 1:1 from the HTML reference).
class OraModuleCard extends StatefulWidget {
  const OraModuleCard({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.route,
    required this.accent,
    required this.badgeIcon,
    super.key,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final String route;
  final Color accent;
  final IconData badgeIcon;

  @override
  State<OraModuleCard> createState() => _OraModuleCardState();
}

class _OraModuleCardState extends State<OraModuleCard> {
  var _pressed = false;

  void _openRoute(BuildContext context) {
    HapticFeedback.selectionClick();
    unawaited(context.push<void>(widget.route));
  }

  static const _imageOverlap = 26.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.subtitle}',
      onTap: () => _openRoute(context),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardHeight = constraints.maxWidth * (240 / 275);
              return InkWell(
                excludeFromSemantics: true,
                onTap: () => _openRoute(context),
                child: SizedBox(
                  height: cardHeight + _imageOverlap,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: _imageOverlap,
                        left: 0,
                        right: 0,
                        height: cardHeight,
                        child: CustomPaint(
                          painter: _BlobCardPainter(),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              0,
                              16,
                              cardHeight * 0.065,
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SizedBox(
                                height: cardHeight * 0.3,
                                child: Row(
                                  children: [
                                    Icon(
                                      widget.badgeIcon,
                                      color: const Color(0xFFFF6A0D),
                                      size: 26,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        widget.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: OraTypography.bodyEmphasis(
                                          OraColors.textPrimary,
                                        ).copyWith(fontSize: 17),
                                      ),
                                    ),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFFFF8A3D),
                                            Color(0xFFFF6A0D),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x66FF6A0D),
                                            blurRadius: 8,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        left: 6,
                        right: 6,
                        height: _imageOverlap + cardHeight * 0.52,
                        child: Image.asset(
                          widget.imageAsset,
                          cacheWidth: 480,
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Paints the glass blob + orange sun, scaled from the prototype's
/// 275x240 viewBox.
class _BlobCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 275;
    final sy = size.height / 240;
    final path = Path()
      ..moveTo(22, 150)
      ..cubicTo(22, 100, 60, 62, 105, 38)
      ..cubicTo(150, 14, 215, 20, 240, 70)
      ..cubicTo(250, 92, 252, 110, 250, 130)
      ..lineTo(250, 192)
      ..cubicTo(250, 212, 238, 226, 216, 226)
      ..lineTo(56, 226)
      ..cubicTo(36, 226, 22, 212, 22, 192)
      ..close();
    final scaled = path.transform(
      Matrix4.diagonal3Values(sx, sy, 1).storage,
    );
    final bounds = Offset.zero & size;

    // soft drop shadow
    canvas.save();
    canvas.translate(0, size.height * 0.045);
    canvas.drawPath(
      scaled,
      Paint()
        ..color = const Color(0x47BE5F28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();

    // glass body
    canvas.drawPath(
      scaled,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFDFC),
            Color(0xFFFDF1EA),
            Color(0xFFFDE6D8),
          ],
          stops: [0, 0.55, 1],
        ).createShader(bounds),
    );

    // inner shading + label glass bar (clipped to blob)
    canvas.save();
    canvas.clipPath(scaled);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(136 * sx, 40 * sy),
        width: 192 * sx,
        height: 60 * sy,
      ),
      Paint()..color = const Color(0x59FFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(22 * sx, 140 * sy, 228 * sx, 90 * sy),
        Radius.circular(40 * sx),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8CFFFFFF), Color(0xE6FFE9DC)],
        ).createShader(bounds),
    );
    canvas.drawRect(
      Rect.fromLTWH(22 * sx, 205 * sy, 228 * sx, 22 * sy),
      Paint()..color = const Color(0x29FFB98A),
    );
    canvas.restore();

    // white rim
    canvas.drawPath(
      scaled,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = const Color(0xE6FFFFFF),
    );

    // orange sun (drawn above the blob, like the reference)
    final sunCenter = Offset(190 * sx, 68 * sy);
    final sunRadius = 58 * sx;
    canvas.drawCircle(
      sunCenter,
      sunRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFA14A), Color(0xFFFF6A0D)],
        ).createShader(
          Rect.fromCircle(center: sunCenter, radius: sunRadius),
        )
        ..color = const Color(0xFFFF8A3D),
    );
  }

  @override
  bool shouldRepaint(_BlobCardPainter oldDelegate) => false;
}
