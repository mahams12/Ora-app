import 'package:flutter/material.dart';

import '../ora_spacing.dart';

enum OraButtonVariant { primary, secondary, outline, ghost }

class OraButton extends StatelessWidget {
  const OraButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = OraButtonVariant.primary,
    this.isLoading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final OraButtonVariant variant;
  final bool isLoading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    final button = switch (variant) {
      OraButtonVariant.primary => FilledButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      OraButtonVariant.secondary => FilledButton.tonal(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      OraButtonVariant.outline => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      OraButtonVariant.ghost => TextButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
    };

    if (!expand) {
      return button;
    }

    return SizedBox(width: double.infinity, child: button);
  }
}

class OraButtonRow extends StatelessWidget {
  const OraButtonRow({
    required this.children,
    super.key,
    this.spacing = OraSpacing.sm,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: children,
    );
  }
}
