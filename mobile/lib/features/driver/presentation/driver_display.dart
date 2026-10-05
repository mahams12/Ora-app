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
      'You are assigned to this trip. Mark en route when you leave for pickup.',
    'DRIVER_EN_ROUTE' =>
      'You are heading to the passenger. Mark arrived when you reach pickup.',
    'DRIVER_ARRIVED' =>
      'You are at pickup. Start the ride when the passenger is onboard.',
    'RIDE_STARTED' =>
      'Trip in progress. Complete the ride when you arrive at the destination.',
    'RIDE_COMPLETED' =>
      'Trip finished. Close the ride when you are ready, then you can rate it.',
    'RIDE_CLOSED' => 'This ride is closed. You can leave a rating if you like.',
    'CANCELLED' => 'This ride was cancelled.',
    'EXPIRED' => 'This request expired before it was assigned.',
    'NO_SHOW' => 'A no-show was recorded for this ride.',
    'SEARCHING' || 'OFFERS_AVAILABLE' =>
      'This request is still waiting for a driver — it is not your assigned job.',
    _ => 'This ride status could not be shown clearly. Pull to refresh.',
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
