# ORA — Redis (Memorystore) Schema

## Key Namespacing

All keys follow: `{service}:{entity}:{identifier}`

## Key Reference

### GEO Index

```redis
# Driver location sorted set per city
KEY:    geo:drivers:{city}
TYPE:   Sorted Set (GEO)
CMD:    GEOADD geo:drivers:lahore {lng} {lat} {driverId}
TTL:    None (managed by sweeper)
SIZE:   ~50 bytes per driver
NOTES:  Removed by sweeper when driver goes stale; removed on go-offline
```

### Assignment Lock

```redis
KEY:    lock:ride:{rideId}
TYPE:   String
VALUE:  {driverId}
TTL:    30 seconds (EX 30)
CMD:    SET lock:ride:abc123 drv456 NX EX 30
NOTES:  Auto-expires if Cloud Run dies mid-transaction
        Released manually after successful assignment or failure
```

### Idempotency Cache Hint

```redis
KEY:    idempotency:{key}
TYPE:   String
VALUE:  JSON result or "PENDING"
TTL:    86400 seconds (24 hours)
CMD:    SET idempotency:{key} {json} EX 86400
NOTES:  Optional cache only; durable idempotency lives outside Redis
```

### Driver Presence Cache (Non-authoritative)

```redis
KEY:    driver:online:{driverId}
TYPE:   String
VALUE:  JSON { lastLocationTs, accuracy, city }
TTL:    30 seconds (refreshed on each GPS update)
CMD:    SET driver:online:drv456 '{"ts":1724035800000,"acc":8.5}' EX 30
NOTES:  Auto-expires = cached presence becomes stale
        Backup cache for matching; authoritative presence is RTDB
```

### Dispatched Drivers per Ride

```redis
KEY:    dispatch:notified:{rideId}
TYPE:   List
VALUE:  [driverId1, driverId2, ...]
TTL:    600 seconds (10 minutes)
CMD:    RPUSH dispatch:notified:abc123 drv1 drv2 drv3
NOTES:  Used for bulk RTDB cleanup after assignment
        Deleted after assignment cleanup completes
```

### Offer Deduplication

```redis
KEY:    offer:dedup:{rideId}:{driverId}
TYPE:   String
VALUE:  "1"
TTL:    300 seconds (5 minutes)
CMD:    SET offer:dedup:abc123:drv456 1 NX EX 300
NOTES:  Prevents driver from submitting multiple offers for same ride
        Returns nil if driver already offered
```

### Demand Counter per Zone

```redis
KEY:    demand:{city}:{zoneId}:bookings
TYPE:   String (counter)
VALUE:  Integer
TTL:    600 seconds (10 min rolling window)
CMD:    INCR demand:lahore:gulberg:bookings
        EXPIRE demand:lahore:gulberg:bookings 600
NOTES:  Approximate demand; rebuilt periodically from Firestore
```

### Rate Limit Counters

```redis
KEY:    rate:{userId}:ride_create
TYPE:   String (counter)
VALUE:  Integer count
TTL:    3600 seconds (1 hour)
CMD:    INCR rate:{userId}:ride_create
NOTES:  Max 20 ride creates per user per hour
        Enforced before processing POST /rides
```

## Memory Budget

| Key Pattern | Est. Count | Size per Entry | Total |
|---|---|---|---|
| geo:drivers:{city} | 5 cities × 500 drivers | 50 bytes | 125 KB |
| lock:ride:{rideId} | ~50 concurrent | 32 bytes | 2 KB |
| idempotency:{key} | ~10,000/day (24h retention) | 512 bytes | 5 MB |
| driver:online:{driverId} | 2,500 | 64 bytes | 160 KB |
| dispatch:notified:{rideId} | ~50 concurrent | 30 × 28 bytes | ~42 KB |
| offer:dedup:{rideId}:{driverId} | ~200 | 8 bytes | 2 KB |
| demand counters | 50 zones | 16 bytes | <1 KB |
| **Total** | | | **< 10 MB** |

Redis instance: Memorystore Basic tier, 1 GB (ample headroom). Upgrade to Standard HA before production.

## Redis Failure Handling

If Redis is unavailable:
1. GEO queries: dispatch becomes degraded; do not scan the full driver population as a pretend safe fallback
2. Assignment contention lock: proceed with Firestore transaction only (correctness preserved; contention may rise)
3. Idempotency: durable store remains available; Redis cache hint is skipped
4. Demand data: use last durable/configured value or temporarily reduce dynamic surge sensitivity

Log `REDIS_UNAVAILABLE` metric. Alert ops. Auto-retry connection with exponential backoff.
