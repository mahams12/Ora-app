import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';

enum RentalSortOrder { relevance, price, rating }

class RentalFilterState {
  RentalFilterState({
    this.cityArea = '',
    this.propertyType,
    this.minimumPrice = '',
    this.maximumPrice = '',
    this.dateRange,
    this.guests = 1,
    Set<String> amenities = const {},
    this.minimumRating,
    this.sortOrder = RentalSortOrder.relevance,
  }) : amenities = Set.unmodifiable(amenities);

  final String cityArea;
  final String? propertyType;
  final String minimumPrice;
  final String maximumPrice;
  final DateTimeRange? dateRange;
  final int guests;
  final Set<String> amenities;
  final int? minimumRating;
  final RentalSortOrder sortOrder;
}

class RentalFilterSheet extends StatefulWidget {
  const RentalFilterSheet({required this.initialValue, super.key});

  final RentalFilterState initialValue;

  @override
  State<RentalFilterSheet> createState() => _RentalFilterSheetState();
}

class _RentalFilterSheetState extends State<RentalFilterSheet> {
  static const _propertyTypes = [
    'Apartment',
    'House',
    'Room',
    'Villa',
    'Guest house',
    'Hotel',
  ];
  static const _amenityOptions = [
    'Wi-Fi',
    'Kitchen',
    'Parking',
    'Air conditioning',
    'Pet-friendly',
    'Washer',
  ];

  late final TextEditingController _cityArea = TextEditingController(
    text: widget.initialValue.cityArea,
  );
  late final TextEditingController _minimumPrice = TextEditingController(
    text: widget.initialValue.minimumPrice,
  );
  late final TextEditingController _maximumPrice = TextEditingController(
    text: widget.initialValue.maximumPrice,
  );
  late String? _propertyType = widget.initialValue.propertyType;
  late DateTimeRange? _dateRange = widget.initialValue.dateRange;
  late int _guests = widget.initialValue.guests;
  late final Set<String> _amenities = {...widget.initialValue.amenities};
  late int? _minimumRating = widget.initialValue.minimumRating;
  late RentalSortOrder _sortOrder = widget.initialValue.sortOrder;

  @override
  void dispose() {
    _cityArea.dispose();
    _minimumPrice.dispose();
    _maximumPrice.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final today = DateTime.now();
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 3),
      initialDateRange: _dateRange,
    );
    if (value != null) setState(() => _dateRange = value);
  }

  void _apply() {
    Navigator.of(context).pop(
      RentalFilterState(
        cityArea: _cityArea.text.trim(),
        propertyType: _propertyType,
        minimumPrice: _minimumPrice.text.trim(),
        maximumPrice: _maximumPrice.text.trim(),
        dateRange: _dateRange,
        guests: _guests,
        amenities: _amenities,
        minimumRating: _minimumRating,
        sortOrder: _sortOrder,
      ),
    );
  }

  void _clear() {
    setState(() {
      _cityArea.clear();
      _minimumPrice.clear();
      _maximumPrice.clear();
      _propertyType = null;
      _dateRange = null;
      _guests = 1;
      _amenities.clear();
      _minimumRating = null;
      _sortOrder = RentalSortOrder.relevance;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Material(
        color: OraColors.navy,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            OraSpacing.md,
            OraSpacing.md,
            OraSpacing.md,
            OraSpacing.md + bottomInset,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filters',
                        style: OraTypography.headline(OraColors.textPrimary),
                      ),
                    ),
                    TextButton(onPressed: _clear, child: const Text('Clear')),
                    IconButton(
                      tooltip: 'Close filters',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: [
                      _filterLabel('City / area'),
                      TextField(
                        controller: _cityArea,
                        decoration: const InputDecoration(
                          hintText: 'Enter a city or area',
                        ),
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Property type'),
                      Wrap(
                        spacing: OraSpacing.xs,
                        runSpacing: OraSpacing.xs,
                        children: [
                          for (final type in _propertyTypes)
                            ChoiceChip(
                              label: Text(type),
                              selected: _propertyType == type,
                              onSelected: (selected) => setState(
                                () => _propertyType = selected ? type : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Price range'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _minimumPrice,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Minimum price',
                              ),
                            ),
                          ),
                          const SizedBox(width: OraSpacing.sm),
                          Expanded(
                            child: TextField(
                              controller: _maximumPrice,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Maximum price',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Dates'),
                      OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          _dateRange == null
                              ? 'Choose dates'
                              : '${MaterialLocalizations.of(context).formatMediumDate(_dateRange!.start)} – '
                                    '${MaterialLocalizations.of(context).formatMediumDate(_dateRange!.end)}',
                        ),
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Guests'),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Remove one guest',
                            onPressed: _guests > 1
                                ? () => setState(() => _guests--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$_guests guests',
                            style: OraTypography.body(OraColors.textPrimary),
                          ),
                          IconButton(
                            tooltip: 'Add one guest',
                            onPressed: () => setState(() => _guests++),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Amenities'),
                      Wrap(
                        spacing: OraSpacing.xs,
                        runSpacing: OraSpacing.xs,
                        children: [
                          for (final amenity in _amenityOptions)
                            FilterChip(
                              label: Text(amenity),
                              selected: _amenities.contains(amenity),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _amenities.add(amenity);
                                  } else {
                                    _amenities.remove(amenity);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Minimum rating'),
                      Wrap(
                        spacing: OraSpacing.xs,
                        children: [
                          for (final rating in [null, 3, 4, 5])
                            ChoiceChip(
                              label: Text(rating == null ? 'Any' : '$rating+'),
                              selected: _minimumRating == rating,
                              onSelected: (_) =>
                                  setState(() => _minimumRating = rating),
                            ),
                        ],
                      ),
                      const SizedBox(height: OraSpacing.md),
                      _filterLabel('Sort by'),
                      DropdownButtonFormField<RentalSortOrder>(
                        initialValue: _sortOrder,
                        items: const [
                          DropdownMenuItem(
                            value: RentalSortOrder.relevance,
                            child: Text('Relevance'),
                          ),
                          DropdownMenuItem(
                            value: RentalSortOrder.price,
                            child: Text('Price'),
                          ),
                          DropdownMenuItem(
                            value: RentalSortOrder.rating,
                            child: Text('Rating'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _sortOrder = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OraSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _apply,
                    child: const Text('Apply filters'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: OraSpacing.xs),
    child: Text(text, style: OraTypography.label(OraColors.textSecondary)),
  );
}
