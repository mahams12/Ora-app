import 'package:flutter/material.dart';

/// Visual ride category catalog for compose UI.
///
/// [id] is sent as the server `category` string when create is enabled.
/// Fares are never fabricated here — display uses [priceLabel] only.
class RideCategoryOption {
  const RideCategoryOption({
    required this.id,
    required this.name,
    required this.blurb,
    required this.icon,
  });

  final String id;
  final String name;
  final String blurb;
  final IconData icon;

  /// Honest label until a pricing snapshot exists.
  String get priceLabel => 'Price TBD';
}

const kRideCategoryOptions = <RideCategoryOption>[
  RideCategoryOption(
    id: 'zip',
    name: 'Zip',
    blurb: 'Bike',
    icon: Icons.two_wheeler_rounded,
  ),
  RideCategoryOption(
    id: 'trio',
    name: 'Trio',
    blurb: 'Rickshaw',
    icon: Icons.airport_shuttle_rounded,
  ),
  RideCategoryOption(
    id: 'easy',
    name: 'Easy',
    blurb: 'Compact',
    icon: Icons.directions_car_rounded,
  ),
  RideCategoryOption(
    id: 'breeze',
    name: 'Breeze',
    blurb: 'AC comfort',
    icon: Icons.ac_unit_rounded,
  ),
  RideCategoryOption(
    id: 'executive',
    name: 'Executive',
    blurb: 'Larger',
    icon: Icons.airport_shuttle_outlined,
  ),
  RideCategoryOption(
    id: 'premium',
    name: 'Premium',
    blurb: 'Luxury feel',
    icon: Icons.workspace_premium_rounded,
  ),
];

RideCategoryOption? rideCategoryById(String? id) {
  if (id == null) return null;
  for (final c in kRideCategoryOptions) {
    if (c.id == id) return c;
  }
  return null;
}
