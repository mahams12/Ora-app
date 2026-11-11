class DriverOnboardingApplication {
  const DriverOnboardingApplication({
    required this.fullName,
    required this.cnicNumber,
    required this.homeCity,
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.vehicleCategory,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.vehicleColor,
    required this.plateNumber,
  });

  final String fullName;
  final String cnicNumber;
  final String homeCity;
  final String licenseNumber;
  final String licenseExpiry;
  final String vehicleCategory;
  final String vehicleMake;
  final String vehicleModel;
  final int vehicleYear;
  final String vehicleColor;
  final String plateNumber;
}

class DriverOnboardingResult {
  const DriverOnboardingResult({
    required this.driverStatus,
    required this.approved,
  });

  final String driverStatus;
  final bool approved;
}
