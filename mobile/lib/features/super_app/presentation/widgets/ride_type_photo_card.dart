import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_motion.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../domain/ride_type_catalogue.dart';

class RideTypePhotoCard extends StatefulWidget {
  const RideTypePhotoCard({
    required this.option,
    required this.onTap,
    super.key,
  });

  final RideTypeOption option;
  final VoidCallback onTap;

  @override
  State<RideTypePhotoCard> createState() => _RideTypePhotoCardState();
}

class _RideTypePhotoCardState extends State<RideTypePhotoCard> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    return Semantics(
      button: true,
      label:
          '${option.name}, ${option.blurb}'
          '${option.comingLater ? ', coming later' : ''}',
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(OraRadius.card),
            child: Material(
              color: OraColors.surfaceElevated,
              child: InkWell(
                excludeFromSemantics: true,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: OraColors.surface),
                    ),
                    Positioned.fill(
                      bottom: 46,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                        child: Image.asset(
                          option.image,
                          cacheWidth: 480,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: OraColors.textMuted,
                                ),
                              ),
                        ),
                      ),
                    ),
                    if (option.comingLater)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 28),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: OraColors.primary,
                            borderRadius: BorderRadius.circular(OraRadius.pill),
                          ),
                          child: Text(
                            'Coming later',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(
                              OraColors.onPhoto,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
                          ),
                          Text(
                            option.blurb,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(
                              OraColors.textMuted,
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
    );
  }
}
