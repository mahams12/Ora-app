import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../domain/driver_onboarding_application.dart';
import '../../../super_app/domain/ride_type_catalogue.dart';

const _stepTitles = ['Personal', 'Licence', 'Vehicle', 'Review'];

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
  final _cnicController = TextEditingController();
  final _cityController = TextEditingController();
  final _licenseController = TextEditingController();
  final _expiryController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();
  final _plateController = TextEditingController();
  final Map<String, String> _errors = {};
  int _step = 0;
  String? _vehicleCategory;
  bool _confirmed = false;
  bool _submitting = false;
  String? _submitError;

  List<RideTypeOption> get _vehicleOptions => kRideTypeCatalogue
      .where((option) => option.action is RideCategoryAction)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: ref.read(sessionUserProfileProvider)?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fullNameController.dispose();
    _cnicController.dispose();
    _cityController.dispose();
    _licenseController.dispose();
    _expiryController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
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

  bool _validateStep() {
    final stepErrors = <String, String>{};
    _errors.clear();
    switch (_step) {
      case 0:
        _required('fullName', 'Full name', _fullNameController.text, 2, 64);
        final cnic = _cnicController.text.trim();
        if (!RegExp(r'^\d{5}-\d{7}-\d$').hasMatch(cnic)) {
          _errors['cnicNumber'] = 'Enter a valid 13-digit CNIC.';
        }
        _required('homeCity', 'Home city', _cityController.text, 2, 64);
      case 1:
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
      case 2:
        if (_vehicleCategory == null) {
          _errors['vehicleCategory'] = 'Select a vehicle category.';
        }
        _required('vehicleMake', 'Vehicle make', _makeController.text, 1, 64);
        _required(
          'vehicleModel',
          'Vehicle model',
          _modelController.text,
          1,
          64,
        );
        final year = int.tryParse(_yearController.text.trim());
        final maxYear = DateTime.now().toUtc().year + 1;
        if (year == null || year < 1980 || year > maxYear) {
          _errors['vehicleYear'] = 'Enter a year from 1980 to $maxYear.';
        }
        _required(
          'vehicleColor',
          'Vehicle colour',
          _colorController.text,
          1,
          32,
        );
        _required('plateNumber', 'Plate number', _plateController.text, 2, 16);
      case 3:
        if (!_confirmed) {
          _errors['confirmation'] = 'Confirm these details before submitting.';
        }
    }
    stepErrors.addAll(_errors);
    setState(() {});
    return stepErrors.isEmpty;
  }

  void _continue() {
    if (!_validateStep()) return;
    if (_step == _stepTitles.length - 1) {
      _submit();
      return;
    }
    setState(() => _step++);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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

  Future<void> _submit() async {
    if (_submitting || !_validateStep()) return;
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
      vehicleColor: _colorController.text.trim(),
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

  Widget _textField({
    required String field,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization capitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final errorField = switch (field) {
      'full-name' => 'fullName',
      'cnic-number' => 'cnicNumber',
      'home-city' => 'homeCity',
      'license-number' => 'licenseNumber',
      'vehicle-make' => 'vehicleMake',
      'vehicle-model' => 'vehicleModel',
      'vehicle-year' => 'vehicleYear',
      'vehicle-color' => 'vehicleColor',
      'plate-number' => 'plateNumber',
      _ => field,
    };
    return OraTextField(
      key: ValueKey('driver-$field'),
      controller: controller,
      label: label,
      hint: hint,
      errorText: _errors[errorField],
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      inputFormatters: inputFormatters,
      onChanged: (_) => _changed(errorField),
    );
  }

  Widget _buildPersonalStep() => Column(
    children: [
      _textField(
        field: 'full-name',
        label: 'Full name',
        controller: _fullNameController,
        hint: 'As shown on your documents',
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'cnic-number',
        label: 'CNIC number',
        controller: _cnicController,
        hint: '#####-#######-#',
        keyboardType: TextInputType.number,
        inputFormatters: const [_CnicInputFormatter()],
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'home-city',
        label: 'Home city',
        controller: _cityController,
        hint: 'e.g. Lahore',
        capitalization: TextCapitalization.words,
      ),
    ],
  );

  Widget _buildLicenseStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _textField(
        field: 'license-number',
        label: 'Licence number',
        controller: _licenseController,
        hint: 'Enter your licence number',
        capitalization: TextCapitalization.characters,
      ),
      const SizedBox(height: OraSpacing.md),
      Text(
        'Licence expiry',
        style: OraTypography.label(OraColors.textSecondary),
      ),
      const SizedBox(height: OraSpacing.xs),
      OraCard(
        key: const ValueKey('driver-license-expiry'),
        onTap: _pickExpiry,
        child: Row(
          children: [
            const Icon(Icons.calendar_month, color: OraColors.primary),
            const SizedBox(width: OraSpacing.sm),
            Expanded(
              child: Text(
                _expiryController.text.isEmpty
                    ? 'Choose expiry date'
                    : _expiryController.text,
                style: OraTypography.body(
                  _expiryController.text.isEmpty
                      ? OraColors.textMuted
                      : OraColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: OraColors.textMuted),
          ],
        ),
      ),
      if (_errors['licenseExpiry'] != null)
        Padding(
          padding: const EdgeInsets.only(top: OraSpacing.xs),
          child: Text(
            _errors['licenseExpiry']!,
            style: OraTypography.caption(OraColors.danger),
          ),
        ),
    ],
  );

  Widget _buildVehicleStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Ride category',
        style: OraTypography.label(OraColors.textSecondary),
      ),
      const SizedBox(height: OraSpacing.sm),
      if (_errors['vehicleCategory'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: OraSpacing.xs),
          child: Text(
            _errors['vehicleCategory']!,
            style: OraTypography.caption(OraColors.danger),
          ),
        ),
      GridView.builder(
        key: const ValueKey('driver-category-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _vehicleOptions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: OraSpacing.sm,
          crossAxisSpacing: OraSpacing.sm,
          childAspectRatio: 1.6,
        ),
        itemBuilder: (context, index) {
          final option = _vehicleOptions[index];
          final category = (option.action as RideCategoryAction).categoryId;
          return OraCard(
            key: ValueKey('driver-category-$category'),
            variant: OraCardVariant.selectable,
            selected: category == _vehicleCategory,
            onTap: () => setState(() {
              _vehicleCategory = category;
              _errors.remove('vehicleCategory');
            }),
            padding: const EdgeInsets.all(OraSpacing.xs),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    option.image,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: OraSpacing.xs),
                Expanded(
                  child: Text(
                    option.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.bodyEmphasis(OraColors.textPrimary),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'vehicle-make',
        label: 'Make',
        controller: _makeController,
        hint: 'e.g. Honda',
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'vehicle-model',
        label: 'Model',
        controller: _modelController,
        hint: 'e.g. City',
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'vehicle-year',
        label: 'Year',
        controller: _yearController,
        hint: 'e.g. 2024',
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'vehicle-color',
        label: 'Colour',
        controller: _colorController,
        hint: 'e.g. White',
        capitalization: TextCapitalization.words,
      ),
      const SizedBox(height: OraSpacing.md),
      _textField(
        field: 'plate-number',
        label: 'Plate number',
        controller: _plateController,
        hint: 'e.g. LEA-1234',
        capitalization: TextCapitalization.characters,
      ),
    ],
  );

  String _categoryName() {
    for (final option in _vehicleOptions) {
      if ((option.action as RideCategoryAction).categoryId ==
          _vehicleCategory) {
        return option.name;
      }
    }
    return '';
  }

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: OraSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: OraTypography.caption(OraColors.textMuted)),
        ),
        Expanded(
          child: Text(value, style: OraTypography.body(OraColors.textPrimary)),
        ),
      ],
    ),
  );

  Widget _buildReviewStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OraCard(
        child: Column(
          children: [
            _reviewRow('Full name', _fullNameController.text.trim()),
            _reviewRow('CNIC', _cnicController.text),
            _reviewRow('Home city', _cityController.text.trim()),
            _reviewRow('Licence number', _licenseController.text.trim()),
            _reviewRow('Licence expiry', _expiryController.text),
            _reviewRow('Ride category', _categoryName()),
            _reviewRow(
              'Vehicle',
              '${_makeController.text.trim()} ${_modelController.text.trim()}',
            ),
            _reviewRow('Year', _yearController.text.trim()),
            _reviewRow('Colour', _colorController.text.trim()),
            _reviewRow('Plate', _plateController.text.trim().toUpperCase()),
          ],
        ),
      ),
      const SizedBox(height: OraSpacing.md),
      OraCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            key: const ValueKey('driver-confirm-details'),
            value: _confirmed,
            onChanged: _submitting
                ? null
                : (value) => setState(() {
                    _confirmed = value ?? false;
                    _errors.remove('confirmation');
                  }),
            activeColor: OraColors.gold,
            title: const Text('I confirm these details are correct'),
            controlAffinity: ListTileControlAffinity.leading,
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

  Widget _buildStep() => switch (_step) {
    0 => _buildPersonalStep(),
    1 => _buildLicenseStep(),
    2 => _buildVehicleStep(),
    _ => _buildReviewStep(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Driver registration')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConstants.maxContentWidth,
            ),
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(OraSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step ${_step + 1} of 4 · ${_stepTitles[_step]}',
                    key: ValueKey('driver-step-$_step'),
                    style: OraTypography.label(OraColors.primary),
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _stepTitles.length,
                      minHeight: 6,
                      backgroundColor: OraColors.border,
                      valueColor: const AlwaysStoppedAnimation(OraColors.gold),
                    ),
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  Text(
                    _stepTitles[_step],
                    style: OraTypography.display(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.md),
                  _buildStep(),
                  const SizedBox(height: OraSpacing.md),
                  OraCard(
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: OraColors.info),
                        const SizedBox(width: OraSpacing.sm),
                        Expanded(
                          child: Text(
                            'Document photo upload will be added with admin review.',
                            style: OraTypography.caption(OraColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: OraSpacing.sm),
                    Text(
                      _submitError!,
                      key: const ValueKey('driver-submit-error'),
                      style: OraTypography.body(OraColors.danger),
                    ),
                  ],
                  const SizedBox(height: OraSpacing.lg),
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OraButton(
                            label: 'Back',
                            variant: OraButtonVariant.outline,
                            onPressed: _submitting
                                ? null
                                : () {
                                    setState(() => _step--);
                                    if (_scrollController.hasClients) {
                                      _scrollController.jumpTo(0);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: OraSpacing.sm),
                      ],
                      Expanded(
                        flex: _step == _stepTitles.length - 1 ? 2 : 1,
                        child: OraButton(
                          label: _step == _stepTitles.length - 1
                              ? 'Submit application'
                              : 'Continue',
                          isLoading: _submitting,
                          onPressed: _submitting ? null : _continue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
