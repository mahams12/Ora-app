import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/providers.dart';
import '../../../auth/presentation/view_models/session_user_profile.dart';
import '../../../ride/domain/entities/ride.dart';
import '../../../ride/domain/models/trip_location_latest.dart';
import '../../../ride/presentation/location/trip_location_session.dart';
import '../../../ride/presentation/widgets/active_ride_map.dart';
import '../location/driver_location_session.dart';
import '../../domain/location/driver_location_fix.dart';
import '../../domain/location/driver_location_lifecycle.dart';

/// Driver-side live job map — the same [ActiveRideMap] the passenger sees,
/// fed from the driver's own local GPS fixes instead of the RTDB listener
/// (the driver IS the source of truth; round-tripping RTDB would add latency
/// for zero accuracy gain).
class DriverJobMap extends ConsumerStatefulWidget {
  const DriverJobMap({
    super.key,
    required this.ride,
    this.height = 200,
  });

  final Ride ride;
  final double height;

  @override
  ConsumerState<DriverJobMap> createState() => _DriverJobMapState();
}

class _DriverJobMapState extends ConsumerState<DriverJobMap> {
  int _seq = 0;

  TripLocationLatest? _toLatest(DriverLocationFix fix, String driverId) {
    _seq += 1;
    return TripLocationLatest(
      lat: fix.latitude,
      lng: fix.longitude,
      accuracy: fix.accuracyMeters,
      heading: fix.headingDegrees ?? 0,
      speed: fix.speedKmh,
      ts: fix.timestamp.millisecondsSinceEpoch,
      acceptedAt: fix.timestamp.toUtc().toIso8601String(),
      driverId: driverId,
      locationSeq: _seq,
      locationStreamId: 'local-driver',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!driverLocationShouldWatch(widget.ride.state)) {
      return const SizedBox.shrink();
    }

    final fix = ref.watch(driverTripLatestFixProvider(widget.ride.rideId));
    final uid = ref.watch(
      sessionUserProfileProvider.select((p) => p?.uid ?? ''),
    );
    final policy = ref.watch(tripLocationFreshnessPolicyProvider);
    final now = ref.watch(tripLocationClockProvider)();
    final mapsEnabled = ref.watch(activeRideMapsEnabledProvider);

    final latest = (fix != null && uid.isNotEmpty) ? _toLatest(fix, uid) : null;
    final session = TripLocationSessionState(
      latest: latest,
      freshness: policy.classify(latest, now: now),
      isListening: latest != null,
    );

    return ActiveRideMap(
      ride: widget.ride,
      locationSession: session,
      height: widget.height,
      enableMaps: mapsEnabled,
      showRecenter: true,
    );
  }
}
