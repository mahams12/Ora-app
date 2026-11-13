import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../registration/widgets/registration_scaffold.dart';
import '../../domain/driver_onboarding_application.dart';
import '../../../super_app/domain/ride_type_catalogue.dart';

const _vehicleColours = [
  'White',
  'Black',
  'Silver',
  'Grey',
  'Red',
  'Blue',
  'Green',
  'Beige',
  'Other',
];

/// Driver registration — single-scroll form matching the partner
/// registration designs. Collects every field the design shows (photo,
/// name, mobile, vehicle type/colour/registration, document uploads) plus
/// the fields the onboarding API requires (CNIC, home city, licence
/// number/expiry, make, model, year).
class DriverRegistrationView extends ConsumerStatefulWidget {
  const DriverRegistrationView({super.key});

  @override
  ConsumerState<DriverRegistrationView> createState() =>
      _DriverRegistrationViewState();
}

class _DriverRegistrationViewState
    extends ConsumerState<DriverRegistrationView> {
  final _scrollController = ScrollController();
  late final TextEditingController _fullNameController;
  late final TextEditingController _mobileController;
  final _cnicController = TextEditingController();
  final _cityController = TextEditingController();
  final _licenseController = TextEditingController();
  final _expiryController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _plateController = TextEditingController();
  final _picker = ImagePicker();
  final Map<String, String> _errors = {};

  String? _vehicleCategory;
  String? _vehicleColour;
  XFile? _profilePhoto;
  XFile? _vehiclePhoto;
  XFile? _registrationCertificate;
  XFile? _drivingLicence;
  XFile? _cnicPhoto;
  bool _confirmed = false;
  bool _submitting = false;
  String? _submitError;

  List<RideTypeOption> get _vehicleOptions => kRideTypeCatalogue
      .where((option) => option.action is RideCategoryAction)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final profile = ref.read(sessionUserProfileProvider);
    _fullNameController = TextEditingController(
      text: profile?.displayName ?? '',
    );
    _mobileController = TextEditingController(
      text: profile?.phoneNumber ?? '',
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _mobileController.dispose();
    _cnicController.dispose();
    _cityController.dispose();
    _licenseController.dispose();
    _expiryController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  void _changed(String field) {
    setState(() {
      _errors.remove(field);
      _submitError = null;
    });
  }

  bool _required(String field, String label, String value, int min, int max) {
    final length = value.trim().length;
    if (length < min || length > max) {
      _errors[field] = '$label must be $min–$max characters.';
      return false;
    }
    return true;
  }

  bool _validate() {
    _errors.clear();
    _required('fullName', 'Full name', _fullNameController.text, 2, 64);
    final cnic = _cnicController.text.trim();
    if (!RegExp(r'^\d{5}-\d{7}-\d$').hasMatch(cnic)) {
      _errors['cnicNumber'] = 'Enter a valid 13-digit CNIC.';
    }
    _required('homeCity', 'Home city', _cityController.text, 2, 64);
    if (_vehicleCategory == null) {
      _errors['vehicleCategory'] = 'Select a vehicle category.';
    }
    if (_vehicleColour == null) {
      _errors['vehicleColor'] = 'Select a vehicle colour.';
    }
    _required('vehicleMake', 'Vehicle make', _makeController.text, 1, 64);
    _required('vehicleModel', 'Vehicle model', _modelController.text, 1, 64);
    final year = int.tryParse(_yearController.text.trim());
    final maxYear = DateTime.now().toUtc().year + 1;
    if (year == null || year < 1980 || year > maxYear) {
      _errors['vehicleYear'] = 'Enter a year from 1980 to $maxYear.';
    }
    _required('plateNumber', 'Plate number', _plateController.text, 2, 16);
    _required(
      'licenseNumber',
      'Licence number',
      _licenseController.text,
      3,
      32,
    );
    final expiry = _expiryController.text;
    final parsed = DateTime.tryParse(expiry);
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != expiry ||
        expiry.compareTo(today) < 0) {
      _errors['licenseExpiry'] = 'Choose a valid date not before today.';
    }
    if (!_confirmed) {
      _errors['confirmation'] = 'Confirm these details before submitting.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(_expiryController.text) ??
        DateTime(now.year + 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2100),
      helpText: 'Select licence expiry',
    );
    if (picked == null || !mounted) return;
    _expiryController.text =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    _changed('licenseExpiry');
  }

  Future<void> _pickVehicleCategory() async {
    final options = [
      for (final option in _vehicleOptions)
        RegOption(
          option.name,
          imageAsset: option.image,
          key: ValueKey(
            'driver-category-'
            '${(option.action as RideCategoryAction).categoryId}',
          ),
        ),
    ];
    final selected = await showRegOptions(
      context,
      title: 'Vehicle type',
      options: options,
      selected: _categoryName().isEmpty ? null : _categoryName(),
    );
    if (selected == null || !mounted) return;
    for (final option in _vehicleOptions) {
      if (option.name == selected) {
        setState(() {
          _vehicleCategory =
              (option.action as RideCategoryAction).categoryId;
          _errors.remove('vehicleCategory');
        });
        return;
      }
    }
  }

  Future<void> _pickVehicleColour() async {
    final selected = await showRegOptions(
      context,
      title: 'Vehicle colour',
      options: [
        for (final colour in _vehicleColours)
          RegOption(
            colour,
            icon: Icons.palette_outlined,
            key: ValueKey('driver-colour-${colour.toLowerCase()}'),
          ),
      ],
      selected: _vehicleColour,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _vehicleColour = selected;
      _errors.remove('vehicleColor');
    });
  }

  Future<void> _pickPhoto(void Function(XFile) apply) async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => apply(file));
    } catch (_) {
      // Picker unavailable (e.g. plugin missing in tests) — keep the tile
      // in its unpicked state rather than surfacing a crash.
    }
  }

  String _categoryName() {
    for (final option in _vehicleOptions) {
      if ((option.action as RideCategoryAction).categoryId ==
          _vehicleCategory) {
        return option.name;
      }
    }
    return '';
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final application = DriverOnboardingApplication(
      fullName: _fullNameController.text.trim(),
      cnicNumber: _cnicController.text.trim(),
      homeCity: _cityController.text.trim(),
      licenseNumber: _licenseController.text.trim(),
      licenseExpiry: _expiryController.text,
      vehicleCategory: _vehicleCategory!,
      vehicleMake: _makeController.text.trim(),
      vehicleModel: _modelController.text.trim(),
      vehicleYear: int.parse(_yearController.text.trim()),
      vehicleColor: _vehicleColour!,
      plateNumber: _plateController.text.trim(),
    );
    try {
      final result = await ref
          .read(submitDriverOnboardingUseCaseProvider)
          .call(application);
      await ref
          .read(authStateNotifierProvider.notifier)
          .refreshCanonicalProfile();
      if (!mounted) return;
      if (result.approved) {
        context.go(AppRoutes.driverHome);
      } else {
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
                    'Your application is saved. You can continue using ORA '
                    'while it is under review.',
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
    List<TextInputFormatter>? inputFormatters,
    bool verified = false,
  }) {
    final errorField = switch (field) {
      'full-name' => 'fullName',
      'mobile-number' => 'mobileNumber',
      'cnic-number' => 'cnicNumber',
      'home-city' => 'homeCity',
      'license-number' => 'licenseNumber',
      'vehicle-make' => 'vehicleMake',
      'vehicle-model' => 'vehicleModel',
      'vehicle-year' => 'vehicleYear',
      'plate-number' => 'plateNumber',
      _ => field,
    };
    return RegFieldTile(
      fieldKey: ValueKey('driver-$field'),
      icon: icon,
      label: label,
      controller: controller,
      hint: hint,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      inputFormatters: inputFormatters,
      verified: verified,
      errorText: _errors[errorField],
      onChanged: (_) => _changed(errorField),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OraRegistrationScaffold(
      title: 'Driver\nRegistration',
      subtitle: 'Join ORA and start earning today!',
      heroAsset: 'assets/brand/reg_rides.webp',
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: OraSpacing.sm),
          const RegInfoBanner(),
          if (_submitError != null) ...[
            const SizedBox(height: OraSpacing.sm),
            Text(
              _submitError!,
              key: const ValueKey('driver-submit-error'),
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
        const RegSection(number: 1, title: 'Personal Information'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RegAvatarUpload(
              photo: _profilePhoto,
              onPick: () => _pickPhoto((f) => _profilePhoto = f),
            ),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Column(
                children: [
                  _field(
                    field: 'full-name',
                    icon: Icons.person_outline_rounded,
                    label: 'Full Name',
                    controller: _fullNameController,
                    hint: 'Ali Raza',
                    capitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  _field(
                    field: 'mobile-number',
                    icon: Icons.phone_iphone_rounded,
                    label: 'Mobile Number',
                    controller: _mobileController,
                    hint: '0300 1234567',
                    keyboardType: TextInputType.phone,
                    verified: _mobileController.text.trim().isNotEmpty,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            _field(
              field: 'cnic-number',
              icon: Icons.badge_outlined,
              label: 'CNIC Number',
              controller: _cnicController,
              hint: '#####-#######-#',
              keyboardType: TextInputType.number,
              inputFormatters: const [_CnicInputFormatter()],
            ),
            _field(
              field: 'home-city',
              icon: Icons.location_city_rounded,
              label: 'Home City',
              controller: _cityController,
              hint: 'e.g. Lahore',
              capitalization: TextCapitalization.words,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(number: 2, title: 'Vehicle Information'),
        RegRow(
          children: [
            RegDropdownTile(
              tileKey: const ValueKey('driver-vehicle-type'),
              icon: Icons.directions_car_filled_rounded,
              label: 'Vehicle Type',
              value: _categoryName(),
              placeholder: 'Select type',
              errorText: _errors['vehicleCategory'],
              onTap: _pickVehicleCategory,
            ),
            RegDropdownTile(
              tileKey: const ValueKey('driver-vehicle-colour'),
              icon: Icons.palette_outlined,
              label: 'Vehicle Colour',
              value: _vehicleColour,
              placeholder: 'Select colour',
              errorText: _errors['vehicleColor'],
              onTap: _pickVehicleColour,
            ),
            _field(
              field: 'plate-number',
              icon: Icons.pin_outlined,
              label: 'Registration Number',
              controller: _plateController,
              hint: 'LEA-1234',
              capitalization: TextCapitalization.characters,
              verified: _plateController.text.trim().length >= 2,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            _field(
              field: 'vehicle-make',
              icon: Icons.factory_outlined,
              label: 'Vehicle Make',
              controller: _makeController,
              hint: 'e.g. Toyota',
              capitalization: TextCapitalization.words,
            ),
            _field(
              field: 'vehicle-model',
              icon: Icons.directions_car_outlined,
              label: 'Vehicle Model',
              controller: _modelController,
              hint: 'e.g. Corolla',
              capitalization: TextCapitalization.words,
            ),
            _field(
              field: 'vehicle-year',
              icon: Icons.calendar_month_rounded,
              label: 'Vehicle Year',
              controller: _yearController,
              hint: 'e.g. 2024',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegUploadTile(
          title: 'Vehicle Photo',
          subtitle: 'Front view of your vehicle',
          icon: Icons.directions_car_filled_rounded,
          file: _vehiclePhoto,
          onPick: () => _pickPhoto((f) => _vehiclePhoto = f),
        ),
        const SizedBox(height: OraSpacing.lg),
        const RegSection(
          number: 3,
          title: 'Vehicle Registration Documents',
        ),
        RegRow(
          children: [
            RegUploadTile(
              title: 'Registration Certificate',
              subtitle: 'Smart Card / Book',
              file: _registrationCertificate,
              onPick: () =>
                  _pickPhoto((f) => _registrationCertificate = f),
            ),
            RegUploadTile(
              title: 'Driving Licence',
              subtitle: 'Front Side',
              icon: Icons.contact_page_outlined,
              file: _drivingLicence,
              onPick: () => _pickPhoto((f) => _drivingLicence = f),
            ),
            RegUploadTile(
              title: 'CNIC',
              subtitle: 'Front & Back',
              icon: Icons.badge_outlined,
              file: _cnicPhoto,
              onPick: () => _pickPhoto((f) => _cnicPhoto = f),
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.sm),
        RegRow(
          children: [
            _field(
              field: 'license-number',
              icon: Icons.contact_page_outlined,
              label: 'Licence Number',
              controller: _licenseController,
              hint: 'Enter licence number',
              capitalization: TextCapitalization.characters,
            ),
            RegDropdownTile(
              tileKey: const ValueKey('driver-license-expiry'),
              icon: Icons.calendar_month_rounded,
              label: 'Licence Expiry',
              value: _expiryController.text.isEmpty
                  ? null
                  : _expiryController.text,
              placeholder: 'Choose expiry date',
              errorText: _errors['licenseExpiry'],
              onTap: _pickExpiry,
            ),
          ],
        ),
        const SizedBox(height: OraSpacing.md),
        Semantics(
          checked: _confirmed,
          child: OraCard(
            key: const ValueKey('driver-confirm-details'),
            padding: const EdgeInsets.symmetric(
              horizontal: OraSpacing.sm,
              vertical: OraSpacing.xs,
            ),
            onTap: _submitting
                ? null
                : () => setState(() {
                    _confirmed = !_confirmed;
                    _errors.remove('confirmation');
                  }),
            child: Row(
              children: [
                Icon(
                  _confirmed
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: _confirmed
                      ? OraColors.gold
                      : OraColors.textMuted,
                ),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Text(
                    'I confirm these details are correct',
                    style: OraTypography.body(OraColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errors['confirmation'] != null)
          Padding(
            padding: const EdgeInsets.only(top: OraSpacing.xs),
            child: Text(
              _errors['confirmation']!,
              style: OraTypography.caption(OraColors.danger),
            ),
          ),
      ],

    );
  }
}

class _CnicInputFormatter extends TextInputFormatter {
  const _CnicInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 13) digits = digits.substring(0, 13);
    final formatted = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index == 5 || index == 12) formatted.write('-');
      formatted.write(digits[index]);
    }
    final text = formatted.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}
