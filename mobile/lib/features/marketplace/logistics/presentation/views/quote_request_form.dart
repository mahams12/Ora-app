import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_button.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';

class QuoteRequestForm extends ConsumerStatefulWidget {
  const QuoteRequestForm({
    required this.categoryId,
    required this.typeId,
    super.key,
  });

  final String categoryId;
  final String typeId;

  @override
  ConsumerState<QuoteRequestForm> createState() => _QuoteRequestFormState();
}

class _QuoteRequestFormState extends ConsumerState<QuoteRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _pickup = TextEditingController();
  final _destination = TextEditingController();
  final _cargo = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _instructions = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _stops = <TextEditingController>[];
  final _handlingOptions = const [
    'Fragile',
    'Refrigerated',
    'Hazardous',
    'Oversized',
    'Livestock',
    'High value',
  ];
  final _selectedHandling = <String>{};
  DateTime? _date;
  TimeOfDay? _time;
  String? _selectedTypeId;
  bool _loadingAssistance = false;

  @override
  void initState() {
    super.initState();
    _selectedTypeId = widget.typeId;
    final profile = ref.read(sessionUserProfileProvider);
    _contactName.text = profile?.displayName ?? '';
    _contactPhone.text = profile?.phoneNumber ?? '';
  }

  @override
  void dispose() {
    _pickup.dispose();
    _destination.dispose();
    _cargo.dispose();
    _weight.dispose();
    _length.dispose();
    _width.dispose();
    _height.dispose();
    _quantity.dispose();
    _instructions.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (value != null) setState(() => _time = value);
  }

  void _addStop() {
    if (_stops.length >= 3) return;
    setState(() => _stops.add(TextEditingController()));
  }

  void _removeStop(int index) {
    setState(() {
      _stops.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Request a quotation')),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const MarketplaceEmptyState(title: 'Catalogue unavailable'),
        data: (data) {
          final category = data.logisticsCategory(widget.categoryId);
          if (category == null || category.types.isEmpty) {
            return const MarketplaceEmptyState(title: 'Vehicle type not found');
          }
          final selectedTypeId =
              category.types.any((type) => type.id == _selectedTypeId)
              ? _selectedTypeId
              : category.types.first.id;
          final selectedType = category.types.firstWhere(
            (type) => type.id == selectedTypeId,
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        OraSpacing.md,
                        padding,
                        OraSpacing.xl,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              selectedType.name,
                              style: OraTypography.headline(
                                OraColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: OraSpacing.xs),
                            Text(
                              'A quote request form is being prepared. '
                              'No information is sent.',
                              style: OraTypography.body(
                                OraColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OraSpacing.lg),
                            _sectionTitle('Route'),
                            _field(
                              controller: _pickup,
                              label: 'Pickup address',
                              validator: _required(
                                'Pickup address is required',
                              ),
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            for (
                              var index = 0;
                              index < _stops.length;
                              index++
                            ) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _field(
                                      controller: _stops[index],
                                      label: 'Optional stop ${index + 1}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove stop ${index + 1}',
                                    onPressed: () => _removeStop(index),
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: OraSpacing.sm),
                            ],
                            if (_stops.length < 3)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _addStop,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Add optional stop'),
                                ),
                              ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _destination,
                              label: 'Destination address',
                              validator: _required(
                                'Destination address is required',
                              ),
                            ),
                            const SizedBox(height: OraSpacing.lg),
                            _sectionTitle('Date and time'),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickDate,
                                  icon: const Icon(Icons.calendar_today),
                                  label: Text(
                                    _date == null
                                        ? 'Choose date'
                                        : MaterialLocalizations.of(
                                            context,
                                          ).formatMediumDate(_date!),
                                  ),
                                ),
                                const SizedBox(height: OraSpacing.xs),
                                OutlinedButton.icon(
                                  onPressed: _pickTime,
                                  icon: const Icon(Icons.schedule),
                                  label: Text(
                                    _time?.format(context) ?? 'Choose time',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: OraSpacing.lg),
                            _sectionTitle('Vehicle and cargo'),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: selectedTypeId,
                              decoration: const InputDecoration(
                                labelText: 'Vehicle type',
                              ),
                              items: [
                                for (final type in category.types)
                                  DropdownMenuItem(
                                    value: type.id,
                                    child: Text(
                                      type.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedTypeId = value),
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _cargo,
                              label: 'Cargo description',
                              validator: _required(
                                'Cargo description is required',
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _weight,
                              label: 'Weight (kg)',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            Text(
                              'Dimensions (cm)',
                              style: OraTypography.label(
                                OraColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OraSpacing.xs),
                            _field(
                              controller: _length,
                              label: 'Length',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _width,
                              label: 'Width',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _height,
                              label: 'Height',
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _quantity,
                              label: 'Quantity',
                              keyboardType: TextInputType.number,
                              validator: _required('Quantity is required'),
                            ),
                            const SizedBox(height: OraSpacing.xs),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Loading / unloading assistance',
                              ),
                              value: _loadingAssistance,
                              onChanged: (value) =>
                                  setState(() => _loadingAssistance = value),
                            ),
                            const SizedBox(height: OraSpacing.md),
                            Text(
                              'Special handling',
                              style: OraTypography.label(
                                OraColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OraSpacing.xs),
                            Wrap(
                              spacing: OraSpacing.xs,
                              runSpacing: OraSpacing.xs,
                              children: [
                                for (final option in _handlingOptions)
                                  FilterChip(
                                    label: Text(option),
                                    selected: _selectedHandling.contains(
                                      option,
                                    ),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedHandling.add(option);
                                        } else {
                                          _selectedHandling.remove(option);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: OraSpacing.md),
                            const Card(
                              color: OraColors.navyElevated,
                              child: ListTile(
                                enabled: false,
                                leading: Icon(Icons.photo_camera_outlined),
                                title: Text('Cargo photos'),
                                subtitle: Text(
                                  'Photo uploads available after setup',
                                ),
                              ),
                            ),
                            const SizedBox(height: OraSpacing.md),
                            _sectionTitle('Additional instructions'),
                            _field(
                              controller: _instructions,
                              label: 'Additional instructions (optional)',
                              maxLines: 3,
                            ),
                            const SizedBox(height: OraSpacing.lg),
                            _sectionTitle('Contact details'),
                            _field(
                              controller: _contactName,
                              label: 'Contact name',
                              validator: _required('Contact name is required'),
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            _field(
                              controller: _contactPhone,
                              label: 'Contact phone',
                              keyboardType: TextInputType.phone,
                              validator: _required('Contact phone is required'),
                            ),
                            const SizedBox(height: OraSpacing.lg),
                            _sectionTitle('Fare estimate'),
                            Container(
                              padding: const EdgeInsets.all(OraSpacing.md),
                              decoration: BoxDecoration(
                                color: OraColors.navyElevated,
                                borderRadius: BorderRadius.circular(
                                  OraRadius.card,
                                ),
                              ),
                              child: Text(
                                'A quotation from verified operators will '
                                'appear here once requests are enabled.',
                                style: OraTypography.body(
                                  OraColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          padding,
          OraSpacing.xs,
          padding,
          OraSpacing.xs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Nothing will be sent',
              style: OraTypography.caption(OraColors.textMuted),
            ),
            const SizedBox(height: OraSpacing.xs),
            const OraButton(
              label: 'Quotation requests open soon',
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }

  String? Function(String?) _required(String message) => (value) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  };

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: OraSpacing.sm),
    child: Text(title, style: OraTypography.title(OraColors.textPrimary)),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }
}
