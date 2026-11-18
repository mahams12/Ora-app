import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/di/providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/theme/ora_colors.dart';
import '../../../app/theme/ora_spacing.dart';
import '../../../app/theme/ora_typography.dart';
import '../../../app/theme/widgets/widgets.dart';
import '../../auth/presentation/view_models/session_user_profile.dart';
import '../widgets/registration_scaffold.dart';

const _businessTypes = [
  'Cargo Owner',
  'Transport Company',
  'Fleet Owner',
  'Individual',
];
const _cargoVehicleTypes = [
  'Truck / Lorry',
  'Pickup',
  'Shehzore',
  'Loader Rickshaw',
  'Cargo Van',
  'Trailer',
  'Container Truck',
];
const _loadCapacities = [
  'Under 1 ton',
  '1 – 3 tons',
  '3 – 5 tons',
  '5 – 10 tons',
  '10+ tons',
];
const _cargoColours = [
  'White',
  'Black',
  'Silver',
  'Grey',
  'Red',
  'Blue',
  'Orange',
  'Other',
];

/// Cargo / logistics partner registration — collects the business, vehicle
/// and document details shown in the cargo registration design. Submits
/// server-side via POST /v1/auth/vendor-application (status → pending).
class CargoRegistrationView extends ConsumerStatefulWidget {
  const CargoRegistrationView({super.key});

  @override
  ConsumerState<CargoRegistrationView> createState() =>
      _CargoRegistrationViewState();
}

class _CargoRegistrationViewState
    extends ConsumerState<CargoRegistrationView> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _contactController;
  final _addressController = TextEditingController();
  final _registrationNumberController = TextEditingController();
  final Map<String, String> _errors = {};

  String? _businessType;
  String? _vehicleType;
  String? _loadCapacity;
  String? _vehicleColour;
  XFile? _vehiclePhoto;
  XFile? _registrationCertificate;
  XFile? _cnicPhoto;
  XFile? _businessDocuments;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(sessionUserProfileProvider);
    _businessNameController = TextEditingController();
    _contactController = TextEditingController(
      text: profile?.phoneNumber ?? '',
    );
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _registrationNumberController.dispose();
    super.dispose();
  }

  void _changed(String field) => setState(() => _errors.remove(field));

  bool _validate() {
    _errors.clear();
    if (_businessNameController.text.trim().length < 2) {
      _errors['businessName'] = 'Enter your business name.';
    }
    if (_contactController.text.trim().length < 7) {
      _errors['contactNumber'] = 'Enter a valid contact number.';
    }
    if (_addressController.text.trim().length < 4) {
      _errors['businessAddress'] = 'Enter your business address.';
    }
    if (_businessType == null) {
      _errors['businessType'] = 'Select a business type.';
    }
    if (_vehicleType == null) {
      _errors['vehicleType'] = 'Select a vehicle type.';
    }
    if (_loadCapacity == null) {
      _errors['loadCapacity'] = 'Select a load capacity.';
    }
    if (_registrationNumberController.text.trim().length < 2) {
      _errors['registrationNumber'] = 'Enter the registration number.';
    }
    if (_vehicleColour == null) {
      _errors['vehicleColour'] = 'Select a vehicle colour.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _pick(
    String field,
    String title,
    List<String> options,
    void Function(String) apply, {
    String? selected,
  }) async {
    final value = await showRegOptions(
      context,
      title: title,
      options: [for (final o in options) RegOption(o)],
      selected: selected,
    );
    if (value == null || !mounted) return;
    setState(() {
      apply(value);
      _errors.remove(field);
    });
  }

  Future<void> _pickPhoto(void Function(XFile) apply) async {
    final file = await pickRegPhoto();
    if (file == null || !mounted) return;
    setState(() => apply(file));
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(submitVendorApplicationUseCaseProvider).call(
        type: 'cargo',
        details: {
          'businessName': _businessNameController.text.trim(),
          'contactNumber': _contactController.text.trim(),
          'businessAddress': _addressController.text.trim(),
          'businessType': _businessType ?? '',
          'vehicleType': _vehicleType ?? '',
          'loadCapacity': _loadCapacity ?? '',
          'registrationNumber': _registrationNumberController.text.trim(),
          'vehicleColour': _vehicleColour ?? '',
        },
      );
      await ref
          .read(authStateNotifierProvider.notifier)
          .refreshCanonicalProfile();
      if (!mounted) return;
      setState(() => _submitting = false);
      await showOraBottomSheet<void>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OraSectionHeader(
              title: "Application received — we'll notify you after review",
              description:
                  'Your cargo partner registration is saved. The logistics '
                  'dashboard unlocks once an admin approves it.',
            ),
            const SizedBox(height: OraSpacing.lg),
            OraButton(
              label: 'Back to Home',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      if (mounted) context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _submitError = ref
            .read(failureMapperProvider)
            .fromException(error)
            .userMessage,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _field({
    required String field,
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    bool verified = false,
  }) {
    final errorField = switch (field) {
      'business-name' => 'businessName',
      'contact-number' => 'contactNumber',
      'business-address' => 'businessAddress',
      'registration-number' => 'registrationNumber',
      _ => field,
    };
    return RegFieldTile(
      fieldKey: ValueKey('cargo-$field'),
      icon: icon,
      label: label,
      controller: controller,
      hint: hint,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      verified: verified,
      errorText: _errors[errorField],
      onChanged: (_) => _changed(errorField),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OraRegistrationScaffold(
      title: 'Cargo\nRegistration',
      subtitle: 'Join ORA and grow your business!',
      heroAsset: 'assets/brand/reg_cargo.webp',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: OraSpacing.sm),
          const RegInfoBanner(),
          if (_submitError != null) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              _submitError!,
              key: const ValueKey('cargo-submit-error'),
              style: OraTypography.body(OraColors.danger),
            ),
          ],
          const SizedBox(height: OraSpacing.md),
          OraButton(
            label: 'Submit Registration',
            trailingIcon: Icons.arrow_forward_rounded,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: OraSpacing.md),
          const RegSupportFooter(),
        ],
      ),
      children: [
        const RegSection(number: 1, title: 'Business Information'),
        RegRow(
          children: [
            _field(
              field: 'business-name',
              icon: Icons.storefront_rounded,
              label: 'Business Name *',
              controller: _businessNameController,
              hint: 'Enter business name',
              capitalization: TextCapitalization.words,
            ),
            _field(
              field: 'contact-number',
              icon: Icons.phone_iphone_rounded,
              label: 'Contact Number *',
              controller: _contactController,
              hint: '0300 1234567',
              keyboardType: TextInputType.phone,
              verified: _contactController.text.trim().isNotEmpty,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            _field(
              field: 'business-address',
              icon: Icons.location_on_outlined,
              label: 'Business Address *',
              controller: _addressController,
              hint: 'Enter address',
              capitalization: TextCapitalization.sentences,
            ),
            RegDropdownTile(
              tileKey: const ValueKey('cargo-business-type'),
              icon: Icons.work_outline_rounded,
              label: 'Business Type *',
              value: _businessType,
              placeholder: 'Select type',
              errorText: _errors['businessType'],
              onTap: () => _pick(
                'businessType',
                'Business type',
                _businessTypes,
                (v) => _businessType = v,
                selected: _businessType,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 2, title: 'Vehicle / Cargo Information'),
        RegRow(
          children: [
            RegDropdownTile(
              tileKey: const ValueKey('cargo-vehicle-type'),
              icon: Icons.local_shipping_outlined,
              label: 'Vehicle Type *',
              value: _vehicleType,
              placeholder: 'Truck / Lorry',
              errorText: _errors['vehicleType'],
              onTap: () => _pick(
                'vehicleType',
                'Vehicle type',
                _cargoVehicleTypes,
                (v) => _vehicleType = v,
                selected: _vehicleType,
              ),
            ),
            RegDropdownTile(
              tileKey: const ValueKey('cargo-load-capacity'),
              icon: Icons.scale_outlined,
              label: 'Load Capacity *',
              value: _loadCapacity,
              placeholder: 'Select Capacity',
              errorText: _errors['loadCapacity'],
              onTap: () => _pick(
                'loadCapacity',
                'Load capacity',
                _loadCapacities,
                (v) => _loadCapacity = v,
                selected: _loadCapacity,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            _field(
              field: 'registration-number',
              icon: Icons.pin_outlined,
              label: 'Vehicle Registration Number *',
              controller: _registrationNumberController,
              hint: 'LEA-1234',
              capitalization: TextCapitalization.characters,
              verified:
                  _registrationNumberController.text.trim().length >= 2,
            ),
            RegDropdownTile(
              tileKey: const ValueKey('cargo-vehicle-colour'),
              icon: Icons.palette_outlined,
              label: 'Vehicle Colour *',
              value: _vehicleColour,
              placeholder: 'White',
              errorText: _errors['vehicleColour'],
              onTap: () => _pick(
                'vehicleColour',
                'Vehicle colour',
                _cargoColours,
                (v) => _vehicleColour = v,
                selected: _vehicleColour,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 3, title: 'Upload Documents'),
        RegRow(
          children: [
            RegUploadTile(
              title: 'Vehicle Photo',
              subtitle: 'Front view of truck',
              icon: Icons.local_shipping_outlined,
              file: _vehiclePhoto,
              onPick: () => _pickPhoto((f) => _vehiclePhoto = f),
            ),
            RegUploadTile(
              title: 'Registration Certificate',
              subtitle: 'Smart Card / Book',
              file: _registrationCertificate,
              onPick: () =>
                  _pickPhoto((f) => _registrationCertificate = f),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            RegUploadTile(
              title: 'CNIC',
              subtitle: 'Front & Back',
              icon: Icons.badge_outlined,
              file: _cnicPhoto,
              onPick: () => _pickPhoto((f) => _cnicPhoto = f),
            ),
            RegUploadTile(
              title: 'Business Documents',
              subtitle: 'Optional',
              icon: Icons.description_outlined,
              file: _businessDocuments,
              onPick: () => _pickPhoto((f) => _businessDocuments = f),
            ),
          ],
        ),
      ],

    );
  }
}
