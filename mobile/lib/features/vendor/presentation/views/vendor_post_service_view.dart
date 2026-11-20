import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../../app/di/providers.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../marketplace/catalogue/catalogue_models.dart';
import '../../../marketplace/catalogue/catalogue_provider.dart';
import '../../../marketplace/data/listing_photo_codec.dart';
import '../../../marketplace/data/marketplace_models.dart';
import '../../../marketplace/data/marketplace_providers.dart';
import '../../../registration/widgets/registration_scaffold.dart'
    show RegOption, showRegOptions;
import '../widgets/vendor_ui_kit.dart';

const _priceUnits = [
  'Per Service',
  'Per Visit',
  'Per Hour',
  'Per Day',
  'Per Job',
];

const _featureOptions = [
  (label: 'On-site Service', icon: Icons.build_rounded),
  (label: 'Express Service', icon: Icons.bolt_rounded),
  (label: 'Warranty', icon: Icons.verified_user_rounded),
  (label: 'Parts Included', icon: Icons.settings_rounded),
  (label: 'Emergency', icon: Icons.emergency_rounded),
  (label: 'Same Day', icon: Icons.today_rounded),
  (label: 'Trained Staff', icon: Icons.groups_rounded),
  (label: '24/7 Support', icon: Icons.headset_mic_rounded),
];

const _maxPhotos = 6;
const _minPhotos = 1;

/// "Post a Service" — the vendor publishing form. Posts to
/// /v1/vendor/listings; opened with [existing] it edits that listing via
/// PATCH instead.
class VendorPostServiceView extends ConsumerStatefulWidget {
  const VendorPostServiceView({super.key, this.existing});

  final MarketplaceListing? existing;

  @override
  ConsumerState<VendorPostServiceView> createState() =>
      _VendorPostServiceViewState();
}

class _VendorPostServiceViewState extends ConsumerState<VendorPostServiceView> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _priceController = TextEditingController();
  final _timingController = TextEditingController();
  final Map<String, String> _errors = {};

  ServiceCategory? _category;
  ServiceSubcategory? _subcategory;
  String _priceUnit = _priceUnits.first;
  DateTime? _availableFrom;
  DateTime? _availableTo;
  final Set<String> _features = {};
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
    _locationController.text = existing.location;
    _priceController.text = existing.price.toString();
    _priceUnit = _priceUnits.contains(existing.priceUnit)
        ? existing.priceUnit
        : _priceUnits.first;
    _timingController.text = existing.timing ?? '';
    _features.addAll(existing.features);
    _existingPhotos.addAll(existing.photos);
    _availableFrom = DateTime.tryParse(existing.availableFrom ?? '');
    _availableTo = DateTime.tryParse(existing.availableTo ?? '');
    final catalogue = ref.read(catalogueProvider).value;
    _category = catalogue?.serviceCategory(existing.categoryId);
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
    _locationController.dispose();
    _priceController.dispose();
    _timingController.dispose();
    super.dispose();
  }

  void _clearError(String field) => setState(() => _errors.remove(field));

  bool _validate() {
    _errors.clear();
    if (_titleController.text.trim().length < 3) {
      _errors['title'] = 'Enter a service title.';
    }
    if (_descriptionController.text.trim().length < 10) {
      _errors['description'] = 'Describe your service (min 10 characters).';
    }
    if (_category == null) {
      _errors['category'] = 'Select a category.';
    }
    if (_subcategory == null) {
      _errors['subcategory'] = 'Select a subcategory.';
    }
    if (_locationController.text.trim().length < 3) {
      _errors['location'] = 'Enter your coverage area.';
    }
    final price = int.tryParse(_priceController.text.replaceAll(',', ''));
    if (price == null || price <= 0) {
      _errors['price'] = 'Enter a valid price.';
    }
    if (_availableFrom == null || _availableTo == null) {
      _errors['availability'] = 'Pick availability dates.';
    }
    if (_photos.length + _existingPhotos.length < _minPhotos) {
      _errors['photos'] = 'Add at least $_minPhotos photo.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _pickCategory() async {
    final catalogue = ref.read(catalogueProvider).value;
    if (catalogue == null || catalogue.services.isEmpty) return;
    final picked = await showRegOptions(
      context,
      title: 'Service category',
      options: [for (final c in catalogue.services) RegOption(c.name)],
      selected: _category?.name,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _category = catalogue.services.firstWhere((c) => c.name == picked);
      _subcategory = null;
      _errors
        ..remove('category')
        ..remove('subcategory');
    });
  }

  Future<void> _pickSubcategory() async {
    final category = _category;
    if (category == null) {
      setState(() => _errors['category'] = 'Pick a category first.');
      return;
    }
    final picked = await showRegOptions(
      context,
      title: 'Subcategory',
      options: [for (final s in category.subcategories) RegOption(s.name)],
      selected: _subcategory?.name,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _subcategory = category.subcategories.firstWhere((s) => s.name == picked);
      _errors.remove('subcategory');
    });
  }

  Future<void> _pickUnit() async {
    final picked = await showRegOptions(
      context,
      title: 'Price unit',
      options: [for (final u in _priceUnits) RegOption(u)],
      selected: _priceUnit,
    );
    if (picked == null || !mounted) return;
    setState(() => _priceUnit = picked);
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: from ? (_availableFrom ?? now) : (_availableTo ?? now),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _availableFrom = picked;
      } else {
        _availableTo = picked;
      }
      _errors.remove('availability');
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
    final category = _category!;
    final subcategory = _subcategory!;
    setState(() => _submitting = true);
    try {
      final photos = [
        ..._existingPhotos,
        ...await encodeListingPhotos(_photos),
      ];
      final details = <String, dynamic>{
        'subcategoryName': subcategory.name,
        if (_availableFrom != null) 'availableFrom': _fmtDate(_availableFrom!),
        if (_availableTo != null) 'availableTo': _fmtDate(_availableTo!),
        if (_timingController.text.trim().isNotEmpty)
          'timing': _timingController.text.trim(),
        if (_features.isNotEmpty) 'features': _features.toList(),
      };
      final body = <String, dynamic>{
        'type': 'service',
        'categoryId': category.id,
        'subcategoryId': subcategory.id,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'price': int.parse(_priceController.text.replaceAll(',', '')),
        'priceUnit': _priceUnit,
        'contactNumber':
            ref.read(sessionUserProfileProvider)?.phoneNumber ?? '',
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
              title: _isEdit ? 'Listing updated' : 'Service posted — now live',
              description: _isEdit
                  ? 'Your changes are live on the Services page.'
                  : 'Your service is listed under the category you chose. '
                        'Customers can find it on the Services page.',
            ),
            const SizedBox(height: OraSpacing.lg),
            OraButton(
              label: 'View my services',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
      if (!mounted) return;
      context.go(AppRoutes.vendorHome);
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

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
          const VendorHeroTop(),
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
                        icon: Icons.build_rounded,
                        label: 'Service Title',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      VendorTextField(
                        controller: _titleController,
                        hint: 'e.g. AC Installation & Repair Service',
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
                            'Describe your service in detail...\n(e.g. '
                            "what's included, service process, experience, "
                            'service area, etc.)',
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
                                  label: 'Service Category',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorPickerTile(
                                  placeholder: 'Select',
                                  value: _category?.name,
                                  error: _errors['category'] != null,
                                  onTap: _pickCategory,
                                ),
                                _errorText('category'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const VendorFieldLabel(
                                  icon: Icons.sell_rounded,
                                  label: 'Subcategory',
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                VendorPickerTile(
                                  placeholder: 'Select',
                                  value: _subcategory?.name,
                                  error: _errors['subcategory'] != null,
                                  onTap: _pickSubcategory,
                                ),
                                _errorText('subcategory'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.location_on_rounded,
                        label: 'Service Location / Coverage',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      VendorTextField(
                        controller: _locationController,
                        hint: 'Enter area, city or select on map',
                        textCapitalization: TextCapitalization.sentences,
                        suffixIcon: const Icon(
                          Icons.my_location_rounded,
                          size: 18,
                          color: OraColors.gold,
                        ),
                        error: _errors['location'] != null,
                        onChanged: (_) => _clearError('location'),
                      ),
                      _errorText('location'),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.payments_rounded,
                        label: 'Service Price',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                _errorText('price'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.xs),
                          Expanded(
                            flex: 4,
                            child: VendorPickerTile(
                              placeholder: 'Per Service',
                              value: _priceUnit,
                              onTap: _pickUnit,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.calendar_month_rounded,
                        label: 'Availability',
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                VendorPickerTile(
                                  placeholder: 'From',
                                  value: _formatDate(_availableFrom),
                                  error: _errors['availability'] != null,
                                  onTap: () => _pickDate(from: true),
                                ),
                                _errorText('availability'),
                              ],
                            ),
                          ),
                          const SizedBox(width: OraSpacing.xs),
                          Expanded(
                            child: VendorPickerTile(
                              placeholder: 'To',
                              value: _formatDate(_availableTo),
                              error: _errors['availability'] != null,
                              onTap: () => _pickDate(from: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.schedule_rounded,
                        label: 'Service Timing',
                        required: false,
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      VendorTextField(
                        controller: _timingController,
                        hint: 'e.g. 9:00 AM – 6:00 PM',
                      ),
                      const SizedBox(height: OraSpacing.md),
                      const VendorFieldLabel(
                        icon: Icons.check_box_rounded,
                        label: 'Service Features',
                        required: false,
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: OraSpacing.xs,
                        crossAxisSpacing: OraSpacing.xs,
                        childAspectRatio: 4.4,
                        children: [
                          for (final feature in _featureOptions)
                            VendorFeatureChip(
                              icon: feature.icon,
                              label: feature.label,
                              selected: _features.contains(feature.label),
                              onChanged: (selected) => setState(() {
                                if (selected) {
                                  _features.add(feature.label);
                                } else {
                                  _features.remove(feature.label);
                                }
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      VendorFieldLabel(
                        icon: Icons.image_rounded,
                        label: 'Add Service Photos',
                        trailing: Text(
                          '${_photos.length + _existingPhotos.length}/$_maxPhotos Photos',
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: OraSpacing.xxs),
                      Text(
                        'Upload clear and high-quality images (min 1, max $_maxPhotos)',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      SizedBox(
                        height: 92,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _UploadPhotoTile(onTap: _addPhotos),
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
                              _PhotoThumb(
                                file: File(_photos[i].path),
                                onRemove: () =>
                                    setState(() => _photos.removeAt(i)),
                              ),
                              const SizedBox(width: OraSpacing.xs),
                            ],
                            if ((_photos.length + _existingPhotos.length) <
                                _maxPhotos)
                              _AddPhotoTile(onTap: _addPhotos),
                          ],
                        ),
                      ),
                      _errorText('photos'),
                      _errorText('submit'),
                      const SizedBox(height: OraSpacing.lg),
                      OraButton(
                        label: _isEdit ? 'Save changes' : 'Post Service',
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

String? _formatDate(DateTime? date) {
  if (date == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Dashed "Upload Photos" tile — first slot in the photo row.
class _UploadPhotoTile extends StatelessWidget {
  const _UploadPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: const CustomPaint(
          painter: _DashedBorderPainter(
            color: OraColors.gold,
            radius: OraRadius.input,
          ),
          child: SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 26,
                  color: OraColors.gold,
                ),
                SizedBox(height: OraSpacing.xxs),
                Text(
                  'Upload\nPhotos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: OraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small "+" tile shown after the last photo when more can be added.
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: onTap,
        child: const CustomPaint(
          painter: _DashedBorderPainter(
            color: OraColors.primaryMuted,
            radius: OraRadius.input,
          ),
          child: SizedBox(
            width: 92,
            child: Icon(
              Icons.add_photo_alternate_outlined,
              size: 24,
              color: OraColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OraRadius.input),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: OraColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: OraColors.onPhoto,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded dashed-stroke painter for the upload tiles.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.7),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end.toDouble()), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
