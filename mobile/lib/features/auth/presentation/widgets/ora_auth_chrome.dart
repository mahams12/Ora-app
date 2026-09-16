import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../core/constants/app_constants.dart';

/// Gold gradient brand mark used on auth surfaces.
class OraBrandMark extends StatelessWidget {
  const OraBrandMark({
    super.key,
    this.size = 72,
    this.semanticLabel = AppConstants.appName,
  });

  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [OraColors.gold, OraColors.goldDeep],
          ),
          boxShadow: OraElevation.primaryButtonShadow,
        ),
        alignment: Alignment.center,
        child: Text(
          'O',
          style: OraTypography.display(
            OraColors.primaryForeground,
          ).copyWith(fontSize: size * 0.42, height: 1),
        ),
      ),
    );
  }
}

/// Dark navy gradient canvas for auth/onboarding screens.
class OraAuthScaffold extends StatelessWidget {
  const OraAuthScaffold({required this.child, super.key, this.topLeading});

  final Widget child;
  final Widget? topLeading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              OraColors.navy,
              OraColors.navyElevated,
              OraColors.background,
            ],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (topLeading != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    OraSpacing.xs,
                    OraSpacing.xs,
                    OraSpacing.md,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: topLeading!,
                  ),
                ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact status / error banner for auth flows.
class OraAuthBanner extends StatelessWidget {
  const OraAuthBanner({required this.message, super.key, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final bg = isError ? OraColors.dangerMuted : OraColors.secondaryMuted;
    final fg = isError ? OraColors.dangerForeground : OraColors.tealBright;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.info_outline_rounded;

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(OraSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(OraRadius.md),
          border: Border.all(
            color: isError
                ? OraColors.danger.withValues(alpha: 0.35)
                : OraColors.secondary,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: OraSpacing.sm),
            Expanded(child: Text(message, style: OraTypography.body(fg))),
          ],
        ),
      ),
    );
  }
}

class OraAuthBackButton extends StatelessWidget {
  const OraAuthBackButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded),
        color: OraColors.textPrimary,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: const Color(0x14FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(OraRadius.sm),
          ),
        ),
      ),
    );
  }
}
