import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_elevation.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_floaty.dart';
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
      child: OraFloaty(
        child: OraTapScale(
          child: ExcludeSemantics(
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
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: OraColors.surfaceElevated),
                        ),
                        Positioned.fill(
                          bottom: 44,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: widget.subcategory.image == 'placeholder'
                                ? _photoPlaceholder()
                                : Image.asset(
                                    'assets/marketplace/${widget.subcategory.image}',
                                    cacheWidth: 360,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.topCenter,
                                    filterQuality: FilterQuality.medium,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _photoPlaceholder(),
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
                            style: OraTypography.bodyEmphasis(
                              OraColors.textPrimary,
                            ),
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
