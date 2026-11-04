import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';

class ModuleComingSoonView extends StatelessWidget {
  const ModuleComingSoonView({
    required this.title,
    required this.imageAsset,
    super.key,
  });

  final String title;
  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(OraSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    imageAsset,
                    width: 176,
                    height: 176,
                    cacheWidth: 528,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: OraTypography.title(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Text(
                    'This module is being built. Nothing can be booked here yet.',
                    textAlign: TextAlign.center,
                    style: OraTypography.body(OraColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
