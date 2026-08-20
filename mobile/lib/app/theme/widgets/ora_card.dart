import 'package:flutter/material.dart';

import '../ora_spacing.dart';

class OraCard extends StatelessWidget {
  const OraCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(OraSpacing.md),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) {
      return card;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}
