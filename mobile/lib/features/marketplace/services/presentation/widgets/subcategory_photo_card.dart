import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_elevation.dart';
import '../../../../../app/theme/ora_motion.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../catalogue/catalogue_models.dart';

class SubcategoryPhotoCard extends StatefulWidget {
  const SubcategoryPhotoCard({
    required this.subcategory,
    required this.onTap,
    super.key,
  });

  final ServiceSubcategory subcategory;
  final VoidCallback onTap;

  @override
  State<SubcategoryPhotoCard> createState() => _SubcategoryPhotoCardState();
}

class _SubcategoryPhotoCardState extends State<SubcategoryPhotoCard> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  Widget _photoPlaceholder() => const ColoredBox(
    color: OraColors.surfaceElevated,
    child: Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: OraColors.textMuted,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return Semantics(
      button: true,
      label: widget.subcategory.name,
      onTap: widget.onTap,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: OraMotion.press,
          curve: OraMotion.standard,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: OraColors.surfaceElevated,
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
                      if (widget.subcategory.image == 'placeholder')
                        _photoPlaceholder()
                      else
                        Image.asset(
                          'assets/marketplace/${widget.subcategory.image}',
                          cacheWidth: 360,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (context, error, stackTrace) =>
                              _photoPlaceholder(),
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
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 9,
                        child: Text(
                          widget.subcategory.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OraTypography.bodyEmphasis(Colors.white),
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
    );
  }
}
