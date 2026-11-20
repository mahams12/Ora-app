/// What the assigned-ride screen may say about the local GPS watch.
enum DriverLocationStatusKind {
  hidden,
  acquiring,
  ready,
  poorAccuracy,
  servicesDisabled,
  permissionNeeded,
  permissionBlocked,
  unavailable,
}

/// User-facing copy. No coordinates, error codes, or infrastructure names.
String? driverLocationStatusLabel(DriverLocationStatusKind kind) {
  return switch (kind) {
    DriverLocationStatusKind.hidden => null,
    DriverLocationStatusKind.acquiring => 'Getting your location…',
    DriverLocationStatusKind.ready => 'Location is ready',
    DriverLocationStatusKind.poorAccuracy => 'Location accuracy is low',
    DriverLocationStatusKind.servicesDisabled => 'Location is turned off',
    DriverLocationStatusKind.permissionNeeded => 'Location permission is needed',
    DriverLocationStatusKind.permissionBlocked =>
      'Location permission is needed',
    DriverLocationStatusKind.unavailable =>
      'Location is temporarily unavailable',
  };
}

/// Optional recovery CTA. Never names APIs, enums, or platform error codes.
String? driverLocationStatusActionLabel(DriverLocationStatusKind kind) {
  return switch (kind) {
    DriverLocationStatusKind.permissionNeeded => 'Allow location',
    DriverLocationStatusKind.permissionBlocked => 'Open settings',
    DriverLocationStatusKind.servicesDisabled => 'Turn on location',
    DriverLocationStatusKind.unavailable => 'Try again',
    _ => null,
  };
}
