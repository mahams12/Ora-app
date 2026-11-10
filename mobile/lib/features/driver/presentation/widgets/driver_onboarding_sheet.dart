import 'package:flutter/material.dart';

import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/widgets/widgets.dart';

/// Result returned when the driver onboarding application is submitted.
class DriverOnboardingResult {
  const DriverOnboardingResult({
    required this.vehicleType,
    this.vehicleModel,
    this.plateNumber,
    this.homeCity,
  });

  final String vehicleType;
  final String? vehicleModel;
  final String? plateNumber;
  final String? homeCity;
}

const _vehicleTypes = <(String, String)>[
  ('bike', 'Bike'),
  ('car', 'Car'),
  ('auto', 'Auto rickshaw'),
  ('other', 'Other'),
];

/// First-time driver application form (Switch to Driver).
///
/// Collects the minimum vehicle details the backend stores on
/// `drivers/{uid}`; approval remains an ops decision — the sheet only ever
/// produces a 'pending' application.
class DriverOnboardingSheet extends StatefulWidget {
  const DriverOnboardingSheet({super.key});

  /// Shows the sheet and resolves with the collected application, or null
  /// when dismissed.
  static Future<DriverOnboardingResult?> show(BuildContext context) {
    return showOraBottomSheet<DriverOnboardingResult>(
      context: context,
      child: const DriverOnboardingSheet(),
    );
  }

  @override
  State<DriverOnboardingSheet> createState() =>
      _DriverOnboardingSheetState();
}

class _DriverOnboardingSheetState extends State<DriverOnboardingSheet> {
  final _modelController = TextEditingController();
  final _plateController = TextEditingController();
  final _cityController = TextEditingController();
  String _vehicleType = 'car';

  @override
  void dispose() {
    _modelController.dispose();
    _plateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      DriverOnboardingResult(
        vehicleType: _vehicleType,
        vehicleModel: _modelController.text.trim(),
        plateNumber: _plateController.text.trim(),
        homeCity: _cityController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraSectionHeader(
            eyebrow: 'Switch to driver',
            title: 'Driver registration',
            description:
                'Apply once with this account. Your application is reviewed '
                'before you can go online — no separate sign-up needed.',
          ),
          const SizedBox(height: OraSpacing.lg),
          Wrap(
            spacing: OraSpacing.sm,
            runSpacing: OraSpacing.sm,
            children: [
              for (final (value, label) in _vehicleTypes)
                OraChip(
                  label: label,
                  selected: _vehicleType == value,
                  onTap: () => setState(() => _vehicleType = value),
                ),
            ],
          ),
          const SizedBox(height: OraSpacing.md),
          OraTextField(
            controller: _modelController,
            label: 'Vehicle model',
            hint: 'e.g. Toyota Corolla',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            controller: _plateController,
            label: 'Plate number',
            hint: 'e.g. LEA-1234',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: OraSpacing.sm),
          OraTextField(
            controller: _cityController,
            label: 'Home city',
            hint: 'e.g. Lahore',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: OraSpacing.lg),
          OraButton(
            label: 'Submit application',
            onPressed: _submit,
          ),
          const SizedBox(height: OraSpacing.xs),
          Text(
            'You will be notified once approved. Your passenger account and '
            'history stay exactly as they are.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}
