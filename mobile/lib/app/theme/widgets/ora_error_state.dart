import 'package:flutter/material.dart';

import 'ora_button.dart';

class OraErrorState extends StatelessWidget {
  const OraErrorState({
    required this.title,
    super.key,
    this.message,
    this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              OraButton(
                label: 'Try again',
                onPressed: onRetry,
                variant: OraButtonVariant.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
