import 'package:flutter/material.dart';

import '../../../../../app/theme/ora_colors.dart';
import '../../../shared/widgets/marketplace_empty_state.dart';
import '../../../../super_app/presentation/widgets/ora_module_bottom_bar.dart';
import '../widgets/services_module_navigation.dart';

class ServicesEmptyView extends StatelessWidget {
  const ServicesEmptyView({required this.destination, super.key});

  final ServicesNavigationDestination destination;

  @override
  Widget build(BuildContext context) {
    final isBookings = destination == ServicesNavigationDestination.bookings;
    return Scaffold(
      backgroundColor: OraColors.background,
      appBar: AppBar(title: Text(isBookings ? 'Bookings' : 'Saved')),
      bottomNavigationBar: const OraModuleBottomBar(
        selected: OraModuleDestination.services,
      ),
      body: MarketplaceEmptyState(
        title: isBookings ? 'No bookings yet' : 'No saved services yet',
        message: isBookings
            ? 'Bookings will appear once providers are onboarded.'
            : 'Verified services can be saved once providers are onboarded.',
        icon: isBookings
            ? Icons.event_note_outlined
            : Icons.bookmark_border_rounded,
      ),
    );
  }
}
