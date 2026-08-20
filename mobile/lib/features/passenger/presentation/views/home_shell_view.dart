import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/responsive.dart';

/// Phase 2+ passenger shell placeholder — no ride business logic yet.
class HomeShellView extends ConsumerWidget {
  const HomeShellView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: Responsive.contentMaxWidth(context),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OraCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Foundation ready',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            Text(
                              'MVVM + Riverpod + go_router are wired. '
                              'Ride dispatch, offers, and payments are intentionally not implemented in Phase 1.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _ConfigRow(label: 'Environment', value: config.environment.displayName),
                      _ConfigRow(label: 'API base URL', value: config.apiBaseUrl),
                      _ConfigRow(label: 'Client version', value: config.clientVersion),
                      const SizedBox(height: OraSpacing.lg),
                      OraButton(
                        label: 'Show design sheet',
                        onPressed: () => _showDesignSheet(context),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDesignSheet(BuildContext context) {
    showOraBottomSheet<void>(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(OraSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Design primitives', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: OraSpacing.md),
            const OraTextField(label: 'Sample field', hint: 'Enter text'),
            const SizedBox(height: OraSpacing.md),
            OraButton(
              label: 'Primary',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: OraSpacing.sm),
            OraButton(
              label: 'Outline',
              variant: OraButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: OraSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
