import 'package:flutter/material.dart';

import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/ora_bottom_sheet.dart';
import '../../../../app/theme/widgets/ora_button.dart';
import '../../../../app/theme/widgets/ora_section_header.dart';

Future<void> showUnavailableFeatureSheet(
  BuildContext context,
  String feature,
) async {
  await showOraBottomSheet<void>(
    context: context,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OraSectionHeader(
          eyebrow: 'Coming later',
          title: feature,
          description:
              '$feature is planned for Ora but is not wired to the backend '
              'in this build. Nothing is faked.',
        ),
        const SizedBox(height: OraSpacing.lg),
        OraButton(
          label: 'Got it',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
