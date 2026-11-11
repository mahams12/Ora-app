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
import '../../../shared/demo/demo_logistics_operator_card.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../shared/widgets/marketplace_search_field.dart';
import '../../../shared/widgets/status_pill.dart';

class LogisticsCategoryView extends ConsumerStatefulWidget {
  const LogisticsCategoryView({required this.categoryId, super.key});

  final String categoryId;

  @override
  ConsumerState<LogisticsCategoryView> createState() =>
      _LogisticsCategoryViewState();
}

class _LogisticsCategoryViewState extends ConsumerState<LogisticsCategoryView> {
  String? _selectedTypeId;
  String _query = '';
  String? _recordedCategoryId;

  @override
  void didUpdateWidget(covariant LogisticsCategoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _selectedTypeId = null;
      _query = '';
      _recordedCategoryId = null;
    }
  }

  void _recordActivity(LogisticsCategory category) {
    if (_recordedCategoryId == category.id) return;
    _recordedCategoryId = category.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(recentActivityProvider.notifier)
          .record(
            RecentActivity(
              kind: RecentActivityKind.logistics,
              id: category.id,
              title: category.name,
              subtitle: 'Logistics',
              imageAsset: 'assets/marketplace/${category.image}',
              route: AppRoutes.logisticsCategoryPath(category.id),
              atMs: DateTime.now().millisecondsSinceEpoch,
            ),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalogue = ref.watch(catalogueProvider);
    final demoEnabled = ref.watch(demoListingsEnabledProvider);
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: const Text('Logistics')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.logistics,
      ),
      body: catalogue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const MarketplaceEmptyState(
          title: 'Catalogue unavailable',
          message: 'Please try again later.',
        ),
        data: (data) {
          final category = data.logisticsCategory(widget.categoryId);
          if (category == null) {
            return const MarketplaceEmptyState(title: 'Category not found');
          }
          _recordActivity(category);
          final query = _query.trim().toLowerCase();
          final List<DemoLogisticsOperator> operators = demoEnabled
              ? demoLogisticsOperators(category, typeId: _selectedTypeId)
                    .where((operator) {
                      if (query.isEmpty) return true;
                      return '${operator.name} ${operator.typeName} ${operator.area}'
                          .toLowerCase()
                          .contains(query);
                    })
                    .toList(growable: false)
              : const <DemoLogisticsOperator>[];
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
                      child: _LogisticsCategoryHero(category: category),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: MarketplaceSearchField(
                              hintText: 'Search operators',
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
                            label: Text('My location'),
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
                        itemCount: category.types.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: OraSpacing.xs),
                        itemBuilder: (context, index) {
                          final type = index == 0
                              ? null
                              : category.types[index - 1];
                          final selected = type == null
                              ? _selectedTypeId == null
                              : _selectedTypeId == type.id;
                          return ChoiceChip(
                            avatar: type == null
                                ? const Icon(
                                    Icons.grid_view_rounded,
                                    size: 18,
                                    color: OraColors.gold,
                                  )
                                : CircleAvatar(
                                    radius: 11,
                                    backgroundImage: AssetImage(
                                      'assets/marketplace/'
                                      '${type.image ?? category.image}',
                                    ),
                                  ),
                            label: Text(type?.name ?? 'All'),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedTypeId = type?.id),
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
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: OraSpacing.sm,
                            mainAxisSpacing: OraSpacing.sm,
                            childAspectRatio: 0.96,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final type = category.types[index];
                        return _VehicleTypePhotoCard(
                          key: ValueKey('logistics-type-${type.id}'),
                          category: category,
                          type: type,
                        );
                      }, childCount: category.types.length),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      OraSpacing.sm,
                      padding,
                      OraSpacing.xs,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Operators near you',
                              style: OraTypography.title(OraColors.textPrimary),
                            ),
                          ),
                          if (demoEnabled)
                            Text(
                              '${operators.length} sample',
                              style: OraTypography.caption(OraColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (!demoEnabled)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: const SliverToBoxAdapter(
                        child: MarketplaceEmptyState(
                          title: 'No verified operators yet',
                          message:
                              'Verified operators will appear here when '
                              'available.',
                          icon: Icons.local_shipping_outlined,
                        ),
                      ),
                    )
                  else if (operators.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      sliver: const SliverToBoxAdapter(
                        child: MarketplaceEmptyState(
                          title: 'No sample operators match',
                          message: 'Try another vehicle type or search.',
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
                          final operator = operators[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: OraSpacing.sm,
                            ),
                            child: DemoLogisticsOperatorCard(
                              operator: operator,
                              onSampleAction: () =>
                                  showDemoBookingSheet(context),
                            ),
                          );
                        }, childCount: operators.length),
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

class _LogisticsCategoryHero extends StatelessWidget {
  const _LogisticsCategoryHero({required this.category});

  final LogisticsCategory category;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return ClipRRect(
      borderRadius: radius,
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
                  colors: [Colors.transparent, OraColors.photoScrimStrong],
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
                    style: OraTypography.headline(OraColors.onPhoto),
                  ),
                  const SizedBox(height: OraSpacing.xxs),
                  Text(
                    category.blurb,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OraTypography.caption(OraColors.onPhotoMuted),
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

class _VehicleTypePhotoCard extends StatelessWidget {
  const _VehicleTypePhotoCard({
    required this.category,
    required this.type,
    super.key,
  });

  final LogisticsCategory category;
  final LogisticsVehicleType type;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(OraRadius.card);
    return Semantics(
      button: true,
      label: '${type.name}, quotation',
      onTap: () =>
          context.push(AppRoutes.logisticsQuotePath(category.id, type.id)),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: OraColors.navyElevated,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: () => context.push(
              AppRoutes.logisticsQuotePath(category.id, type.id),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/marketplace/${type.image ?? category.image}',
                  cacheWidth: 480,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: OraColors.surfaceStrong),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, OraColors.photoScrimStrong],
                    ),
                  ),
                ),
                Positioned(
                  left: OraSpacing.sm,
                  right: OraSpacing.sm,
                  bottom: OraSpacing.sm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        type.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OraTypography.bodyEmphasis(OraColors.onPhoto),
                      ),
                      const SizedBox(height: OraSpacing.xs),
                      const StatusPill.quotation(),
                    ],
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
