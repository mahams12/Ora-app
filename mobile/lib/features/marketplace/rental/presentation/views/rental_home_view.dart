import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import 'rental_filter_sheet.dart';

class RentalHomeView extends StatefulWidget {
  const RentalHomeView({super.key});

  @override
  State<RentalHomeView> createState() => _RentalHomeViewState();
}

class _RentalHomeViewState extends State<RentalHomeView> {
  static const _propertyTypes = [
    'Apartment',
    'House',
    'Room',
    'Villa',
    'Guest house',
    'Hotel',
  ];

  String? _selectedPropertyType;
  String _query = '';
  RentalFilterState _filters = RentalFilterState();

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<RentalFilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RentalFilterSheet(initialValue: _filters),
    );
    if (result != null && mounted) {
      setState(() {
        _filters = result;
        _selectedPropertyType = result.propertyType;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Rental')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding,
              OraSpacing.md,
              padding,
              OraSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MarketplaceSearchField(
                          hintText: 'Search by name or location',
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: OraSpacing.xs),
                      IconButton.filledTonal(
                        tooltip: 'Open filters',
                        onPressed: _openFilters,
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                  if (_query.trim().isNotEmpty) ...[
                    const SizedBox(height: OraSpacing.xs),
                    Text(
                      'Search stays on this device. No listings are available.',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                  ],
                  const SizedBox(height: OraSpacing.lg),
                  Text(
                    'Property type',
                    style: OraTypography.title(OraColors.textPrimary),
                  ),
                  const SizedBox(height: OraSpacing.xs),
                  Wrap(
                    spacing: OraSpacing.xs,
                    runSpacing: OraSpacing.xs,
                    children: [
                      for (final type in _propertyTypes)
                        ChoiceChip(
                          label: Text(type),
                          selected: _selectedPropertyType == type,
                          onSelected: (selected) {
                            setState(
                              () => _selectedPropertyType = selected
                                  ? type
                                  : null,
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  if (_filters.cityArea.isNotEmpty ||
                      _filters.minimumPrice.isNotEmpty ||
                      _filters.maximumPrice.isNotEmpty ||
                      _filters.amenities.isNotEmpty ||
                      _filters.dateRange != null)
                    Text(
                      'Filters are stored locally on this device.',
                      style: OraTypography.caption(OraColors.textMuted),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            sliver: const SliverToBoxAdapter(
              child: MarketplaceEmptyState(
                title:
                    'No properties listed yet — verified hosts are coming '
                    'soon',
                message:
                    'Nothing is available to book until verified hosts join.',
                icon: Icons.home_work_outlined,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: OraSpacing.xxl)),
        ],
      ),
    );
  }
}
