#!/usr/bin/env python3
"""Minimal local /v1 stub so a profile-mode APK can reach the map UI while
staging is down (GCP billing disabled, 2026-10-19). NOT a staging substitute —
it answers only what the frame-timing flow needs:

  GET  /v1/auth/me            -> 200 passenger profile (profileComplete=true)
  GET  /v1/rides              -> 200 [] (history list stays empty)
  GET  /v1/rides/open         -> 200 {"rides": []} (driver feed empty)
  POST /v1/pricing/estimate   -> 503 (estimate unavailable; compose map still renders)
  anything else               -> 404 JSON

Run:  python3 stub_auth_api.py 8081          # passenger mode (default)
      python3 stub_auth_api.py 8081 driver   # approved-driver + completed rides
Then: adb -s <serial> reverse tcp:8081 tcp:8081
Build: --dart-define=ORA_API_BASE_URL=http://127.0.0.1:8081/v1
        --dart-define=ORA_ALLOW_HTTP_API=true
"""
import json
import sys
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer


DRIVER_MODE = len(sys.argv) > 2 and sys.argv[2] == "driver"

ME = {
    "uid": "stub-passenger-profile",
    "phoneNumber": "+923012345678",
    "displayName": "Perf Stub",
    "role": "passenger",
    "isActive": True,
    "banned": False,
    "profileComplete": True,
}

DRIVER_ME = {
    "uid": "stub-driver-profile",
    "phoneNumber": "+923099998877",
    "displayName": "Stub Driver",
    "role": "driver",
    "driverStatus": "approved",
    "isActive": True,
    "banned": False,
    "profileComplete": True,
}


def _ride(ride_id, fare_minor, completed_at):
    return {
        "rideId": ride_id,
        "passengerId": "stub-passenger-1",
        "assignedDriverId": "stub-driver-profile",
        "state": "RIDE_CLOSED",
        "version": 7,
        "requestVersion": 3,
        "category": "easy",
        "serviceType": "ride",
        "pickup": {"lat": 33.5651, "lng": 73.1569,
                   "address": "F-8 Markaz, Islamabad"},
        "destination": {"lat": 33.6844, "lng": 73.0479,
                        "address": "G-11 Markaz, Islamabad"},
        "pricingSnapshotId": "snap-stub",
        "recommendedFareMinor": 60000,
        "passengerOfferMinor": fare_minor or 55000,
        "agreedFareMinor": fare_minor,
        "agreedFareCurrency": "PKR" if fare_minor is not None else None,
        "agreedOfferId": "offer-stub",
        "paymentMethod": "CASH",
        "passengerCount": 1,
        "expiresAt": "2026-03-01T11:30:00.000Z",
        "assignedAt": "2026-03-01T10:15:00.000Z",
        "arrivedAt": "2026-03-01T10:30:00.000Z",
        "startedAt": "2026-03-01T10:40:00.000Z",
        "completedAt": completed_at,
        "closedAt": completed_at,
        "cancelledBy": None,
        "cancellationReason": None,
        "createdAt": "2026-03-01T10:00:00.000Z",
        "updatedAt": completed_at,
    }


def _iso(hours_ago):
    t = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
    return t.strftime("%Y-%m-%dT%H:%M:%S.000Z")


DRIVER_RIDES = {
    "rides": [
        # Completed ~2h ago → lands in Today + Last-7-days tiles.
        _ride("stub-ride-1", 65000, _iso(2)),
        # Completed ~3 days ago → Last-7-days only.
        _ride("stub-ride-2", 48000, _iso(72)),
        # Completed ~40 days ago, no recorded fare → missing-fare note.
        _ride("stub-ride-3", None, _iso(960)),
    ],
    "nextCursor": None,
}


class H(BaseHTTPRequestHandler):
    def _json(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, fmt, *args):
        print(f"[stub] {self.command} {self.path} -> handled", file=sys.stderr)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/v1/auth/me":
            self._json(200, DRIVER_ME if DRIVER_MODE else ME)
        elif p in ("/v1/rides", "/v1/rides/history"):
            # API envelope: {data: {rides, nextCursor}} — flat {rides} is NOT
            # unwrapped by the client and would surface as a parse failure.
            body = DRIVER_RIDES if DRIVER_MODE else {"rides": []}
            self._json(200, {"data": body})
        elif p == "/v1/rides/open":
            self._json(200, {"data": {"rides": []}})
        else:
            self._json(404, {"error": {"code": "STUB_NOT_FOUND", "message": p}})

    def do_POST(self):
        p = self.path.split("?")[0]
        if p == "/v1/auth/register":
            self._json(200, DRIVER_ME if DRIVER_MODE else ME)
        elif p == "/v1/pricing/estimate":
            self._json(503, {"error": {"code": "STUB_UNAVAILABLE",
                                       "message": "estimate stubbed"}})
        else:
            self._json(404, {"error": {"code": "STUB_NOT_FOUND", "message": p}})

    do_PATCH = do_POST
    do_DELETE = do_POST


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    print(f"stub auth api on 127.0.0.1:{port}", file=sys.stderr)
    HTTPServer(("127.0.0.1", port), H).serve_forever()
