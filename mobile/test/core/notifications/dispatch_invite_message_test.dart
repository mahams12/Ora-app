import 'package:flutter_test/flutter_test.dart';
import 'package:ora/core/notifications/dispatch_fcm_constants.dart';
import 'package:ora/core/notifications/dispatch_invite_message.dart';

void main() {
  test('parses DISPATCH_INVITE data payload', () {
    final msg = DispatchInviteMessage.tryParse({
      DispatchFcmConstants.dataKeyType: DispatchFcmConstants.messageType,
      DispatchFcmConstants.dataKeyRideId: 'ride-1',
      DispatchFcmConstants.dataKeyEventId: 'evt-1',
      DispatchFcmConstants.dataKeyWaveNumber: '1',
    });
    expect(msg?.rideId, 'ride-1');
    expect(msg?.eventId, 'evt-1');
    expect(msg?.waveNumber, '1');
  });

  test('rejects wrong type', () {
    expect(
      DispatchInviteMessage.tryParse({
        DispatchFcmConstants.dataKeyType: 'OTHER',
        DispatchFcmConstants.dataKeyRideId: 'r',
        DispatchFcmConstants.dataKeyEventId: 'e',
      }),
      isNull,
    );
  });
}
