import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/obd/pid/pid_registry.dart';
import 'package:obdrive/services/sensor/sensor_statistics_service.dart';

void main() {
  group('SensorStatisticsService', () {
    late SensorStatisticsService service;

    setUp(() {
      service = SensorStatisticsService();
    });

    test('initializes all standard vehicle sensors', () {
      final all = service.getAllSensors();
      expect(all.length, greaterThanOrEqualTo(20));

      final keys = all.map((s) => s.key).toSet();
      expect(keys.contains(PidKey.engineRpm), isTrue);
      expect(keys.contains(PidKey.intakeAirTemperature), isTrue);
      expect(keys.contains(PidKey.intakeManifoldPressure), isTrue);
      expect(keys.contains(PidKey.timingAdvance), isTrue);
      expect(keys.contains(PidKey.controlModuleVoltage), isTrue);
    });

    test('updateFromValues updates stats for all updated sensors', () {
      service.updateFromValues({
        PidKey.engineRpm: 2400,
        PidKey.intakeAirTemperature: 32,
        PidKey.intakeManifoldPressure: 65,
      });

      final rpm = service.getAllSensors().firstWhere((s) => s.key == PidKey.engineRpm);
      expect(rpm.currentValue, 2400.0);
      expect(rpm.minValue, 2400.0);
      expect(rpm.maxValue, 2400.0);
      expect(rpm.sampleCount, 1);

      final iat = service.getAllSensors().firstWhere((s) => s.key == PidKey.intakeAirTemperature);
      expect(iat.currentValue, 32.0);

      // Second update
      service.updateFromValues({
        PidKey.engineRpm: 1800,
      });

      final updatedRpm = service.getAllSensors().firstWhere((s) => s.key == PidKey.engineRpm);
      expect(updatedRpm.currentValue, 1800.0);
      expect(updatedRpm.minValue, 1800.0);
      expect(updatedRpm.maxValue, 2400.0);
      expect(updatedRpm.avgValue, 2100.0);
      expect(updatedRpm.sampleCount, 2);
    });

    test('getFilteredSensors filters by category and allowedKeys', () {
      final coreOnly = service.getFilteredSensors(allowedKeys: PidRegistry.coreKeys);
      expect(coreOnly.length, 9);
      for (final sensor in coreOnly) {
        expect(PidRegistry.coreKeys.contains(sensor.key), isTrue);
      }

      final temperatures = service.getFilteredSensors(category: 'Temperatures');
      expect(temperatures.every((s) => s.category == 'Temperatures'), isTrue);
    });
  });
}
