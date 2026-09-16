/// Driver-facing job status copy — driven only by server ride state.
library;

String driverJobTitle(String state) {
  return switch (state.toUpperCase()) {
    'DRIVER_ASSIGNED' => 'Assigned — head to pickup',
    'DRIVER_EN_ROUTE' => 'En route to passenger',
    'DRIVER_ARRIVED' => 'Arrived at pickup',
    'RIDE_STARTED' => 'Ride in progress',
    'RIDE_COMPLETED' => 'Ride completed',
    'RIDE_CLOSED' => 'Ride closed',
    'CANCELLED' => 'Ride cancelled',
    'EXPIRED' => 'Request expired',
    'NO_SHOW' => 'No-show recorded',
    'SEARCHING' || 'OFFERS_AVAILABLE' => 'Open request (not assigned)',
    _ => 'Job update',
  };
}

String driverJobMessage(String state) {
  return switch (state.toUpperCase()) {
    'DRIVER_ASSIGNED' =>
      'You are assigned on Ora\'s servers. Mark en route when you leave. '
          'Live maps and ETA are not in this build.',
    'DRIVER_EN_ROUTE' =>
      'Server shows you en route. Mark arrived when you reach pickup — Ora '
          'does not invent GPS or ETA here.',
    'DRIVER_ARRIVED' =>
      'Server recorded your arrival. Start the ride when the passenger is '
          'onboard. Wait clocks use real arrivedAt when present.',
    'RIDE_STARTED' =>
      'Trip is in progress on the server. Complete the ride when you finish. '
          'Route tracking is not in this build.',
    'RIDE_COMPLETED' =>
      'Trip completed on the server. Closing the ride is the next step. '
          'You can rate after completion or close.',
    'RIDE_CLOSED' =>
      'This ride aggregate is closed. You can submit a stars-only rating '
          'from the rate screen.',
    'CANCELLED' => 'This ride was cancelled on Ora\'s servers.',
    'EXPIRED' => 'This request expired on the server.',
    'NO_SHOW' =>
      'The server recorded a no-show. No fees or penalties are invented here.',
    'SEARCHING' || 'OFFERS_AVAILABLE' =>
      'This ride is still in the offers marketplace — not an assigned job. '
          'Use Direct offer only with a known rideId.',
    _ =>
      'Ora received an unrecognized ride state. Showing server data safely.',
  };
}

bool isDriverJobPollingState(String state) {
  final s = state.toUpperCase();
  return s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED' ||
      s == 'RIDE_COMPLETED';
}

bool isDriverJobTerminalState(String state) {
  final s = state.toUpperCase();
  return s == 'CANCELLED' ||
      s == 'EXPIRED' ||
      s == 'NO_SHOW' ||
      s == 'RIDE_CLOSED';
}

bool driverCanEnRoute(String state) =>
    state.toUpperCase() == 'DRIVER_ASSIGNED';

bool driverCanArrive(String state) =>
    state.toUpperCase() == 'DRIVER_EN_ROUTE';

bool driverCanStart(String state) =>
    state.toUpperCase() == 'DRIVER_ARRIVED';

bool driverCanComplete(String state) =>
    state.toUpperCase() == 'RIDE_STARTED';

/// Driver may cancel post-assign through RIDE_STARTED (server-enforced).
bool driverCanCancel(String state) {
  final s = state.toUpperCase();
  return s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED';
}

bool driverCanClose(String state) =>
    state.toUpperCase() == 'RIDE_COMPLETED';

String? driverPrimaryActionLabel(String state) {
  return switch (state.toUpperCase()) {
    'DRIVER_ASSIGNED' => 'Mark en route',
    'DRIVER_EN_ROUTE' => 'Mark arrived',
    'DRIVER_ARRIVED' => 'Start ride',
    'RIDE_STARTED' => 'Complete ride',
    _ => null,
  };
}
