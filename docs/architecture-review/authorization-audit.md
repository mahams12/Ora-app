# ORA — Authorization Audit

## Authorization Rule

Authorization is the combination of:
- authenticated caller identity
- caller role
- resource ownership / relationship
- current resource state
- requested action

## Resource Checks Required

| Operation | Caller | Resource Relation Required | State Check |
|---|---|---|---|
| Create ride | passenger | self | no active conflicting ride |
| Read ride | passenger | `ride.passengerId == caller` | none |
| Read assigned ride | driver | `ride.assignedDriverId == caller` | none |
| Accept ride | driver | driver approved, eligible, notified or server-eligible | ride assignable |
| Cancel ride | passenger | passenger owns ride | state cancellable |
| Cancel ride | driver | driver assigned to ride | state cancellable |
| Start ride | driver | driver assigned to ride | current state `DRIVER_ARRIVED` |
| Complete ride | driver | driver assigned to ride | current state `RIDE_STARTED` |
| Read wallet | user | own wallet only | none |
| Credit wallet | server/admin only | n/a | business rules |
| Trigger payout | driver | own payout account | sufficient settled balance |

## Adversarial Findings

### RTDB overexposure
Current RTDB rules are too broad in some docs. `tripLocations` and `rideSignals` must not be readable by arbitrary authenticated users.

### Driver accept authorization gap
The docs say “driver can accept” but must also require:
- approved driver
- approved active vehicle
- category eligibility
- no active ride
- location freshness
- request still assignable

### Passenger selection authorization gap
Passenger selecting an offer must be restricted to:
- own ride only
- existing `PENDING` offer for that ride
- offer not expired / stale
- ride still `SEARCHING` or `OFFERS_AVAILABLE`
- driver still eligible

Drivers cannot call select. Drivers create offers only if dispatched/eligible.

### Financial authorization gap
No client may:
- mark payment captured
- mark payout completed
- mutate wallet balance
- post a refund

## Recommendation

Every mutation handler should perform a single authorization function with explicit inputs:

`authorize(actor, action, resource, currentState, context) -> allow/deny`
