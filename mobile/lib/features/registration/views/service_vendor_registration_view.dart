import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/router/routes.dart';
import '../../../app/theme/ora_colors.dart';
import '../../../app/theme/ora_spacing.dart';
import '../../../app/theme/ora_typography.dart';
import '../../../app/theme/widgets/widgets.dart';
import '../../auth/presentation/view_models/session_user_profile.dart';
import '../widgets/registration_scaffold.dart';

const _businessTypes = ['Individual', 'Company'];
const _serviceAreas = [
  'Karachi',
  'Lahore',
  'Islamabad',
  'Rawalpindi',
  'Faisalabad',
  'Multan',
  'Peshawar',
  'Quetta',
];
const _experienceOptions = [
  'Less than 1 year',
  '1 – 3 years',
  '3+ Years',
  '5+ Years',
  '10+ Years',
];

const _categories = [
  (label: 'Plumbing', icon: Icons.plumbing_rounded),
  (label: 'Electrician', icon: Icons.bolt_rounded),
  (label: 'Painter', icon: Icons.format_paint_rounded),
  (label: 'AC Repair', icon: Icons.ac_unit_rounded),
  (label: 'Home Services', icon: Icons.home_rounded),
  (label: 'Computer & IT', icon: Icons.computer_rounded),
  (label: 'Carpentry', icon: Icons.carpenter_rounded),
  (label: 'Cleaning Services', icon: Icons.cleaning_services_rounded),
  (label: 'Construction', icon: Icons.construction_rounded),
  (label: 'Others (Specify)', icon: Icons.more_horiz_rounded),
];

/// Service-provider (vendor) registration — business details, selectable
/// service categories, area/experience and documents per the services
/// registration design. Stored locally until the vendor onboarding API
/// lands.
class ServiceVendorRegistrationView extends ConsumerStatefulWidget {
  const ServiceVendorRegistrationView({super.key});

  @override
  ConsumerState<ServiceVendorRegistrationView> createState() =>
      _ServiceVendorRegistrationViewState();
}

class _ServiceVendorRegistrationViewState
    extends ConsumerState<ServiceVendorRegistrationView> {
  late final TextEditingController _businessNameController;
  late final TextEditingController _contactController;
  final _addressController = TextEditingController();
  final _aboutController = TextEditingController();
  final Map<String, String> _errors = {};

  String? _businessType;
  String? _serviceArea;
  String? _experience;
  final Set<String> _selectedCategories = {};
  XFile? _cnicPhoto;
  XFile? _businessLicense;
  XFile? _servicePhotos;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(sessionUserProfileProvider);
    _businessNameController = TextEditingController(
      text: profile?.displayName != null
          ? '${profile!.displayName} Services'
          : '',
    );
    _contactController = TextEditingController(
      text: profile?.phoneNumber ?? '',
    );
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _aboutController.dispose();
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
    if (_selectedCategories.isEmpty) {
      _errors['categories'] = 'Select at least one service category.';
    }
    if (_serviceArea == null) {
      _errors['serviceArea'] = 'Select a service area.';
    }
    if (_experience == null) {
      _errors['experience'] = 'Select your experience.';
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
                'Your service provider registration is saved. Our team will '
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
      'business-name' => 'businessName',
      'contact-number' => 'contactNumber',
      'business-address' => 'businessAddress',
      _ => field,
    };
    return RegFieldTile(
      fieldKey: ValueKey('vendor-$field'),
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
      title: 'Services\nRegistration',
      subtitle: 'Offer your services on ORA and grow your business!',
      heroAsset: 'assets/brand/reg_services.webp',
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
        const RegSection(number: 1, title: 'Business Information'),
        RegRow(
          children: [
            _field(
              field: 'business-name',
              icon: Icons.storefront_rounded,
              label: 'Business Name *',
              controller: _businessNameController,
              hint: 'ABC Services',
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
              hint: 'DHA Phase 6, Karachi',
              capitalization: TextCapitalization.sentences,
            ),
            RegDropdownTile(
              tileKey: const ValueKey('vendor-business-type'),
              icon: Icons.work_outline_rounded,
              label: 'Business Type *',
              value: _businessType,
              placeholder: 'Individual / Company',
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
        const RegSection(number: 2, title: 'Service Categories'),
        if (_errors['categories'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: OraSpacing.xs),
            child: Text(
              _errors['categories']!,
              style: OraTypography.caption(OraColors.danger),
            ),
          ),
        GridView.count(
          key: const ValueKey('vendor-category-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 5,
          mainAxisSpacing: OraSpacing.xs,
          crossAxisSpacing: OraSpacing.xs,
          childAspectRatio: 0.78,
          children: [
            for (final category in _categories)
              RegCategoryChip(
                key: ValueKey(
                  'vendor-category-${category.label.toLowerCase()}',
                ),
                label: category.label,
                icon: category.icon,
                selected: _selectedCategories.contains(category.label),
                onTap: () => setState(() {
                  if (!_selectedCategories.remove(category.label)) {
                    _selectedCategories.add(category.label);
                  }
                  _errors.remove('categories');
                }),
              ),
          ],
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 3, title: 'Service Area & Details'),
        RegRow(
          children: [
            RegDropdownTile(
              tileKey: const ValueKey('vendor-service-area'),
              icon: Icons.location_on_outlined,
              label: 'Service Area *',
              value: _serviceArea,
              placeholder: 'Karachi',
              errorText: _errors['serviceArea'],
              onTap: () => _pick(
                'serviceArea',
                'Service area',
                _serviceAreas,
                (v) => _serviceArea = v,
                selected: _serviceArea,
              ),
            ),
            RegDropdownTile(
              tileKey: const ValueKey('vendor-experience'),
              icon: Icons.star_outline_rounded,
              label: 'Experience *',
              value: _experience,
              placeholder: '3+ Years',
              errorText: _errors['experience'],
              onTap: () => _pick(
                'experience',
                'Experience',
                _experienceOptions,
                (v) => _experience = v,
                selected: _experience,
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        _field(
          field: 'about-services',
          icon: Icons.notes_rounded,
          label: 'About Your Services',
          controller: _aboutController,
          hint: 'Tell us about your services...',
          capitalization: TextCapitalization.sentences,
          maxLines: 3,
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 4, title: 'Documents'),
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
              title: 'Business License',
              subtitle: 'if applicable',
              icon: Icons.workspace_premium_outlined,
              file: _businessLicense,
              onPick: () => _pickPhoto((f) => _businessLicense = f),
            ),
            RegUploadTile(
              title: 'Service Photos',
              subtitle: 'Shop / Work',
              icon: Icons.photo_library_outlined,
              file: _servicePhotos,
              onPick: () => _pickPhoto((f) => _servicePhotos = f),
            ),
          ],
        ),
      ],

    );
  }
}
