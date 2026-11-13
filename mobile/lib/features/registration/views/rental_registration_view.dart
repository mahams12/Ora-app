import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router/routes.dart';
import '../../../app/theme/ora_spacing.dart';
import '../../../app/theme/widgets/widgets.dart';
import '../../auth/presentation/view_models/session_user_profile.dart';
import '../widgets/registration_scaffold.dart';

const _propertyTypes = [
  'Hotel',
  'House',
  'Apartment / Flat',
  'Guest House',
  'Farmhouse',
  'Room / Shared Room',
  'Resort',
  'Shop / Commercial',
];
const _locations = [
  'DHA Phase 6, Karachi',
  'Clifton, Karachi',
  'Gulberg, Lahore',
  'Bahria Town, Lahore',
  'F-7, Islamabad',
  'F-10, Islamabad',
  'Other',
];

/// Rental host registration — host details, property info and the optional
/// documents shown in the rentals registration design. Stored locally until
/// the host onboarding API lands.
class RentalRegistrationView extends ConsumerStatefulWidget {
  const RentalRegistrationView({super.key});

  @override
  ConsumerState<RentalRegistrationView> createState() =>
      _RentalRegistrationViewState();
}

class _RentalRegistrationViewState
    extends ConsumerState<RentalRegistrationView> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _contactController;
  final _addressController = TextEditingController();
  final _propertyNameController = TextEditingController();
  final _detailsController = TextEditingController();
  final Map<String, String> _errors = {};

  String? _propertyType;
  String? _location;
  XFile? _hostPhoto;
  XFile? _propertyPhoto;
  XFile? _cnicPhoto;
  XFile? _ownershipDocument;
  XFile? _businessLicense;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(sessionUserProfileProvider);
    _fullNameController = TextEditingController(
      text: profile?.displayName ?? '',
    );
    _contactController = TextEditingController(
      text: profile?.phoneNumber ?? '',
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _propertyNameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _changed(String field) => setState(() => _errors.remove(field));

  bool _validate() {
    _errors.clear();
    if (_fullNameController.text.trim().length < 2) {
      _errors['fullName'] = 'Enter your full name.';
    }
    if (_contactController.text.trim().length < 7) {
      _errors['contactNumber'] = 'Enter a valid contact number.';
    }
    if (_addressController.text.trim().length < 4) {
      _errors['address'] = 'Enter your address.';
    }
    if (_propertyType == null) {
      _errors['propertyType'] = 'Select a property type.';
    }
    if (_propertyNameController.text.trim().length < 2) {
      _errors['propertyName'] = 'Enter the property name.';
    }
    if (_location == null) {
      _errors['location'] = 'Select a location.';
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
    setState(() => _submitting = true);
    await showOraBottomSheet<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OraSectionHeader(
            title: "Application received — we'll notify you after review",
            description:
                'Your rental host registration is saved. Our team will '
                'contact you once it is reviewed.',
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
    int maxLines = 1,
  }) {
    final errorField = switch (field) {
      'full-name' => 'fullName',
      'contact-number' => 'contactNumber',
      'address' => 'address',
      'property-name' => 'propertyName',
      _ => field,
    };
    return RegFieldTile(
      fieldKey: ValueKey('rental-$field'),
      icon: icon,
      label: label,
      controller: controller,
      hint: hint,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      verified: verified,
      errorText: _errors[errorField],
      maxLines: maxLines,
      onChanged: (_) => _changed(errorField),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OraRegistrationScaffold(
      title: 'Rentals\nRegistration',
      subtitle: 'List your property and start earning today!',
      heroAsset: 'assets/marketplace/modules/rental.webp',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: OraSpacing.sm),
          const RegInfoBanner(),
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
        const RegSection(number: 1, title: 'Host Information'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RegAvatarUpload(
              photo: _hostPhoto,
              onPick: () => _pickPhoto((f) => _hostPhoto = f),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Column(
                children: [
                  _field(
                    field: 'full-name',
                    icon: Icons.person_outline_rounded,
                    label: 'Full Name *',
                    controller: _fullNameController,
                    hint: 'Enter your name',
                    capitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: OraSpacing.sm),
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
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        _field(
          field: 'address',
          icon: Icons.location_on_outlined,
          label: 'Address *',
          controller: _addressController,
          hint: 'Enter your address',
          capitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 2, title: 'Property Information'),
        RegRow(
          children: [
            RegDropdownTile(
              tileKey: const ValueKey('rental-property-type'),
              icon: Icons.home_work_outlined,
              label: 'Property Type *',
              value: _propertyType,
              placeholder: 'Hotel',
              errorText: _errors['propertyType'],
              onTap: () => _pick(
                'propertyType',
                'Property type',
                _propertyTypes,
                (v) => _propertyType = v,
                selected: _propertyType,
              ),
            ),
            _field(
              field: 'property-name',
              icon: Icons.apartment_rounded,
              label: 'Property Name *',
              controller: _propertyNameController,
              hint: 'Grand View Hotel',
              capitalization: TextCapitalization.words,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegDropdownTile(
          tileKey: const ValueKey('rental-location'),
          icon: Icons.location_on_outlined,
          label: 'Location *',
          value: _location,
          placeholder: 'DHA Phase 6, Karachi',
          errorText: _errors['location'],
          onTap: () => _pick(
            'location',
            'Location',
            _locations,
            (v) => _location = v,
            selected: _location,
          ),
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            RegUploadTile(
              title: 'Property Photos',
              subtitle: 'Add good quality photos',
              icon: Icons.villa_outlined,
              file: _propertyPhoto,
              onPick: () => _pickPhoto((f) => _propertyPhoto = f),
            ),
            _field(
              field: 'property-details',
              icon: Icons.notes_rounded,
              label: 'Property Details',
              controller: _detailsController,
              hint: 'e.g. Luxury hotel, 2 rooms, WiFi, parking etc.',
              capitalization: TextCapitalization.sentences,
              maxLines: 4,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(
          number: 3,
          title: 'Required Documents (Optional at First, Mandatory Later)',
        ),
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
              title: 'Property Ownership',
              subtitle: 'Title / Agreement',
              icon: Icons.assignment_outlined,
              file: _ownershipDocument,
              onPick: () => _pickPhoto((f) => _ownershipDocument = f),
            ),
            RegUploadTile(
              title: 'Business License',
              subtitle: 'if applicable',
              icon: Icons.workspace_premium_outlined,
              file: _businessLicense,
              onPick: () => _pickPhoto((f) => _businessLicense = f),
            ),
          ],
        ),
      ],

    );
  }
}
