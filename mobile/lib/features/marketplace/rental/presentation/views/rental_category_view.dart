import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';
import '../../../../../app/theme/ora_colors.dart';
import '../../../../../app/theme/ora_radius.dart';
import '../../../../../app/theme/ora_spacing.dart';
import '../../../../../app/theme/ora_typography.dart';
import '../../../../../core/utils/responsive.dart';
import '../../../../super_app/recent/recent_activity.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../../../catalogue/catalogue_models.dart';
import '../../../catalogue/catalogue_provider.dart';
import '../../../shared/demo/demo_listings.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../../../shared/widgets/rental_listing_card.dart';

class RentalCategoryView extends ConsumerStatefulWidget {
  const RentalCategoryView({
    required this.categoryId,
    this.subcategoryId,
    super.key,
  });

  final String categoryId;
  final String? subcategoryId;

  @override
  ConsumerState<RentalCategoryView> createState() => _RentalCategoryViewState();
}

class _RentalCategoryViewState extends ConsumerState<RentalCategoryView> {
  String _query = '';
  String? _recordedActivityKey;

  @override
  void didUpdateWidget(covariant RentalCategoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId ||
        oldWidget.subcategoryId != widget.subcategoryId) {
      _query = '';
      _recordedActivityKey = null;
    }
  }

  void _recordActivity(
    RentalCategory category,
    RentalSubcategory? subcategory,
  ) {
    final activityKey = '${category.id}:${subcategory?.id ?? ''}';
    if (_recordedActivityKey == activityKey) return;
    _recordedActivityKey = activityKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(recentActivityProvider.notifier)
          .record(
            RecentActivity(
              kind: RecentActivityKind.rental,
              id: activityKey,
              title: subcategory?.name ?? category.name,
              subtitle: 'Rental',
              imageAsset:
                  'assets/marketplace/${subcategory?.image ?? category.image}',
              route: AppRoutes.rentalCategoryPath(
                category.id,
                subcategoryId: subcategory?.id,
              ),
              atMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
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
          final category = data.rentalCategory(widget.categoryId);
          if (category == null) {
            return const MarketplaceEmptyState(title: 'Category not found');
          }
          RentalSubcategory? selectedSubcategory;
          for (final subcategory in category.subcategories) {
            if (subcategory.id == widget.subcategoryId) {
              selectedSubcategory = subcategory;
              break;
            }
          }
          if (widget.subcategoryId != null && selectedSubcategory == null) {
            return const MarketplaceEmptyState(
              title: 'Property type not found',
            );
          }
          _recordActivity(category, selectedSubcategory);
          final query = _query.trim().toLowerCase();
          final visibleSubcategories = category.subcategories
              .where((item) {
                if (query.isEmpty) return true;
                return '${item.name} ${item.keywords.join(' ')}'
                    .toLowerCase()
                    .contains(query);
              })
              .toList(growable: false);
          final List<DemoRentalListing> listings = demoEnabled
              ? demoRentalListings(category, subId: widget.subcategoryId)
                    .where((listing) {
                      if (query.isEmpty) return true;
                      var subcategoryName = '';
                      for (final item in category.subcategories) {
                        if (item.id == listing.subcategoryId) {
                          subcategoryName = item.name;
                          break;
                        }
                      }
                      return [
                        listing.title,
                        listing.area,
                        listing.amenities.join(' '),
                        subcategoryName,
                      ].join(' ').toLowerCase().contains(query);
                    })
                    .toList(growable: false)
              : const <DemoRentalListing>[];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.md,
                      padding,
                      OraSpacing.sm,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _RentalCategoryHero(category: category),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: MarketplaceSearchField(
                              hintText: 'Search stays and properties',
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            ),
                          ),
                          const SizedBox(width: OraSpacing.xs),
                          const Chip(
                            avatar: Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: OraColors.gold,
                            ),
                            label: Text('Lahore'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(
                          horizontal: padding,
                          vertical: OraSpacing.xs,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: category.subcategories.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: OraSpacing.xs),
                        itemBuilder: (context, index) {
                          final subcategory = index == 0
                              ? null
                              : category.subcategories[index - 1];
                          final selected = subcategory == null
                              ? selectedSubcategory == null
                              : selectedSubcategory?.id == subcategory.id;
                          return ChoiceChip(
                            label: Text(subcategory?.name ?? 'All'),
                            selected: selected,
                            onSelected: (_) => context.push(
                              AppRoutes.rentalCategoryPath(
                                category.id,
                                subcategoryId: subcategory?.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.xs,
                      padding,
                      OraSpacing.md,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Property types',
                        style: OraTypography.title(OraColors.textPrimary),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 142,
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: padding),
                        scrollDirection: Axis.horizontal,
                        itemCount: visibleSubcategories.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: OraSpacing.sm),
                        itemBuilder: (context, index) {
                          final subcategory = visibleSubcategories[index];
                          return SizedBox(
                            width: 176,
                            child: _RentalSubcategoryPhotoCard(
                              category: category,
                              subcategory: subcategory,
                              selected:
                                  selectedSubcategory?.id == subcategory.id,
                            ),
                          );
                        },
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
                      child: Text(
                        selectedSubcategory == null
                            ? 'Places near you'
                            : '${selectedSubcategory.name} near you',
                        style: OraTypography.title(OraColors.textPrimary),
                      ),
                    ),
                  ),
                  if (!demoEnabled)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: SliverToBoxAdapter(
                        child: MarketplaceEmptyState(
                          title: 'No verified listings yet',
                          message: selectedSubcategory == null
                              ? 'Verified properties will appear here when '
                                    'available.'
                              : 'There are no verified '
                                    '${selectedSubcategory.name.toLowerCase()} '
                                    'listings yet.',
                          icon: Icons.home_work_outlined,
                        ),
                      ),
                    )
                  else if (listings.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: const SliverToBoxAdapter(
                        child: MarketplaceEmptyState(
                          title: 'No sample properties match',
                          message: 'Try another property type or search.',
                          icon: Icons.search_off_rounded,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        OraSpacing.xs,
                        padding,
                        OraSpacing.xxl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final listing = listings[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: OraSpacing.sm,
                            ),
                            child: RentalListingCard(
                              model: RentalListingCardModel(
                                title: listing.title,
                                location: listing.area,
                                imageAsset: listing.imageAsset,
                                rating: listing.rating,
                                reviewCount: listing.reviewCount,
                                priceLabel: listing.priceLabel,
                                amenities: listing.amenities,
                                tag: listing.tag,
                              ),
                              width: double.infinity,
                              height: 190,
                              horizontal: true,
                              isSample: true,
                              onTap: () => showDemoBookingSheet(context),
                              onBookmark: () => showDemoBookingSheet(context),
                            ),
                          );
                        }, childCount: listings.length),
                      ),
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

class _RentalCategoryHero extends StatelessWidget {
  const _RentalCategoryHero({required this.category});

  final RentalCategory category;

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
              'assets/marketplace/${category.image}',
              cacheWidth: 960,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: OraColors.navyElevated),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [Color(0x0012182B), Color(0xE612182B)],
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
                    '${category.name} near me',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.headline(Colors.white),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    category.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(Colors.white70),
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

class _RentalSubcategoryPhotoCard extends StatelessWidget {
  const _RentalSubcategoryPhotoCard({
    required this.category,
    required this.subcategory,
    required this.selected,
  });

  final RentalCategory category;
  final RentalSubcategory subcategory;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return Semantics(
      button: true,
      label: subcategory.name,
      onTap: () => context.push(
        AppRoutes.rentalCategoryPath(
          category.id,
          subcategoryId: subcategory.id,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? OraColors.gold : OraColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            color: OraColors.navyElevated,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: () => context.push(
                AppRoutes.rentalCategoryPath(
                  category.id,
                  subcategoryId: subcategory.id,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/marketplace/${subcategory.image ?? category.image}',
                    cacheWidth: 440,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: OraColors.surfaceStrong),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xE6000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: OraSpacing.sm,
                    right: OraSpacing.sm,
                    bottom: OraSpacing.sm,
                    child: Text(
                      subcategory.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: OraTypography.bodyEmphasis(Colors.white),
                    ),
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
