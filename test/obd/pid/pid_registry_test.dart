import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/pid/pid_definition.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/obd/pid/pid_registry.dart';

void main() {
  test('finds engine RPM definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.engineRpm);

    expect(definition?.command, '010C');
  });

  test('finds vehicle speed definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.vehicleSpeed);

    expect(definition?.command, '010D');
  });

  test('finds coolant temperature definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.coolantTemperature);

    expect(definition?.command, '0105');
  });

  test('finds adapter voltage definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.adapterVoltage);

    expect(definition?.command, 'ATRV');
    expect(definition?.source, PidSource.adapter);
  });

  test('finds engine load definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.engineLoad);

    expect(definition?.command, '0104');
    expect(definition?.pid, 0x04);
  });

  test('finds throttle position definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.throttlePosition);

    expect(definition?.command, '0111');
    expect(definition?.pid, 0x11);
  });

  test('finds MAF air flow rate definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.mafAirFlowRate);

    expect(definition?.command, '0110');
    expect(definition?.pid, 0x10);
  });

  test('finds engine fuel rate definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.engineFuelRate);

    expect(definition?.command, '015E');
    expect(definition?.pid, 0x5E);
  });

  test('finds fuel system status definition', () {
    final registry = PidRegistry();
    final definition = registry.find(PidKey.fuelSystemStatus);

    expect(definition?.command, '0103');
    expect(definition?.pid, 0x03);
  });

  group('PidRegistry.findSupportedEcuKeys', () {
    test('returns matching ECU PID keys including load, MAF, and fuel rate', () {
      final registry = PidRegistry();

      final result = registry.findSupportedEcuKeys({
        0x04,
        0x05,
        0x0C,
        0x0D,
        0x10,
        0x11,
        0x5E,
      });

      expect(result, {
        PidKey.engineLoad,
        PidKey.coolantTemperature,
        PidKey.engineRpm,
        PidKey.vehicleSpeed,
        PidKey.mafAirFlowRate,
        PidKey.throttlePosition,
        PidKey.engineFuelRate,
      });
    });

    test('returns only supported ECU PID keys', () {
      final registry = PidRegistry();

      final result = registry.findSupportedEcuKeys({0x0C});

      expect(result, {PidKey.engineRpm});
    });

    test('does not include adapter parameters', () {
      final registry = PidRegistry();

      final result = registry.findSupportedEcuKeys({0x05, 0x0C, 0x0D});

      expect(result.contains(PidKey.adapterVoltage), isFalse);
    });

    test('returns empty set when supported PID set is empty', () {
      final registry = PidRegistry();

      final result = registry.findSupportedEcuKeys({});

      expect(result, isEmpty);
    });

    test('ignores supported PIDs that are not registered', () {
      final registry = PidRegistry();

      final result = registry.findSupportedEcuKeys({0x01, 0x02, 0x08});

      expect(result, isEmpty);
    });
  });
}
