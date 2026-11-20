/// Driver-facing job status copy — driven only by server ride state.
library;

String driverJobTitle(String state, {bool courier = false}) {
  final s = state.toUpperCase();
  if (courier) {
    return switch (s) {
      'DRIVER_ASSIGNED' => 'Assigned — head to sender',
      'DRIVER_EN_ROUTE' => 'En route to pickup',
      'DRIVER_ARRIVED' => 'At pickup — collect parcel',
      'RIDE_STARTED' => 'Delivering parcel',
      'RIDE_COMPLETED' => 'Parcel delivered',
      'RIDE_CLOSED' => 'Delivery closed',
      'CANCELLED' => 'Booking cancelled',
      'EXPIRED' => 'Request expired',
      'NO_SHOW' => 'No-show recorded',
      'RETURNING' => 'Returning to sender',
      'RETURNED' => 'Parcel returned',
      'DELIVERY_FAILED' => 'Delivery failed',
      'SEARCHING' || 'OFFERS_AVAILABLE' => 'Open request (not assigned)',
      _ => 'Job update',
    };
  }
  return switch (s) {
    'DRIVER_ASSIGNED' => 'Assigned — head to pickup',
    'DRIVER_EN_ROUTE' => 'En route to passenger',
    'DRIVER_ARRIVED' => 'Arrived at pickup',
    'RIDE_STARTED' => 'Ride in progress',
    'RIDE_COMPLETED' => 'Ride completed',
    'RIDE_CLOSED' => 'Ride closed',
    'CANCELLED' => 'Ride cancelled',
    'EXPIRED' => 'Request expired',
    'NO_SHOW' => 'No-show recorded',
    'RETURNING' => 'Returning to sender',
    'RETURNED' => 'Parcel returned',
    'DELIVERY_FAILED' => 'Delivery failed',
    'SEARCHING' || 'OFFERS_AVAILABLE' => 'Open request (not assigned)',
    _ => 'Job update',
  };
}

String driverJobMessage(
  String state, {
  bool courier = false,
  bool courierV2 = false,
}) {
  final s = state.toUpperCase();
  if (courier) {
    if (courierV2) {
      return switch (s) {
        'DRIVER_ASSIGNED' =>
          'You are assigned to this delivery. Mark en route when you leave '
              'for the first stop.',
        'DRIVER_EN_ROUTE' =>
          'You are heading to the first stop. Mark arrived when you reach it.',
        'DRIVER_ARRIVED' =>
          'You are at the stop. Confirm it in the app — no code is needed.',
        'RIDE_STARTED' =>
          'Parcel onboard. Confirm each stop in the app as you complete it.',
        'RIDE_COMPLETED' =>
          'All stops done. Report the cash settlement, then close the job.',
        'RIDE_CLOSED' =>
          'This delivery is closed. You can leave a rating if you like.',
        'CANCELLED' => 'This booking was cancelled.',
        'EXPIRED' => 'This request expired before it was assigned.',
        'NO_SHOW' => 'A no-show was recorded for this delivery.',
        'RETURNING' =>
          'You are returning the parcel to the sender. Confirm the handover '
              'in the app — no code is needed.',
        'RETURNED' =>
          'The parcel was returned to the sender and confirmed.',
        'DELIVERY_FAILED' =>
          'A stop was marked failed. You can retry the delivery from the '
              'checklist.',
        'SEARCHING' || 'OFFERS_AVAILABLE' =>
          'This request is still waiting for a driver — it is not your '
              'assigned job.',
        _ => 'This ride status could not be shown clearly. Pull to refresh.',
      };
    }
    return switch (s) {
      'DRIVER_ASSIGNED' =>
        'You are assigned to this parcel delivery. Mark en route when you '
            'leave for the sender.',
      'DRIVER_EN_ROUTE' =>
        'You are heading to the sender. Mark arrived when you reach the '
            'pickup point.',
      'DRIVER_ARRIVED' =>
        'You are at pickup. Confirm pickup with the sender\'s one-time code '
            'before taking the parcel.',
      'RIDE_STARTED' =>
        'Parcel onboard. Confirm delivery with the receiver\'s one-time code '
            'at the destination.',
      'RIDE_COMPLETED' =>
        'Delivery confirmed. Close the job when ready, then you can rate it.',
      'RIDE_CLOSED' =>
        'This delivery is closed. You can leave a rating if you like.',
      'CANCELLED' => 'This booking was cancelled.',
      'EXPIRED' => 'This request expired before it was assigned.',
      'NO_SHOW' => 'A no-show was recorded for this delivery.',
      'RETURNING' =>
        'You are returning the parcel to the sender. The sender\'s return '
            'code confirms handover.',
      'RETURNED' =>
        'The parcel was returned to the sender and confirmed.',
      'DELIVERY_FAILED' =>
        'Delivery could not be completed. The reason is recorded.',
      'SEARCHING' || 'OFFERS_AVAILABLE' =>
        'This request is still waiting for a driver — it is not your '
            'assigned job.',
      _ => 'This ride status could not be shown clearly. Pull to refresh.',
    };
  }
  return switch (s) {
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
    'RETURNING' => 'A parcel is being returned to its sender.',
    'RETURNED' => 'The parcel was returned to the sender.',
    'DELIVERY_FAILED' => 'Delivery could not be completed.',
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
      s == 'RIDE_COMPLETED' ||
      s == 'RETURNING';
}

bool isDriverJobTerminalState(String state) {
  final s = state.toUpperCase();
  return s == 'CANCELLED' ||
      s == 'EXPIRED' ||
      s == 'NO_SHOW' ||
      s == 'RIDE_CLOSED' ||
      // Ora Courier terminal states.
      s == 'RETURNED' ||
      s == 'DELIVERY_FAILED';
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
/// For courier the server refuses cancellation once the parcel is picked up —
/// after pickup the driver must fail delivery or return the parcel instead.
bool driverCanCancel(String state, {bool courier = false}) {
  if (courier && state.toUpperCase() == 'RIDE_STARTED') return false;
  final s = state.toUpperCase();
  return s == 'DRIVER_ASSIGNED' ||
      s == 'DRIVER_EN_ROUTE' ||
      s == 'DRIVER_ARRIVED' ||
      s == 'RIDE_STARTED';
}

bool driverCanClose(String state, {bool courier = false}) {
  final s = state.toUpperCase();
  if (courier) {
    return s == 'RIDE_COMPLETED' || s == 'RETURNED';
  }
  return s == 'RIDE_COMPLETED';
}

/// Ora Courier — exception actions (server-authoritative).
/// Pickup-side failures are handled by cancelling with a reason before the
/// parcel is handed over; after pickup the only exits are delivery, a
/// failed-delivery record, retry, or return-to-sender.
bool driverCanFailDelivery(String state, {bool courier = false}) =>
    courier && state.toUpperCase() == 'RIDE_STARTED';

bool driverCanRetryDelivery(String state, {bool courier = false}) =>
    courier && state.toUpperCase() == 'DELIVERY_FAILED';

bool driverCanStartReturn(String state, {bool courier = false}) =>
    courier && state.toUpperCase() == 'DELIVERY_FAILED';

bool driverCanConfirmReturn(String state, {bool courier = false}) =>
    courier && state.toUpperCase() == 'RETURNING';

String? driverPrimaryActionLabel(String state, {bool courier = false}) {
  final s = state.toUpperCase();
  if (courier) {
    return switch (s) {
      'DRIVER_ASSIGNED' => 'Mark en route',
      'DRIVER_EN_ROUTE' => 'Mark arrived',
      'DRIVER_ARRIVED' => 'Confirm pickup (code)',
      'RIDE_STARTED' => 'Confirm delivery (code)',
      'RETURNING' => 'Confirm return (code)',
      _ => null,
    };
  }
  return switch (s) {
    'DRIVER_ASSIGNED' => 'Mark en route',
    'DRIVER_EN_ROUTE' => 'Mark arrived',
    'DRIVER_ARRIVED' => 'Start ride',
    'RIDE_STARTED' => 'Complete ride',
    _ => null,
  };
}

/// Failure reasons the driver may record — keep aligned with the backend
/// allow-list in rides/types.ts.
const kCourierFailureReasons = <String>[
  'RECEIVER_UNREACHABLE',
  'ADDRESS_INCORRECT',
  'RECEIVER_REJECTED',
  'PARCEL_DAMAGED',
  'OTHER',
];

String courierFailureReasonLabel(String reason) {
  return switch (reason) {
    'RECEIVER_UNREACHABLE' => 'Receiver unreachable',
    'ADDRESS_INCORRECT' => 'Incorrect address',
    'RECEIVER_REJECTED' => 'Receiver refused the parcel',
    'PARCEL_DAMAGED' => 'Parcel damaged',
    _ => 'Other',
  };
}
