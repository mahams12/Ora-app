import type { VendorType } from '../types';

export const MARKETPLACE_LISTINGS = 'marketplaceListings';
export const MARKETPLACE_BOOKINGS = 'marketplaceBookings';

/** Listing type maps 1:1 onto the vendor application role, so every write
 * can be gated by `vendorApplications.{type}.status === 'approved'`. */
export const LISTING_TYPES: readonly VendorType[] = [
  'cargo',
  'rental',
  'service',
];

export const LISTING_STATUSES = [
  'draft',
  'published',
  'paused',
  'deleted',
] as const;
export type ListingStatus = (typeof LISTING_STATUSES)[number];

export const BOOKING_STATUSES = [
  'requested',
  'quoted',
  'confirmed',
  'in_progress',
  'completed',
  'rejected',
  'cancelled',
] as const;
export type BookingStatus = (typeof BOOKING_STATUSES)[number];

/** Statuses that still occupy the listing / keep the customer engaged. */
export const ACTIVE_BOOKING_STATUSES: readonly BookingStatus[] = [
  'requested',
  'quoted',
  'confirmed',
  'in_progress',
];

export interface MarketplaceListing {
  listingId: string;
  vendorId: string;
  vendorName: string;
  type: VendorType;
  categoryId: string;
  /** Service/rental subcategory or logistics vehicleType id. */
  subcategoryId: string;
  title: string;
  description: string;
  /** Whole-rupee price (no payment integration — display/quote basis only). */
  price: number;
  priceUnit: string;
  location: string;
  /** Per-type dynamic fields (amenities, capacity, availability…). */
  details: Record<string, unknown>;
  /** Data-URL photos, bounded count + total bytes. */
  photos: string[];
  contactNumber: string;
  status: ListingStatus;
  createdAt: string;
  updatedAt: string;
  publishedAt?: string;
  version: number;
}

export interface BookingStatusEvent {
  status: BookingStatus;
  at: string;
  by: string;
  note?: string;
}

export interface MarketplaceBooking {
  bookingId: string;
  listingId: string;
  listingTitle: string;
  type: VendorType;
  vendorId: string;
  customerId: string;
  customerName: string;
  status: BookingStatus;
  /** Customer-submitted request payload (contact + per-type details). */
  request: Record<string, unknown>;
  quote?: { amount: number; note?: string; sentAt: string };
  /** Wallet commission charged at vendor-confirmed completion. */
  commission?: {
    points: number;
    amountMinor: number;
    grossMinor: number;
    bps: number;
    ledgerEntryId: string;
  };
  statusHistory: BookingStatusEvent[];
  createdAt: string;
  updatedAt: string;
  version: number;
}

export class MarketplaceError extends Error {
  constructor(
    public readonly code: string,
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = 'MarketplaceError';
  }
}
