import '../../../core/constants/app_constants.dart';

sealed class RideTypeAction {
  const RideTypeAction();
}

class RideCategoryAction extends RideTypeAction {
  const RideCategoryAction(this.categoryId);

  final String categoryId;
}

class RideIntercityAction extends RideTypeAction {
  const RideIntercityAction();
}

class RideComingLaterAction extends RideTypeAction {
  const RideComingLaterAction();
}

class RideTypeOption {
  const RideTypeOption({
    required this.id,
    required this.name,
    required this.blurb,
    required this.image,
    required this.action,
  });

  final String id;
  final String name;
  final String blurb;
  final String image;
  final RideTypeAction action;

  bool get comingLater => action is RideComingLaterAction;
}

const kRideTypeCatalogue = <RideTypeOption>[
  RideTypeOption(
    id: 'bike',
    name: 'Bike',
    blurb: 'Quick city rides',
    image: 'assets/marketplace/rides/bike.webp',
    action: RideCategoryAction('zip'),
  ),
  RideTypeOption(
    id: 'rickshaw',
    name: 'Rickshaw',
    blurb: 'Three wheels for everyday journeys',
    image: 'assets/marketplace/rides/rickshaw.webp',
    action: RideCategoryAction('trio'),
  ),
  RideTypeOption(
    id: 'mini',
    name: 'Mini',
    blurb: 'Compact city travel',
    image: AppConstants.serviceCityRidesAsset,
    action: RideCategoryAction('easy'),
  ),
  RideTypeOption(
    id: 'ac',
    name: 'AC',
    blurb: 'Comfortable rides',
    image: 'assets/marketplace/rides/ac.webp',
    action: RideCategoryAction('breeze'),
  ),
  RideTypeOption(
    id: 'premium',
    name: 'Premium',
    blurb: 'A refined ride experience',
    image: 'assets/marketplace/rides/premium.webp',
    action: RideCategoryAction('premium'),
  ),
  RideTypeOption(
    id: 'business_class',
    name: 'Business class',
    blurb: 'Extra room for the ride',
    image: 'assets/marketplace/rides/business_class.webp',
    action: RideCategoryAction('executive'),
  ),
  RideTypeOption(
    id: 'for_events',
    name: 'For Events',
    blurb: 'Event transport options',
    image: 'assets/marketplace/rides/for_events.webp',
    action: RideComingLaterAction(),
  ),
  RideTypeOption(
    id: 'six_seater',
    name: '6-Seater',
    blurb: 'Group travel option',
    image: 'assets/marketplace/rides/six_seater.webp',
    action: RideComingLaterAction(),
  ),
  RideTypeOption(
    id: 'seven_seater',
    name: '7-Seater',
    blurb: 'Room for a larger group',
    image: 'assets/marketplace/rides/seven_seater.webp',
    action: RideComingLaterAction(),
  ),
  RideTypeOption(
    id: 'van',
    name: 'Van',
    blurb: 'Space for a group',
    image: 'assets/marketplace/rides/van.webp',
    action: RideComingLaterAction(),
  ),
  RideTypeOption(
    id: 'bus',
    name: 'Bus',
    blurb: 'Group transport option',
    image: 'assets/marketplace/rides/bus.webp',
    action: RideComingLaterAction(),
  ),
  RideTypeOption(
    id: 'intercity',
    name: 'Intercity',
    blurb: 'Travel between cities',
    image: AppConstants.serviceIntercityAsset,
    action: RideIntercityAction(),
  ),
  RideTypeOption(
    id: 'women_only',
    name: 'Women-Only Rides',
    blurb: 'A dedicated ride option',
    image: 'assets/marketplace/rides/women_only.webp',
    action: RideComingLaterAction(),
  ),
];
