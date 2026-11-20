import 'package:flutter/material.dart';

import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';

/// Placeholder tab for passenger features not yet in this slice.
class PassengerUnavailableView extends StatelessWidget {
  const PassengerUnavailableView({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.hourglass_empty_rounded,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: OraEmptyState(
                  title: title,
                  message: message,
                  icon: icon,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null)
              OraButton(label: actionLabel!, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}
