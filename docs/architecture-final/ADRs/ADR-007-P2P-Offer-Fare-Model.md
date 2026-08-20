# ADR-007: P2P Offered-Fare Marketplace Model

## Status
Accepted / Locked.

## Decision
Ora is a P2P offered-fare marketplace (inDrive-style behavior):
recommended fare is guidance;
passenger sets passenger offer;
drivers accept or counter with offers;
passenger selects one offer;
server assigns atomically exactly one driver.

## Consequences
- Avoids first-accept-wins assignment races.
- Maintains distinct fields for `recommendedFare`, `passengerOffer`, `driver offers`, and `agreedFare`.

