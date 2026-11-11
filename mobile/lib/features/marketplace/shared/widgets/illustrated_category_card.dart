import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_typography.dart';
import 'status_pill.dart';

class IllustratedCategoryCard extends StatefulWidget {
  const IllustratedCategoryCard({
    required this.imageAsset,
    required this.title,
    required this.countLine,
    required this.onTap,
    super.key,
    this.width = 164,
    this.height = 172,
    this.badgeIcon = Icons.category_outlined,
    this.statusVariant,
  });

  final String imageAsset;
  final String title;
  final String countLine;
  final VoidCallback onTap;
  final double width;
  final double height;
  final IconData badgeIcon;
  final StatusPillVariant? statusVariant;

  @override
  State<IllustratedCategoryCard> createState() =>
      _IllustratedCategoryCardState();
}

class _IllustratedCategoryCardState extends State<IllustratedCategoryCard> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    final status = widget.statusVariant == null
        ? null
        : StatusPill(variant: widget.statusVariant!, inverse: true);
    return Semantics(
      button: true,
      label: [
        widget.title,
        widget.countLine,
        if (status != null) widget.statusVariant!.name,
      ].join(', '),
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: OraColors.navyElevated,
                borderRadius: radius,
                border: Border.fromBorderSide(OraElevation.cardBorder),
                boxShadow: OraElevation.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    excludeFromSemantics: true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Image.asset(
                          widget.imageAsset,
                          cacheWidth: 480,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                OraColors.shadow,
                                OraColors.photoScrimStrong,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: OraColors.photoChip,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              widget.badgeIcon,
                              size: 16,
                              color: OraColors.navy,
                            ),
                          ),
                        ),
                        if (status != null)
                          Positioned(top: 10, right: 8, child: status),
                        Positioned(
                          left: 12,
                          right: 10,
                          bottom: 10,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.bodyEmphasis(
                                  OraColors.onPhoto,
                                ),
                              ),
                              Text(
                                widget.countLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OraTypography.caption(
                                  OraColors.onPhotoMuted,
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
