import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/elm/elm_client.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/obd/pid/pid_registry.dart';
import 'package:obdrive/obd/polling/polling_controller.dart';
import '../fakes/fake_obd_connection.dart';

void main() {
  late PidRegistry registry;
  late FakeObdConnection connection;
  late ElmClient elmClient;

  setUp(() {
    registry = PidRegistry();
    connection = FakeObdConnection();
    elmClient = ElmClient(connection: connection);
  });

  tearDown(() async {
    await elmClient.dispose();
    await connection.dispose();
  });

  test('computes union of keys requested by different sources', () {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {
        PidKey.vehicleSpeed,
        PidKey.engineRpm,
        PidKey.coolantTemperature,
      },
    );

    controller.setWatchlist(WatchSource.visibleScreen, {
      PidKey.vehicleSpeed,
      PidKey.engineRpm,
    });
    controller.setWatchlist(WatchSource.backgroundMonitoring, {
      PidKey.vehicleSpeed,
      PidKey.coolantTemperature,
    });
    controller.setWatchlist(WatchSource.session, {PidKey.adapterVoltage});

    final effective = controller.computeEffectiveKeys();

    expect(effective, {
      PidKey.vehicleSpeed,
      PidKey.engineRpm,
      PidKey.coolantTemperature,
      PidKey.adapterVoltage,
    });
  });

  test('removes keys when source watchlists is cleared or empty', () {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {PidKey.vehicleSpeed, PidKey.engineRpm},
    );

    controller.setWatchlist(WatchSource.visibleScreen, {PidKey.engineRpm});
    controller.setWatchlist(WatchSource.backgroundMonitoring, {
      PidKey.vehicleSpeed,
    });

    controller.setWatchlist(WatchSource.visibleScreen, {});

    final effective = controller.computeEffectiveKeys();

    expect(effective, {PidKey.vehicleSpeed});
  });

  test('filters out unsupported ECU PIDs', () {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {PidKey.engineRpm},
    );

    controller.setWatchlist(WatchSource.visibleScreen, {
      PidKey.vehicleSpeed,
      PidKey.engineRpm,
    });

    final effective = controller.computeEffectiveKeys();

    expect(effective, {PidKey.engineRpm});
    expect(effective.contains(PidKey.vehicleSpeed), isFalse);
  });

  test('always allows adapter parameters without checking ECU support', () {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {},
    );

    controller.setWatchlist(WatchSource.visibleScreen, {
      PidKey.adapterVoltage,
      PidKey.vehicleSpeed,
    });

    final effective = controller.computeEffectiveKeys();

    expect(effective, {PidKey.adapterVoltage});
  });

  test(
    'polls requested PID and emits value through stream and latestValues',
    () async {
      final controller = PollingController(
        elmClient: elmClient,
        registry: registry,
        supportedEcuKeys: {PidKey.vehicleSpeed},
      );

      addTearDown(controller.dispose);

      controller.setWatchlist(WatchSource.visibleScreen, {PidKey.vehicleSpeed});

      final emittedValues = <({PidKey key, num value})>[];
      final subscription = controller.updates.listen(emittedValues.add);
      addTearDown(subscription.cancel);

      controller.start();

      await pumpEventQueue();
      expect(connection.sentCommands, ['010D\r']);

      connection.emit('41 0D 2A\r>');
      await pumpEventQueue();

      expect(controller.latestValues[PidKey.vehicleSpeed], 42);
      expect(emittedValues.length, 1);
      expect(emittedValues.first.key, PidKey.vehicleSpeed);
      expect(emittedValues.first.value, 42);

      controller.stop();
    },
  );

  test('stops polling loop when stop is called', () async {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {PidKey.vehicleSpeed},
    );

    addTearDown(controller.dispose);

    controller.setWatchlist(WatchSource.visibleScreen, {PidKey.vehicleSpeed});

    controller.start();
    await pumpEventQueue();
    expect(connection.sentCommands, ['010D\r']);

    controller.stop();

    connection.emit('41 0D 2A\r>');
    await pumpEventQueue();

    connection.sentCommands.clear();
    await pumpEventQueue();

    expect(connection.sentCommands, isEmpty);
    expect(controller.isPolling, isFalse);
  });

  test('emits polling error and stops polling', () async {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {PidKey.vehicleSpeed},
    );

    addTearDown(controller.dispose);

    controller.setWatchlist(WatchSource.visibleScreen, {PidKey.vehicleSpeed});

    final pollingError = Exception('polling failed');

    connection.sendError = pollingError;

    final errorExpectation = expectLater(
      controller.updates,
      emitsError(same(pollingError)),
    );

    controller.start();

    await errorExpectation;

    expect(connection.sentCommands, ['010D\r']);

    expect(controller.isPolling, isFalse);
  });

  test('skips NO DATA and emits error after one failed retry', () async {
    final controller = PollingController(
      elmClient: elmClient,
      registry: registry,
      supportedEcuKeys: {PidKey.vehicleSpeed},
    );
    addTearDown(controller.dispose);

    controller.setWatchlist(WatchSource.visibleScreen, {PidKey.vehicleSpeed});

    Future<void> waitForCommandCount(int count) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (connection.sentCommands.length < count) {
        if (DateTime.now().isAfter(deadline)) {
          fail(
            'Expected $count commands, got ${connection.sentCommands.length}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    final errorExpectation = expectLater(
      controller.updates,
      emitsError(isA<StateError>()),
    );

    controller.start();
    await waitForCommandCount(1);
    connection.emit('NO DATA\r>');

    await waitForCommandCount(2);
    expect(controller.isPolling, isTrue);
    expect(controller.latestValues, isEmpty);

    connection.emit('BUS ERROR\r>');

    await waitForCommandCount(3);
    expect(controller.isPolling, isTrue);
    connection.emit('BUS ERROR\r>');

    await errorExpectation;
    expect(connection.sentCommands, ['010D\r', '010D\r', '010D\r']);
    expect(controller.isPolling, isFalse);
  });

  group('Tiered Priority Scheduling & Smart High-Load Boost', () {
    test('correctly maps PID priority tiers with promoted Load, STFT, and LTFT', () {
      expect(PollingController.priorityFor(PidKey.vehicleSpeed), PidPriorityTier.high);
      expect(PollingController.priorityFor(PidKey.engineRpm), PidPriorityTier.high);
      expect(PollingController.priorityFor(PidKey.throttlePosition), PidPriorityTier.high);
      expect(PollingController.priorityFor(PidKey.mafAirFlowRate), PidPriorityTier.high);
      expect(PollingController.priorityFor(PidKey.engineLoad), PidPriorityTier.high);
      expect(PollingController.priorityFor(PidKey.shortTermFuelTrim1), PidPriorityTier.high);

      expect(PollingController.priorityFor(PidKey.longTermFuelTrim1), PidPriorityTier.normal);
      expect(PollingController.priorityFor(PidKey.timingAdvance), PidPriorityTier.normal);
      expect(PollingController.priorityFor(PidKey.intakeManifoldPressure), PidPriorityTier.normal);
      expect(PollingController.priorityFor(PidKey.fuelSystemStatus), PidPriorityTier.normal);

      expect(PollingController.priorityFor(PidKey.coolantTemperature), PidPriorityTier.low);
      expect(PollingController.priorityFor(PidKey.fuelTankLevel), PidPriorityTier.low);
      expect(PollingController.priorityFor(PidKey.adapterVoltage), PidPriorityTier.low);
    });

    test('computeScheduledKeys includes all uninitialized keys on first cycle', () {
      final controller = PollingController(
        elmClient: elmClient,
        registry: registry,
        supportedEcuKeys: {
          PidKey.vehicleSpeed,
          PidKey.engineLoad,
          PidKey.coolantTemperature,
          PidKey.fuelTankLevel,
        },
      );

      final effective = {
        PidKey.vehicleSpeed,
        PidKey.engineLoad,
        PidKey.coolantTemperature,
        PidKey.fuelTankLevel,
      };

      // When values are not yet known, ALL keys must be scheduled for immediate discovery
      final scheduled = controller.computeScheduledKeys(effective);
      expect(scheduled, containsAll(effective));
    });

    test('interleaves overdue normal and low keys without dumping all low keys at once', () {
      final allKeys = {
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.longTermFuelTrim1,
        PidKey.timingAdvance,
        PidKey.intakeManifoldPressure,
        PidKey.coolantTemperature,
        PidKey.intakeAirTemperature,
        PidKey.fuelTankLevel,
      };
      final controller = PollingController(
        elmClient: elmClient,
        registry: registry,
        supportedEcuKeys: allKeys,
      );

      // Cycle 0 discovery: seed all keys at cycle 0 with normal idle values
      for (final k in allKeys) {
        controller.seedValueForTesting(k, 20, polledAtCycle: 0);
      }
      controller.seedValueForTesting(PidKey.engineRpm, 800, polledAtCycle: 0);
      controller.seedValueForTesting(PidKey.throttlePosition, 13.0, polledAtCycle: 0);

      // Simulate advancing to cycle 8 ( manual computeScheduledKeys after 8 cycles )
      for (int c = 1; c <= 8; c++) {
        // advance internal cycle tracking by calling computeScheduledKeys
        controller.computeScheduledKeys(allKeys);
      }

      // Even when multiple low keys are overdue, at most 1 low key is scheduled per cycle
      final scheduled = controller.computeScheduledKeys(allKeys);
      final lowCount = scheduled
          .where((k) => PollingController.priorityFor(k) == PidPriorityTier.low)
          .length;
      expect(lowCount, lessThanOrEqualTo(1));
    });

    test('Smart High-Load Boost activates when RPM > 3000 or relative throttle > 50%', () {
      final allKeys = {
        PidKey.engineRpm,
        PidKey.throttlePosition,
        PidKey.longTermFuelTrim1,
        PidKey.timingAdvance,
        PidKey.intakeManifoldPressure,
        PidKey.fuelTankLevel,
        PidKey.intakeAirTemperature,
      };
      final controller = PollingController(
        elmClient: elmClient,
        registry: registry,
        supportedEcuKeys: allKeys,
      );

      for (final k in allKeys) {
        controller.seedValueForTesting(k, 20, polledAtCycle: 0);
      }
      controller.seedValueForTesting(PidKey.engineRpm, 3800, polledAtCycle: 0);
      controller.seedValueForTesting(PidKey.throttlePosition, 65.0, polledAtCycle: 0);

      expect(controller.isHighLoadBoostActive, isTrue);

      final scheduled = controller.computeScheduledKeys(allKeys);
      expect(scheduled, containsAll([
        PidKey.longTermFuelTrim1,
        PidKey.timingAdvance,
        PidKey.intakeManifoldPressure,
      ]));
      expect(scheduled, isNot(contains(PidKey.fuelTankLevel)));
    });

    test('quarantines a PID after 5 consecutive NO DATA responses', () async {
      final controller = PollingController(
        elmClient: elmClient,
        registry: registry,
        supportedEcuKeys: {PidKey.vehicleSpeed, PidKey.engineRpm},
      );
      addTearDown(controller.dispose);

      controller.setWatchlist(WatchSource.visibleScreen, {
        PidKey.vehicleSpeed,
        PidKey.engineRpm,
      });

      controller.start();

      for (int i = 0; i < 5; i++) {
        while (connection.sentCommands.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final cmd = connection.sentCommands.removeAt(0);
        if (cmd == '010D\r') {
          connection.emit('NO DATA\r>');
        } else {
          connection.emit('41 0C 0F A0\r>');
        }
        await pumpEventQueue();
        // Handle second command in the cycle
        while (connection.sentCommands.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        final cmd2 = connection.sentCommands.removeAt(0);
        if (cmd2 == '010D\r') {
          connection.emit('NO DATA\r>');
        } else {
          connection.emit('41 0C 0F A0\r>');
        }
        await pumpEventQueue();
      }

      expect(controller.quarantinedKeys, contains(PidKey.vehicleSpeed));
      expect(controller.computeEffectiveKeys(), isNot(contains(PidKey.vehicleSpeed)));
      expect(controller.computeEffectiveKeys(), contains(PidKey.engineRpm));

      controller.stop();
    });
  });
}
