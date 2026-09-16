export type AvailabilityState = 'offline' | 'online';

export class DriverDomainError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'DriverDomainError';
  }
}

export interface DriverAvailabilitySnapshot {
  driverId: string;
  availabilityState: AvailabilityState;
}
