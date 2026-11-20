import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../app/di/providers.dart';
import '../../../marketplace/catalogue/catalogue_models.dart';
import '../../../marketplace/catalogue/catalogue_provider.dart';
import '../../../marketplace/data/listing_photo_codec.dart';
import '../../../marketplace/data/marketplace_models.dart';
import '../../../marketplace/data/marketplace_providers.dart';
import '../../../registration/widgets/registration_scaffold.dart'
    show RegOption, showRegOptions;
import '../../../vendor/presentation/widgets/vendor_ui_kit.dart';

const _priceUnits = ['Per Day', 'Per Week', 'Per Month', 'Per Year'];

const _amenityOptions = [
  (label: 'Wi-Fi', icon: Icons.wifi_rounded),
  (label: 'AC', icon: Icons.ac_unit_rounded),
  (label: 'Parking', icon: Icons.local_parking_rounded),
  (label: 'Furnished', icon: Icons.chair_rounded),
  (label: 'Kitchen', icon: Icons.soup_kitchen_rounded),
  (label: 'TV', icon: Icons.tv_rounded),
  (label: 'Security', icon: Icons.verified_user_rounded),
  (label: 'Laundry', icon: Icons.local_laundry_service_rounded),
];

const _maxPhotos = 6;
const _minPhotos = 1;

/// "Post a Rental Property" — the rental-vendor publishing form. Posts to
/// /v1/vendor/listings; opened with [existing] it edits via PATCH instead.
class RentalPostPropertyView extends ConsumerStatefulWidget {
  const RentalPostPropertyView({super.key, this.existing});

  final MarketplaceListing? existing;

  @override
  ConsumerState<RentalPostPropertyView> createState() =>
      _RentalPostPropertyViewState();
}

class _RentalPostPropertyViewState
    extends ConsumerState<RentalPostPropertyView> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final Map<String, String> _errors = {};

  RentalCategory? _category;
  RentalSubcategory? _subcategory;
  String _priceUnit = 'Per Month';
  DateTime? _availableFrom;
  DateTime? _availableTo;
  final Set<String> _amenities = {};
  final List<XFile> _photos = [];
  final List<String> _existingPhotos = [];
  bool _submitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) return;
    _titleController.text = existing.title;
    _descriptionController.text = existing.description;
    _priceController.text = existing.price.toString();
    _locationController.text = existing.location;
    _contactController.text = existing.contactNumber;
    _emailController.text = existing.email ?? '';
    _priceUnit = _priceUnits.contains(existing.priceUnit)
        ? existing.priceUnit
        : 'Per Month';
    _amenities.addAll(existing.amenities);
    _existingPhotos.addAll(existing.photos);
    _availableFrom = DateTime.tryParse(existing.availableFrom ?? '');
    _availableTo = DateTime.tryParse(existing.availableTo ?? '');
    final catalogue = ref.read(catalogueProvider).value;
    _category = catalogue?.rentalCategory(existing.categoryId);
    if (_category != null) {
      for (final sub in _category!.subcategories) {
        if (sub.id == existing.subcategoryId) _subcategory = sub;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _clearError(String field) => setState(() => _errors.remove(field));

  bool _validate() {
    _errors.clear();
    if (_titleController.text.trim().length < 3) {
      _errors['title'] = 'Enter a property title.';
    }
    if (_descriptionController.text.trim().length < 10) {
      _errors['description'] = 'Describe your property (min 10 characters).';
    }
    if (_subcategory == null) {
      _errors['propertyType'] = 'Select a property type.';
    }
    final price = int.tryParse(_priceController.text.replaceAll(',', ''));
    if (price == null || price <= 0) {
      _errors['price'] = 'Enter a valid rent.';
    }
    if (_locationController.text.trim().length < 3) {
      _errors['location'] = 'Enter the property location.';
    }
    if (_photos.length + _existingPhotos.length < _minPhotos) {
      _errors['photos'] = 'Add at least $_minPhotos photo.';
    }
    if (_contactController.text.trim().length < 10) {
      _errors['contact'] = 'Enter a contact number.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _pickPropertyType() async {
    final catalogue = ref.read(catalogueProvider).value;
    if (catalogue == null || catalogue.rental.isEmpty) return;
    final options = <String, (RentalCategory, RentalSubcategory)>{};
    for (final c in catalogue.rental) {
      for (final s in c.subcategories) {
        options['${s.name} · ${c.name}'] = (c, s);
      }
    }
    final picked = await showRegOptions(
      context,
      title: 'Property type',
      options: [for (final label in options.keys) RegOption(label)],
      selected: _subcategory == null || _category == null
          ? null
          : '${_subcategory!.name} · ${_category!.name}',
    );
    if (picked == null || !mounted) return;
    final entry = options[picked];
    if (entry == null) return;
    setState(() {
      _category = entry.$1;
      _subcategory = entry.$2;
      _errors.remove('propertyType');
    });
  }

  Future<void> _pickUnit() async {
    final picked = await showRegOptions(
      context,
      title: 'Rent unit',
      options: [for (final u in _priceUnits) RegOption(u)],
      selected: _priceUnit,
    );
    if (picked == null || !mounted) return;
    setState(() => _priceUnit = picked);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_availableFrom ?? now)
          : (_availableTo ?? _availableFrom ?? now),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _availableFrom = picked;
      } else {
        _availableTo = picked;
      }
    });
  }

  Future<void> _addPhotos() async {
    final remaining = _maxPhotos - _photos.length - _existingPhotos.length;
    if (remaining <= 0) return;
    List<XFile> picked = const [];
    try {
      picked = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      picked = const [];
    }
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _photos.addAll(picked.take(remaining));
      _errors.remove('photos');
    });
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) return;
    final subcategory = _subcategory!;
    setState(() => _submitting = true);
    try {
      final photos = [
        ..._existingPhotos,
        ...await encodeListingPhotos(_photos),
      ];
      final details = <String, dynamic>{
        'subcategoryName': subcategory.name,
        if (_availableFrom != null) 'availableFrom': _isoDate(_availableFrom!),
        if (_availableTo != null) 'availableTo': _isoDate(_availableTo!),
        if (_amenities.isNotEmpty) 'amenities': _amenities.toList(),
        if (_emailController.text.trim().isNotEmpty)
          'email': _emailController.text.trim(),
      };
      final body = <String, dynamic>{
        'type': 'rental',
        'categoryId': _category!.id,
        'subcategoryId': subcategory.id,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': int.parse(_priceController.text.replaceAll(',', '')),
        'priceUnit': _priceUnit,
        'location': _locationController.text.trim(),
        'contactNumber': _contactController.text.trim(),
        'details': details,
        'photos': photos,
      };
      final mutations = ref.read(listingMutationsProvider);
      final existing = widget.existing;
      if (existing != null) {
        await mutations.update(existing, body..remove('type'));
      } else {
        await mutations.create(body);
      }
      if (!mounted) return;
      await showOraBottomSheet<void>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OraSectionHeader(
              title: _isEdit ? 'Listing updated' : 'Property posted — now live',
              description: _isEdit
                  ? 'Your changes are live on the Rental pages.'
                  : 'Your rental property is live under the property type '
                        'you chose. Customers can find it on the Rental pages.',
            ),
            const SizedBox(height: OraSpacing.lg),
            OraButton(
              label: 'View my properties',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      if (!mounted) return;
      context.go(AppRoutes.rentalVendorHome);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errors['submit'] = ref
            .read(failureMapperProvider)
            .fromException(error)
            .userMessage;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Widget _errorText(String field) {
    final error = _errors[field];
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: OraSpacing.xxs),
      child: Text(error, style: OraTypography.caption(OraColors.danger)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const padding = OraSpacing.md;
    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      body: Column(
        children: [
          const VendorHeroTop(
            asset: 'assets/vendor/rental_top.png',
            topStrip: [Color(0xFFFE7709), Color(0xFFFE810E), Color(0xFFFEE0D0)],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(padding, 0, padding, 40),
              children: [
                const SizedBox(height: OraSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(OraSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F3),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const VendorFieldLabel(
                        icon: Icons.home_rounded,
                        label: 'Property / Rental Title',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      VendorTextField(
                        controller: _titleController,
                        hint: 'e.g. 2-Bed Apartment in Gulberg, Lahore',
                        textCapitalization: TextCapitalization.sentences,
                        error: _errors['title'] != null,
                        onChanged: (_) => _clearError('title'),
                      ),
                      _errorText('title'),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.notes_rounded,
                        label: 'Detailed Description',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      VendorTextField(
                        controller: _descriptionController,
                        hint:
                            'Write a detailed description about your '
                            'property...\n(e.g. size, features, nearby '
                            'places, rules, etc.)',
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 4,
                        maxLength: 500,
                        error: _errors['description'] != null,
                        onChanged: (_) => _clearError('description'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_descriptionController.text.length}/500',
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ),
                      _errorText('description'),
                      const SizedBox(height: OraSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const VendorFieldLabel(
                                  icon: Icons.layers_rounded,
                                  label: 'Property Type',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorPickerTile(
                                  placeholder: 'Select',
                                  value: _subcategory?.name,
                                  error: _errors['propertyType'] != null,
                                  onTap: _pickPropertyType,
                                ),
                                _errorText('propertyType'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const VendorFieldLabel(
                                  icon: Icons.payments_rounded,
                                  label: 'Rental Price',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorTextField(
                                  controller: _priceController,
                                  hint: 'Enter price',
                                  prefixText: 'Rs. ',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  error: _errors['price'] != null,
                                  onChanged: (_) => _clearError('price'),
                                ),
                                const SizedBox(height: OraSpacing.xxs),
                                VendorPickerTile(
                                  placeholder: '/ Month',
                                  value: _priceUnit,
                                  onTap: _pickUnit,
                                ),
                                _errorText('price'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const VendorFieldLabel(
                                  icon: Icons.location_on_rounded,
                                  label: 'Location',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorTextField(
                                  controller: _locationController,
                                  hint: 'Enter address',
                                  suffixIcon: const Icon(
                                    Icons.my_location_rounded,
                                    size: 18,
                                    color: OraColors.gold,
                                  ),
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  error: _errors['location'] != null,
                                  onChanged: (_) => _clearError('location'),
                                ),
                                _errorText('location'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const VendorFieldLabel(
                                  icon: Icons.calendar_month_rounded,
                                  label: 'Availability',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorPickerTile(
                                  placeholder: 'From',
                                  value: _availableFrom == null
                                      ? null
                                      : _fmtDate(_availableFrom!),
                                  onTap: () => _pickDate(isFrom: true),
                                ),
                                const SizedBox(height: OraSpacing.xxs),
                                VendorPickerTile(
                                  placeholder: 'To',
                                  value: _availableTo == null
                                      ? null
                                      : _fmtDate(_availableTo!),
                                  onTap: () => _pickDate(isFrom: false),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.star_rounded,
                        label: 'Amenities (Select all that apply)',
                        required: false,
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final chipW =
                              (constraints.maxWidth - OraSpacing.xs) / 2;
                          return Wrap(
                            spacing: OraSpacing.xs,
                            runSpacing: OraSpacing.xs,
                            children: [
                              for (final option in _amenityOptions)
                                SizedBox(
                                  width: chipW,
                                  child: VendorFeatureChip(
                                    icon: option.icon,
                                    label: option.label,
                                    selected: _amenities.contains(option.label),
                                    onChanged: (selected) => setState(() {
                                      if (selected) {
                                        _amenities.add(option.label);
                                      } else {
                                        _amenities.remove(option.label);
                                      }
                                    }),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: OraSpacing.md),
                      VendorFieldLabel(
                        icon: Icons.photo_camera_rounded,
                        label: 'Add Property Photos',
                        trailing: Text(
                          '${_photos.length + _existingPhotos.length}/$_maxPhotos Photos',
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: OraSpacing.xxs),
                      Text(
                        'Upload clear and high-quality images '
                        '(min 1, max $_maxPhotos)',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      SizedBox(
                        height: 92,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            VendorUploadTile(onTap: _addPhotos),
                            const SizedBox(width: OraSpacing.xs),
                            for (
                              var i = 0;
                              i < _existingPhotos.length;
                              i++
                            ) ...[
                              VendorRemotePhotoThumb(
                                image: MarketplaceListing.photoProvider(
                                  _existingPhotos[i],
                                ),
                                onRemove: () =>
                                    setState(() => _existingPhotos.removeAt(i)),
                              ),
                              const SizedBox(width: OraSpacing.xs),
                            ],
                            for (var i = 0; i < _photos.length; i++) ...[
                              VendorPhotoThumb(
                                file: File(_photos[i].path),
                                onRemove: () =>
                                    setState(() => _photos.removeAt(i)),
                              ),
                              const SizedBox(width: OraSpacing.xs),
                            ],
                            if ((_photos.length + _existingPhotos.length) <
                                _maxPhotos)
                              VendorAddPhotoTile(onTap: _addPhotos),
                          ],
                        ),
                      ),
                      _errorText('photos'),
                      _errorText('submit'),
                      const SizedBox(height: OraSpacing.lg),
                      const VendorFieldLabel(
                        icon: Icons.person_rounded,
                        label: 'Contact Details',
                      ),
                      const SizedBox(height: OraSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VendorTextField(
                                  controller: _contactController,
                                  hint: '0300 1234567',
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9+\s-]'),
                                    ),
                                  ],
                                  error: _errors['contact'] != null,
                                  onChanged: (_) => _clearError('contact'),
                                ),
                                _errorText('contact'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: VendorTextField(
                              controller: _emailController,
                              hint: 'your@email.com',
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.lg),
                      OraButton(
                        label: _isEdit
                            ? 'Save changes'
                            : 'Post Rental Property',
                        trailingIcon: Icons.arrow_forward_rounded,
                        isLoading: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
