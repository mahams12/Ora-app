import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../app/theme/ora_colors.dart';
import '../../../../app/theme/ora_elevation.dart';
import '../../../../app/theme/ora_radius.dart';
import '../../../../app/theme/ora_spacing.dart';
import '../../../../app/theme/ora_typography.dart';
import '../../../../app/theme/widgets/widgets.dart';
import '../../../marketplace/catalogue/catalogue_models.dart';
import '../../../marketplace/catalogue/catalogue_provider.dart';
import '../../../marketplace/data/marketplace_models.dart';
import '../../../marketplace/data/marketplace_providers.dart';
import '../../../marketplace/presentation/widgets/vendor_listing_manage_card.dart';
import '../widgets/vendor_ui_kit.dart';

/// Vendor home — "ORA Services Vendor" landing for an approved service
/// provider: hero card, real listings from /v1/vendor/listings and the
/// Post a Service entry that publishes onto the passenger Services pages.
class VendorHomeView extends ConsumerWidget {
  const VendorHomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(myListingsProvider('service'));
    final bookings = ref.watch(
      bookingsProvider(const BookingsQuery(role: 'vendor', type: 'service')),
    );
    final catalogue = ref.watch(catalogueProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFFFBEFE4),
      body: Column(
        children: [
          VendorHeroTop(
            onBannerTap: () => context.push(AppRoutes.vendorPostService),
          ),
          Expanded(
            child: RefreshIndicator(
              color: OraColors.gold,
              onRefresh: () async => ref.invalidate(myListingsProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  OraSpacing.md,
                  0,
                  OraSpacing.md,
                  40,
                ),
                children: [
                  const SizedBox(height: OraSpacing.sm),
                  _VendorStatRow(
                    listings: listings.value ?? const [],
                    bookingCount: bookings.value?.length ?? 0,
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OraButton(
                          label: 'Bookings',
                          trailingIcon: Icons.inbox_rounded,
                          variant: OraButtonVariant.secondary,
                          onPressed: () =>
                              context.push(AppRoutes.vendorBookingsService),
                        ),
                      ),
                      const SizedBox(width: OraSpacing.sm),
                      Expanded(
                        child: OraButton(
                          label: 'Wallet',
                          trailingIcon:
                              Icons.account_balance_wallet_rounded,
                          variant: OraButtonVariant.secondary,
                          onPressed: () =>
                              context.push(AppRoutes.vendorWallet),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'My Services',
                          style: OraTypography.title(OraColors.textPrimary),
                        ),
                      ),
                      Text(
                        '${listings.value?.length ?? 0} listings',
                        style: OraTypography.caption(OraColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  listings.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(OraSpacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => _ErrorCard(
                      onRetry: () => ref.invalidate(myListingsProvider),
                    ),
                    data: (items) => items.isEmpty
                        ? const _NoServicesCard()
                        : Column(
                            children: [
                              for (final listing in items) ...[
                                VendorListingManageCard(
                                  listing: listing,
                                  icon: Icons.handyman_rounded,
                                  subtitle: [
                                    catalogue
                                        ?.serviceCategory(listing.categoryId)
                                        ?.name,
                                    _subcategoryName(
                                      catalogue?.serviceCategory(
                                        listing.categoryId,
                                      ),
                                      listing.subcategoryId,
                                    ),
                                  ].whereType<String>().join(' · '),
                                  onEdit: (l) => context.push(
                                    AppRoutes.vendorPostService,
                                    extra: l,
                                  ),
                                ),
                                const SizedBox(height: OraSpacing.sm),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: OraSpacing.sm),
                  OraButton(
                    label: 'Post a Service',
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: () => context.push(AppRoutes.vendorPostService),
                  ),
                  const SizedBox(height: OraSpacing.lg),
                  const _PassengerSwitchCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String? _subcategoryName(
    ServiceCategory? category,
    String subcategoryId,
  ) {
    if (category == null) return null;
    for (final sub in category.subcategories) {
      if (sub.id == subcategoryId) return sub.name;
    }
    return null;
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(OraSpacing.lg),
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Column(
        children: [
          Text(
            'Could not load your listings',
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.sm),
          OraButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _VendorStatRow extends StatelessWidget {
  const _VendorStatRow({required this.listings, required this.bookingCount});

  final List<MarketplaceListing> listings;
  final int bookingCount;

  @override
  Widget build(BuildContext context) {
    final photos = listings.fold<int>(
      0,
      (sum, listing) => sum + listing.photos.length,
    );
    final live = listings.where((l) => l.isPublished).length;
    return Row(
      children: [
        Expanded(
          child: _VendorStatCard(
            icon: Icons.storefront_rounded,
            value: '$live',
            label: 'Live services',
          ),
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: _VendorStatCard(
            icon: Icons.photo_library_rounded,
            value: '$photos',
            label: 'Photos',
          ),
        ),
        const SizedBox(width: OraSpacing.sm),
        Expanded(
          child: _VendorStatCard(
            icon: Icons.event_note_rounded,
            value: '$bookingCount',
            label: 'Requests',
          ),
        ),
      ],
    );
  }
}

class _VendorStatCard extends StatelessWidget {
  const _VendorStatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: OraSpacing.sm,
        vertical: OraSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: OraColors.gold),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            value,
            style: OraTypography.title(
              OraColors.textPrimary,
            ).copyWith(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoServicesCard extends StatelessWidget {
  const _NoServicesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(OraSpacing.lg),
      decoration: BoxDecoration(
        color: OraColors.onPhoto,
        borderRadius: BorderRadius.circular(OraRadius.card),
        boxShadow: OraElevation.cardShadow,
      ),
      child: Column(
        children: [
          const Icon(Icons.handyman_outlined, size: 34, color: OraColors.gold),
          const SizedBox(height: OraSpacing.xs),
          Text(
            'No services posted yet',
            style: OraTypography.bodyEmphasis(OraColors.textPrimary),
          ),
          const SizedBox(height: OraSpacing.xxs),
          Text(
            'Post your first service — it shows up on the '
            'passenger Services page in the category you pick.',
            textAlign: TextAlign.center,
            style: OraTypography.caption(OraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Bright-orange "Switch to Passenger" card — same affordance as driver
/// home so vendor mode always has a way back.
class _PassengerSwitchCard extends StatelessWidget {
  const _PassengerSwitchCard();

  @override
  Widget build(BuildContext context) {
    return OraTapScale(
      child: GestureDetector(
        onTap: () => context.go(AppRoutes.home),
        child: Container(
          padding: const EdgeInsets.all(OraSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(OraRadius.card),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF9A3E), OraColors.goldSharp],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59FF6A0D),
                blurRadius: 16,
                offset: Offset(0, 6),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: OraColors.primaryForeground.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: OraColors.primaryForeground,
                ),
              ),
              const SizedBox(width: OraSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch to Passenger',
                      style: OraTypography.bodyEmphasis(
                        OraColors.primaryForeground,
                      ),
                    ),
                    Text(
                      'Book a ride with the same account',
                      style: OraTypography.caption(OraColors.primaryForeground),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.swap_horiz_rounded,
                color: OraColors.primaryForeground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
