import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/notifications/ride_fcm_nudge.dart';

RemoteMessage _msg(Map<String, dynamic> data) =>
    RemoteMessage(data: Map<String, dynamic>.from(data));

void main() {
  test('parses rideId + eventId + type', () {
    final n = RideFcmNudge.tryParse(_msg({
      'type': 'ride_update',
      'rideId': 'ride-1',
      'eventId': 'evt-9',
    }))!;
    expect(n.rideId, 'ride-1');
    expect(n.eventId, 'evt-9');
    expect(n.type, 'ride_update');
  });

  test('parses the canonical backend RIDE_UPDATE contract', () {
    // Exact payload emitted by the ride-state FCM projector:
    // {type: RIDE_UPDATE, rideId, eventId} — identifiers only.
    final n = RideFcmNudge.tryParse(_msg({
      'type': 'RIDE_UPDATE',
      'rideId': 'ride-42',
      'eventId': 'ev-42',
    }))!;
    expect(n.rideId, 'ride-42');
    expect(n.eventId, 'ev-42');
    expect(n.type, 'RIDE_UPDATE');
  });

  test('accepts snake_case ride_id / delivery_event_id', () {
    final n = RideFcmNudge.tryParse(_msg({
      'ride_id': 'ride-2',
      'delivery_event_id': 'evt-10',
    }))!;
    expect(n.rideId, 'ride-2');
    expect(n.eventId, 'evt-10');
  });

  test('missing/empty rideId yields null', () {
    expect(RideFcmNudge.tryParse(_msg({'eventId': 'e'})), isNull);
    expect(RideFcmNudge.tryParse(_msg({'rideId': '  '})), isNull);
    expect(RideFcmNudge.tryParse(_msg({})), isNull);
  });

  test('id-less nudge still parses (consumer debounce handles dupes)', () {
    final n = RideFcmNudge.tryParse(_msg({'rideId': 'ride-3'}))!;
    expect(n.eventId, isNull);
    expect(n.type, isNull);
  });

  test('extra/unknown fields are ignored', () {
    final n = RideFcmNudge.tryParse(_msg({
      'rideId': 'ride-4',
      'fareMinor': '26000',
      'state': 'RIDE_STARTED', // never trusted — parse only
    }))!;
    expect(n.rideId, 'ride-4');
  });
}
