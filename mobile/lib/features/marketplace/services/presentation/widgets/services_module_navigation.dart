import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../../app/router/routes.dart';

enum ServicesNavigationDestination { explore, bookings, saved }

class ServicesModuleNavigation extends StatelessWidget {
  const ServicesModuleNavigation({required this.selected, super.key});

  final ServicesNavigationDestination selected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (index) {
        final destination = ServicesNavigationDestination.values[index];
        context.go(switch (destination) {
          ServicesNavigationDestination.explore => AppRoutes.services,
          ServicesNavigationDestination.bookings => AppRoutes.servicesBookings,
          ServicesNavigationDestination.saved => AppRoutes.servicesSaved,
        });
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore_rounded),
          label: 'Explore',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note_rounded),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border_rounded),
          selectedIcon: Icon(Icons.bookmark_rounded),
          label: 'Saved',
        ),
      ],
    );
  }
}
