import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ora_colors.dart';
import '../ora_typography.dart';

/// Circular profile avatar — shows the stored photo when [avatarData] is a
/// `data:image/...;base64,...` URL, otherwise [initials] on the brand
/// gradient.
class OraAvatar extends StatelessWidget {
  const OraAvatar({
    required this.initials,
    this.avatarData,
    this.size = 38,
    this.fontSize,
    super.key,
  });

  final String initials;
  final String? avatarData;
  final double size;
  final double? fontSize;

  static const _goldGradient = LinearGradient(
    colors: [OraColors.gold, OraColors.goldDeep],
  );

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(avatarData);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: _goldGradient,
      ),
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : Center(
              child: Text(
                initials,
                style: OraTypography.label(
                  OraColors.primaryForeground,
                ).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize ?? size * 0.36,
                ),
              ),
            ),
    );
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}
