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
                    Image.asset(
                      option.image,
                      cacheWidth: 480,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                            color: OraColors.surfaceElevated,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: OraColors.textMuted,
                              ),
                            ),
                          ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xD9000000)],
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
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(OraRadius.pill),
                          ),
                          child: Text(
                            'Coming later',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(
                              OraColors.navy,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.bodyEmphasis(Colors.white),
                          ),
                          Text(
                            option.blurb,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OraTypography.caption(Colors.white70),
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
