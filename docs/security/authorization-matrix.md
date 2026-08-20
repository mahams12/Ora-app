# ORA — Authorization Matrix

## Actor Roles

| Role | Description |
|---|---|
| `anonymous` | No auth token |
| `passenger` | Authenticated user (default) |
| `driver_pending` | Auth'd; driverStatus = pending |
| `driver` | Auth'd; driverStatus = approved |
| `admin` | Auth'd; role = admin custom claim |
| `server` | Cloud Run with Admin SDK (bypasses all rules) |

## Firestore Operations

| Collection | Operation | anonymous | passenger | driver | admin |
|---|---|---|---|---|---|
| users/{own} | read | ✗ | ✓ | ✓ | ✓ |
| users/{other} | read | ✗ | ✗ | ✗ | ✓ |
| users/{own} | write (non-sensitive) | ✗ | ✓ | ✓ | ✓ |
| users/{own}.role | write | ✗ | ✗ | ✗ | ✓ |
| drivers/{own} | read | ✗ | ✓ | ✓ | ✓ |
| drivers/{other} | read | ✗ | limited* | limited* | ✓ |
| drivers/{own} | write | ✗ | ✗ | limited† | ✓ |
| vehicles/{own} | read/write | ✗ | ✗ | ✓ | ✓ |
| driverDocuments/{own} | read | ✗ | ✗ | ✓ | ✓ |
| driverDocuments/{own} | write | ✗ | ✗ | ✗ (server only) | ✓ |
| rides/{own} | read | ✗ | ✓ | ✓** | ✓ |
| rides/{other} | read | ✗ | ✗ | ✗ | ✓ |
| rides | write | ✗ | ✗ | ✗ | ✗ (server only) |
| rideOffers/{own ride} | read | ✗ | ✓ | ✓ (own offers) | ✓ |
| rideOffers | write | ✗ | ✗ | ✗ | ✗ (server only) |
| feePolicies | read | ✗ | ✓ | ✓ | ✓ |
| feePolicies | write | ✗ | ✗ | ✗ | ✓ |
| pricingRules | read | ✗ | ✓ | ✓ | ✓ |
| pricingRules | write | ✗ | ✗ | ✗ | ✓ |
| walletAccounts/{own} | read | ✗ | ✓ | ✓ | ✓ |
| walletAccounts | write | ✗ | ✗ | ✗ | ✗ (server only) |
| ledgerEntries | write | ✗ | ✗ | ✗ | ✗ (server only) |
| paymentIntents/{own} | read | ✗ | ✓ | limited | ✓ |
| paymentIntents | write | ✗ | ✗ | ✗ | ✗ (server only) |
| transactions/{own} | read | ✗ | ✓ | ✓ | ✓ |
| safetyEvents | read | ✗ | ✗ | ✗ | ✓ |
| savedPlaces/{own} | read/write | ✗ | ✓ | ✓ | ✓ |
| referrals | read | ✗ | ✓ | ✓ | ✓ |
| hotZones | read | ✗ | ✓ | ✓ | ✓ |
| serviceAreas | read | ✗ | ✓ | ✓ | ✓ |

*limited: public fields only (displayName, rating, vehicleInfo)  
**driver can read own assigned rides only  
†driver can update homeCity, preferredCategories

## API Endpoint Authorization

| Endpoint | passenger | driver | admin |
|---|---|---|---|
| POST /rides | ✓ | ✗ | ✓ |
| GET /rides/{id} (own) | ✓ | ✓ | ✓ |
| POST /rides/{id}/offers | ✗ | ✓ (eligible/dispatched only) | ✓ |
| POST /rides/{id}/offers/{offerId}/select | ✓ (own ride) | ✗ | ✓ |
| POST /rides/{id}/offers/{offerId}/withdraw | ✗ | ✓ (own offer) | ✓ |
| POST /rides/{id}/cancel | ✓ | ✓ | ✓ |
| POST /rides/{id}/status (driver states) | ✗ | ✓ (assigned) | ✓ |
| POST /pricing/estimate | ✓ | ✓ | ✓ |
| POST /drivers/go-online | ✗ | ✓ (approved) | ✓ |
| POST /location/update | ✗ | ✓ (approved) | ✓ |
| POST /payments/initiate | ✓ | ✗ | ✓ |
| POST /payments/cash-collected | ✗ | ✓ (assigned) | ✓ |
| POST /payments/refund | ✗ | ✗ | ✓ |
| GET /admin/* | ✗ | ✗ | ✓ |
| POST /admin/force-transition | ✗ | ✗ | ✓ |
| POST /admin/suspend-driver | ✗ | ✗ | ✓ |

## RTDB Authorization

| Path | anonymous | passenger | driver | admin |
|---|---|---|---|---|
| driverPresence/{own} | ✗ | ✗ | read/write | ✓ |
| driverPresence/{other} | ✗ | ✗ | ✗ | ✓ |
| tripLocations/{rideId} | ✗ | read (own active ride only) | read (assigned active ride only) | ✓ |
| rideSignals/{rideId} | ✗ | read (own active ride only) | read (assigned/pending ride only) | ✓ |
| rideRequests/{driverId} | ✗ | ✗ | read (own) | ✓ |
| All writes (except own presence) | ✗ | ✗ | ✗ | ✓ (server) |

## Sensitive Operations (Require Re-authentication)

- Change phone number
- Delete account
- Withdraw large wallet amount (> Rs 5,000)
- Access emergency contact data
