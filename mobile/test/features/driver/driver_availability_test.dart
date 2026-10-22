import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ora/app/di/providers.dart';
import 'package:ora/core/errors/failure_mapper.dart';
import 'package:ora/core/network/request_context.dart';
import 'package:ora/features/driver/data/availability/driver_availability_remote_data_source.dart';
import 'package:ora/features/driver/presentation/view_models/driver_availability_view_model.dart';

void main() {
  late _FakeAvailabilityRemote remote;

  ProviderContainer container() {
    return ProviderContainer(
      overrides: [
        driverAvailabilityRemoteDataSourceProvider.overrideWithValue(remote),
        failureMapperProvider.overrideWithValue(const FailureMapper()),
      ],
    );
  }

  setUp(() {
    remote = _FakeAvailabilityRemote();
  });

  test('initial GET restores persisted online state', () async {
    remote.nextState = 'online';
    final c = container();
    addTearDown(c.dispose);
    final sub = c.listen(driverAvailabilityProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().availabilityState, 'online');
    expect(sub.read().isOnline, isTrue);
    expect(sub.read().loaded, isTrue);
    sub.close();
  });

  test('toggle offline→online calls goOnline and adopts snapshot', () async {
    remote.nextState = 'offline';
    final c = container();
    addTearDown(c.dispose);
    final sub = c.listen(driverAvailabilityProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(sub.read().isOnline, isFalse);

    remote.nextState = 'online';
    await c.read(driverAvailabilityProvider.notifier).toggle();
    expect(remote.calls, ['get', 'online']);
    expect(sub.read().isOnline, isTrue);
    expect(sub.read().busy, isFalse);
    sub.close();
  });

  test('toggle online→offline calls goOffline', () async {
    remote.nextState = 'online';
    final c = container();
    addTearDown(c.dispose);
    final sub = c.listen(driverAvailabilityProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    remote.nextState = 'offline';
    await c.read(driverAvailabilityProvider.notifier).toggle();
    expect(remote.calls, ['get', 'offline']);
    expect(sub.read().isOnline, isFalse);
    sub.close();
  });

  test('toggle failure keeps last confirmed state and surfaces error',
      () async {
    remote.nextState = 'offline';
    remote.failOn = 'online';
    final c = container();
    addTearDown(c.dispose);
    final sub = c.listen(driverAvailabilityProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await c.read(driverAvailabilityProvider.notifier).toggle();
    expect(sub.read().isOnline, isFalse);
    expect(sub.read().busy, isFalse);
    expect(sub.read().errorMessage, isNotNull);
    sub.close();
  });
}

class _FakeAvailabilityRemote implements DriverAvailabilityRemoteDataSource {
  String nextState = 'offline';
  String? failOn;
  final calls = <String>[];

  DriverAvailabilitySnapshot _snap() =>
      DriverAvailabilitySnapshot(availabilityState: nextState);

  @override
  Future<DriverAvailabilitySnapshot> getAvailability({
    RequestContext? context,
  }) async {
    calls.add('get');
    return _snap();
  }

  @override
  Future<DriverAvailabilitySnapshot> goOnline({RequestContext? context}) async {
    calls.add('online');
    if (failOn == 'online') throw Exception('server');
    return _snap();
  }

  @override
  Future<DriverAvailabilitySnapshot> goOffline({RequestContext? context}) async {
    calls.add('offline');
    if (failOn == 'offline') throw Exception('server');
    return _snap();
  }
}
