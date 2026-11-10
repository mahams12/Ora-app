import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../app/theme/widgets/ora_section_header.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../../super_app/presentation/widgets/service_coming_later_sheet.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../domain/rental_catalogue_search.dart';
import '../../../shared/demo/demo_listings.dart';
import '../../../shared/widgets/illustrated_category_card.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../../../shared/widgets/rental_listing_card.dart';
import 'rental_filter_sheet.dart';

class RentalHomeView extends ConsumerStatefulWidget {
  const RentalHomeView({super.key});

  @override
  ConsumerState<RentalHomeView> createState() => _RentalHomeViewState();
}

class _RentalHomeViewState extends ConsumerState<RentalHomeView> {
  String? _selectedCategoryId;
  String _query = '';
  RentalFilterState _filters = RentalFilterState();

  Future<void> _openFilters(List<RentalCategory> categories) async {
    final result = await showModalBottomSheet<RentalFilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RentalFilterSheet(
        initialValue: _filters,
        propertyTypes: categories.map((category) => category.name).toList(),
      ),
    );
    if (result != null && mounted) {
      String? selectedId;
      for (final category in categories) {
        if (category.name == result.propertyType) {
          selectedId = category.id;
          break;
        }
      }
      setState(() {
        _filters = result;
        _selectedCategoryId = selectedId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final catalogue = ref.watch(catalogueProvider);
    final demoEnabled = ref.watch(demoListingsEnabledProvider);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Rental')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.rental,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const MarketplaceEmptyState(
          title: 'Catalogue unavailable',
          message: 'Please try again later.',
        ),
        data: (data) {
          final categories = data.rental;
          final selectedCategories = _selectedCategoryId == null
              ? categories
              : categories
                    .where((category) => category.id == _selectedCategoryId)
                    .toList(growable: false);
          final nearCategory = selectedCategories.isEmpty
              ? null
              : selectedCategories.first;
          final nearYouListings = demoEnabled && nearCategory != null
              ? demoRentalListings(nearCategory).take(3).toList()
              : const <DemoRentalListing>[];
          final searchResults = _query.trim().isEmpty
              ? const <RentalSearchMatch>[]
              : RentalCatalogueSearch.search(categories, _query);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: CustomScrollView(
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _RentalHero(),
                          const SizedBox(height: OraSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: MarketplaceSearchField(
                                  hintText: 'Search homes, stays or spaces',
                                  onChanged: (value) =>
                                      setState(() => _query = value),
                                ),
                              ),
                              const SizedBox(width: OraSpacing.xs),
                              IconButton.filledTonal(
                                tooltip: 'Open filters',
                                onPressed: () => _openFilters(categories),
                                icon: const Icon(Icons.tune_rounded),
                              ),
                            ],
                          ),
                          if (_query.trim().isNotEmpty) ...[
                            const SizedBox(height: OraSpacing.xs),
                            Text(
                              'Search is performed locally. No verified '
                              'listings are available yet.',
                              style: OraTypography.caption(OraColors.textMuted),
                            ),
                          ],
                          const SizedBox(height: OraSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Categories',
                                  style: OraTypography.title(
                                    OraColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (_selectedCategoryId != null)
                                TextButton(
                                  onPressed: () => setState(
                                    () => _selectedCategoryId = null,
                                  ),
                                  child: const Text('Show all'),
                                ),
                            ],
                          ),
                          const SizedBox(height: OraSpacing.xs),
                          SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: categories.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: OraSpacing.xs),
                              itemBuilder: (context, index) {
                                final category = categories[index];
                                return ChoiceChip(
                                  label: Text(
                                    category.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  selected: _selectedCategoryId == category.id,
                                  onSelected: (selected) => setState(
                                    () => _selectedCategoryId = selected
                                        ? category.id
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_query.trim().isNotEmpty) ...[
                    if (searchResults.isEmpty)
                      const SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: OraSpacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: MarketplaceEmptyState(
                            title: 'No matching property types',
                            message:
                                'Try a different name or a related keyword.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final match = searchResults[index];
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: OraSpacing.xs,
                              ),
                              child: _RentalSearchTile(
                                match: match,
                                onTap: () => context.push(
                                  AppRoutes.rentalCategoryPath(
                                    match.category.id,
                                    subcategoryId: match.subcategory?.id,
                                  ),
                                ),
                              ),
                            );
                          }, childCount: searchResults.length),
                        ),
                      ),
                  ] else
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: OraSpacing.sm,
                              mainAxisSpacing: OraSpacing.sm,
                              childAspectRatio: 1.05,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final category = selectedCategories[index];
                          return LayoutBuilder(
                            builder: (context, constraints) =>
                                IllustratedCategoryCard(
                                  imageAsset:
                                      'assets/marketplace/${category.image}',
                                  title: category.name,
                                  countLine:
                                      '${category.subcategories.length} property types',
                                  badgeIcon: Icons.home_work_outlined,
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                  onTap: () => context.push(
                                    AppRoutes.rentalCategoryPath(category.id),
                                  ),
                                ),
                          );
                        }, childCount: selectedCategories.length),
                      ),
                    ),
                  if (demoEnabled && nearCategory != null)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        OraSpacing.lg,
                        0,
                        OraSpacing.sm,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(right: padding),
                              child: const OraSectionHeader(
                                title: 'Places near you',
                              ),
                            ),
                            const SizedBox(height: OraSpacing.sm),
                            SizedBox(
                              height: 212,
                              child: ListView.separated(
                                padding: EdgeInsets.only(right: padding),
                                scrollDirection: Axis.horizontal,
                                itemCount: nearYouListings.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: OraSpacing.sm),
                                itemBuilder: (context, index) {
                                  final listing = nearYouListings[index];
                                  return RentalListingCard(
                                    width: 300,
                                    height: 200,
                                    isSample: true,
                                    model: RentalListingCardModel(
                                      title: listing.title,
                                      location: listing.area,
                                      imageAsset: listing.imageAsset,
                                      rating: listing.rating,
                                      reviewCount: listing.reviewCount,
                                      priceLabel: listing.priceLabel,
                                      availability: listing.amenities.join(
                                        ' · ',
                                      ),
                                      amenities: listing.amenities,
                                      tag: listing.tag,
                                    ),
                                    onTap: () => showDemoBookingSheet(context),
                                    onBookmark: () =>
                                        showDemoBookingSheet(context),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.lg,
                      padding,
                      OraSpacing.xs,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: OutlinedButton.icon(
                        onPressed: () => unawaited(
                          showServiceComingLaterSheet(
                            context,
                            'List your property',
                          ),
                        ),
                        icon: const Icon(Icons.add_home_work_outlined),
                        label: const Text('List your property'),
                      ),
                    ),
                  ),
                  if (_filters.cityArea.isNotEmpty ||
                      _filters.minimumPrice.isNotEmpty ||
                      _filters.maximumPrice.isNotEmpty ||
                      _filters.amenities.isNotEmpty ||
                      _filters.dateRange != null)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          'Filters are saved only on this device.',
                          style: OraTypography.caption(OraColors.textMuted),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: OraSpacing.xxl),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RentalHero extends StatelessWidget {
  const _RentalHero();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(OraRadius.card),
      child: SizedBox(
        height: 168,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/marketplace/modules/rental.webp',
              cacheWidth: 720,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Color(0x000A1025), Color(0xE60A1025)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(OraSpacing.md),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find a space that fits',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.headline(Colors.white),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    'Homes, stays and spaces — all in one place.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.body(Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RentalSearchTile extends StatelessWidget {
  const _RentalSearchTile({required this.match, required this.onTap});

  final RentalSearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = match.name;
    final subtitle = match.subcategory == null
        ? match.category.blurb
        : match.category.name;
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      onTap: onTap,
      child: Card(
        color: OraColors.surfaceElevated,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(OraRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(OraSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.home_work_outlined, color: OraColors.teal),
                const SizedBox(width: OraSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.bodyEmphasis(
                          OraColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: OraColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
