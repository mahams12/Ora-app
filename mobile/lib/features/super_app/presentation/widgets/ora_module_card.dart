import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_typography.dart';

class OraModuleCard extends StatefulWidget {
  const OraModuleCard({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.route,
    required this.accent,
    super.key,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final String route;
  final Color accent;

  @override
  State<OraModuleCard> createState() => _OraModuleCardState();
}

class _OraModuleCardState extends State<OraModuleCard> {
  var _pressed = false;

  void _openRoute(BuildContext context) {
    HapticFeedback.selectionClick();
    unawaited(context.push<void>(widget.route));
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);

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
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OraColors.navyElevated,
                  widget.accent.withValues(alpha: 0.3),
                ],
              ),
              border: Border.fromBorderSide(OraElevation.cardBorder),
              boxShadow: OraElevation.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  excludeFromSemantics: true,
                  onTap: () => _openRoute(context),
                  child: SizedBox(
                    height: 164,
                    child: Stack(
                      children: [
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Image.asset(
                            widget.imageAsset,
                            width: 84,
                            height: 84,
                            cacheWidth: 256,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: widget.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(
                                OraRadius.pill,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: widget.accent,
                              size: 16,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.bodyEmphasis(
                                  OraColors.textPrimary,
                                ),
                              ),
                              Text(
                                widget.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
