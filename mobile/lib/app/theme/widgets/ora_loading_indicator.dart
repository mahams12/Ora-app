import 'package:flutter/material.dart';

class OraLoadingIndicator extends StatelessWidget {
  const OraLoadingIndicator({
    super.key,
    this.message,
    this.expand = true,
  });

  final String? message;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );

    if (!expand) {
      return content;
    }

    return Center(child: content);
  }
}
