import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/ora_floaty.dart' show OraTapScale;

/// Full-bleed vendor hero — the reference artwork rendered edge-to-edge
/// covering the whole top area, uncropped and blended into the page
/// below. Used for both the services-vendor and logistics-vendor tops.
class VendorHeroTop extends StatelessWidget {
  const VendorHeroTop({
    super.key,
    this.asset = 'assets/vendor/vendor_top.png',
    this.aspect = 341.0 / 1024.0,
    this.bannerRect = const Rect.fromLTRB(10, 135, 1014, 335),
    this.srcWidth = 1024.0,
    this.topStrip = const [Color(0xFFFDF2EF)],
    this.onBannerTap,
  });

  final String asset;
  final double aspect;
  final Rect bannerRect;
  final double srcWidth;

  /// Colour(s) continuing the artwork's top edge across the status-bar
  /// strip, so the lowered art still reads as one continuous surface.
  final List<Color> topStrip;
  final VoidCallback? onBannerTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w * aspect;
        final s = w / srcWidth;
        final inset = MediaQuery.of(context).padding.top;
        return SizedBox(
          height: h + inset,
          width: w,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: inset,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: topStrip.length == 1
                          ? [topStrip.first, topStrip.first]
                          : topStrip,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: inset,
                left: 0,
                right: 0,
                height: h,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.white, Colors.transparent],
                    stops: [0.0, 0.86, 1.0],
                  ).createShader(rect),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.fitWidth,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              if (onBannerTap != null)
                Positioned(
                  left: bannerRect.left * s,
                  top: inset + bannerRect.top * s,
                  width: bannerRect.width * s,
                  height: bannerRect.height * s,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onBannerTap,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Field label row — icon in an orange disc, bold label, red `*`.
class VendorFieldLabel extends StatelessWidget {
  const VendorFieldLabel({
    required this.icon,
    required this.label,
    super.key,
    this.required = true,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool required;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFA45E), OraColors.goldDeep],
            ),
          ),
          child: Icon(icon, size: 14, color: OraColors.primaryForeground),
        ),
        const SizedBox(width: OraSpacing.xs),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: OraColors.danger),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.label(
              OraColors.textPrimary,
            ).copyWith(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// White rounded input shell shared by the vendor form fields.
class VendorInputShell extends StatelessWidget {
  const VendorInputShell({required this.child, super.key, this.error = false});

  final Widget child;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.input),
        border: Border.all(
          color: error ? OraColors.danger : const Color(0xFFEFD9C6),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0E8A4A1E),
            blurRadius: 10,
            offset: Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Borderless text field inside [VendorInputShell].
class VendorTextField extends StatelessWidget {
  const VendorTextField({
    required this.controller,
    super.key,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.prefixText,
    this.suffixIcon,
    this.error = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final String? prefixText;
  final Widget? suffixIcon;
  final bool error;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return VendorInputShell(
      error: error,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        style: OraTypography.body(OraColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: OraTypography.body(OraColors.textMuted),
          border: InputBorder.none,
          counterText: '',
          prefixText: prefixText,
          prefixStyle: OraTypography.body(OraColors.textPrimary),
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: OraSpacing.sm,
            vertical: OraSpacing.sm,
          ),
        ),
      ),
    );
  }
}

/// Dropdown-style tile — white shell + chevron, opens a picker sheet.
class VendorPickerTile extends StatelessWidget {
  const VendorPickerTile({
    required this.placeholder,
    super.key,
    this.value,
    this.error = false,
    this.onTap,
  });

  final String placeholder;
  final String? value;
  final bool error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: VendorInputShell(
          error: error,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.sm,
              vertical: OraSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value ?? placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: value != null
                        ? OraTypography.body(OraColors.textPrimary)
                        : OraTypography.body(OraColors.textMuted),
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: OraColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Selectable feature chip — icon + label + checkbox, white pill.
class VendorFeatureChip extends StatelessWidget {
  const VendorFeatureChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: OraSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: OraColors.onPhoto,
            borderRadius: BorderRadius.circular(OraRadius.input),
            border: Border.all(
              color: selected ? OraColors.gold : const Color(0xFFEFD9C6),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? OraColors.gold : OraColors.textMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OraTypography.caption(
                    OraColors.textPrimary,
                  ).copyWith(fontWeight: FontWeight.w600, fontSize: 11.5),
                ),
              ),
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: selected,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: OraColors.gold,
                  side: const BorderSide(color: OraColors.textMuted),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "Upload Photos" tile — first slot in the photo row.
class VendorUploadTile extends StatelessWidget {
  const VendorUploadTile({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: const CustomPaint(
          painter: _VendorDashedPainter(
            color: OraColors.gold,
            radius: OraRadius.input,
          ),
          child: SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 26,
                  color: OraColors.gold,
                ),
                SizedBox(height: OraSpacing.xxs),
                Text(
                  'Upload\nPhotos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: OraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small "+" tile shown after the last photo when more can be added.
class VendorAddPhotoTile extends StatelessWidget {
  const VendorAddPhotoTile({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: const CustomPaint(
          painter: _VendorDashedPainter(
            color: OraColors.primaryMuted,
            radius: OraRadius.input,
          ),
          child: SizedBox(
            width: 92,
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 24,
              color: OraColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picked photo thumbnail with a remove badge.
class VendorPhotoThumb extends StatelessWidget {
  const VendorPhotoThumb({
    required this.file,
    required this.onRemove,
    super.key,
  });

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.input),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: OraColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: OraColors.onPhoto,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same thumb as [VendorPhotoThumb] but renders a backend-hosted data-URL
/// photo (listings fetched from the marketplace API).
class VendorRemotePhotoThumb extends StatelessWidget {
  const VendorRemotePhotoThumb({
    required this.image,
    required this.onRemove,
    super.key,
  });

  final ImageProvider image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.input),
              child: Image(image: image, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: OraColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: OraColors.onPhoto,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded dashed-stroke painter for the upload tiles.
class _VendorDashedPainter extends CustomPainter {
  const _VendorDashedPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.7),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end.toDouble()), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_VendorDashedPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
