import '../../models/live_sensor_item.dart';
import '../../obd/models/obd_data.dart';
import '../../obd/pid/pid_key.dart';

/// Manages real-time sensor statistics (min, max, average) and filtering.
class SensorStatisticsService {
  final Map<PidKey, LiveSensorItem> _sensors = {};

  SensorStatisticsService() {
    _initSensors();
  }

  void _initSensors() {
    _sensors[PidKey.engineRpm] = const LiveSensorItem(
      key: PidKey.engineRpm,
      name: 'Engine Speed (RPM)',
      category: 'Engine',
      unit: 'rpm',
      decimalPlaces: 0,
      normalMin: 600,
      normalMax: 6500,
    );

    _sensors[PidKey.vehicleSpeed] = const LiveSensorItem(
      key: PidKey.vehicleSpeed,
      name: 'Vehicle Speed',
      category: 'Engine',
      unit: 'km/h',
      decimalPlaces: 0,
      normalMin: 0,
      normalMax: 200,
    );

    _sensors[PidKey.engineLoad] = const LiveSensorItem(
      key: PidKey.engineLoad,
      name: 'Calculated Engine Load',
      category: 'Engine',
      unit: '%',
      decimalPlaces: 1,
      normalMin: 0,
      normalMax: 100,
    );

    _sensors[PidKey.throttlePosition] = const LiveSensorItem(
      key: PidKey.throttlePosition,
      name: 'Absolute Throttle Position',
      category: 'Engine',
      unit: '%',
      decimalPlaces: 1,
      normalMin: 0,
      normalMax: 100,
    );

    _sensors[PidKey.coolantTemperature] = const LiveSensorItem(
      key: PidKey.coolantTemperature,
      name: 'Engine Coolant Temp',
      category: 'Temperatures',
      unit: '°C',
      decimalPlaces: 0,
      normalMin: 40,
      normalMax: 110,
    );

    _sensors[PidKey.mafAirFlowRate] = const LiveSensorItem(
      key: PidKey.mafAirFlowRate,
      name: 'Mass Air Flow (MAF)',
      category: 'Air & Fuel',
      unit: 'g/s',
      decimalPlaces: 2,
      normalMin: 0,
      normalMax: 120,
    );

    _sensors[PidKey.engineFuelRate] = const LiveSensorItem(
      key: PidKey.engineFuelRate,
      name: 'Engine Fuel Rate (ECU)',
      category: 'Air & Fuel',
      unit: 'L/h',
      decimalPlaces: 2,
      normalMin: 0,
      normalMax: 35,
    );

    _sensors[PidKey.adapterVoltage] = const LiveSensorItem(
      key: PidKey.adapterVoltage,
      name: 'Adapter / Battery Voltage',
      category: 'Electrical',
      unit: 'V',
      decimalPlaces: 1,
      normalMin: 11.5,
      normalMax: 15.0,
    );

    _sensors[PidKey.intakeAirTemperature] = const LiveSensorItem(
      key: PidKey.intakeAirTemperature,
      name: 'Intake Air Temp (IAT)',
      category: 'Temperatures',
      unit: '°C',
      decimalPlaces: 0,
      normalMin: -10,
      normalMax: 65,
    );

    _sensors[PidKey.intakeManifoldPressure] = const LiveSensorItem(
      key: PidKey.intakeManifoldPressure,
      name: 'Intake Manifold Pressure (MAP)',
      category: 'Engine',
      unit: 'kPa',
      decimalPlaces: 0,
      normalMin: 20,
      normalMax: 105,
    );

    _sensors[PidKey.timingAdvance] = const LiveSensorItem(
      key: PidKey.timingAdvance,
      name: 'Ignition Timing Advance',
      category: 'Engine',
      unit: '°',
      decimalPlaces: 1,
      normalMin: -10,
      normalMax: 45,
    );

    _sensors[PidKey.shortTermFuelTrim1] = const LiveSensorItem(
      key: PidKey.shortTermFuelTrim1,
      name: 'Short Term Fuel Trim B1',
      category: 'Air & Fuel',
      unit: '%',
      decimalPlaces: 1,
      normalMin: -15,
      normalMax: 15,
    );

    _sensors[PidKey.longTermFuelTrim1] = const LiveSensorItem(
      key: PidKey.longTermFuelTrim1,
      name: 'Long Term Fuel Trim B1',
      category: 'Air & Fuel',
      unit: '%',
      decimalPlaces: 1,
      normalMin: -15,
      normalMax: 15,
    );

    _sensors[PidKey.fuelPressure] = const LiveSensorItem(
      key: PidKey.fuelPressure,
      name: 'Fuel Rail Pressure',
      category: 'Air & Fuel',
      unit: 'kPa',
      decimalPlaces: 0,
      normalMin: 200,
      normalMax: 500,
    );

    _sensors[PidKey.fuelTankLevel] = const LiveSensorItem(
      key: PidKey.fuelTankLevel,
      name: 'Fuel Tank Level Input',
      category: 'Air & Fuel',
      unit: '%',
      decimalPlaces: 1,
      normalMin: 10,
      normalMax: 100,
    );

    _sensors[PidKey.barometricPressure] = const LiveSensorItem(
      key: PidKey.barometricPressure,
      name: 'Barometric Pressure',
      category: 'Air & Fuel',
      unit: 'kPa',
      decimalPlaces: 0,
      normalMin: 90,
      normalMax: 105,
    );

    _sensors[PidKey.controlModuleVoltage] = const LiveSensorItem(
      key: PidKey.controlModuleVoltage,
      name: 'Control Module (ECU) Voltage',
      category: 'Electrical',
      unit: 'V',
      decimalPlaces: 2,
      normalMin: 11.5,
      normalMax: 15.0,
    );

    _sensors[PidKey.ambientAirTemperature] = const LiveSensorItem(
      key: PidKey.ambientAirTemperature,
      name: 'Ambient Air Temp',
      category: 'Temperatures',
      unit: '°C',
      decimalPlaces: 0,
      normalMin: -20,
      normalMax: 50,
    );

    _sensors[PidKey.engineOilTemperature] = const LiveSensorItem(
      key: PidKey.engineOilTemperature,
      name: 'Engine Oil Temp',
      category: 'Temperatures',
      unit: '°C',
      decimalPlaces: 0,
      normalMin: 70,
      normalMax: 125,
    );

    _sensors[PidKey.runTimeSinceStart] = const LiveSensorItem(
      key: PidKey.runTimeSinceStart,
      name: 'Engine Run Time',
      category: 'Engine',
      unit: 's',
      decimalPlaces: 0,
      normalMin: 0,
      normalMax: 7200,
    );
  }

  /// Updates sensor statistics from the latest [ObdData] snapshot.
  void updateFromData(ObdData data) {
    _update(PidKey.engineRpm, data.rpm.toDouble());
    _update(PidKey.vehicleSpeed, data.speed.toDouble());
    _update(PidKey.engineLoad, data.engineLoad);
    _update(PidKey.throttlePosition, data.throttlePosition);
    _update(PidKey.coolantTemperature, data.coolantTemp.toDouble());
    if (data.maf > 0) {
      _update(PidKey.mafAirFlowRate, data.maf);
    }
    if (data.engineFuelRate > 0) {
      _update(PidKey.engineFuelRate, data.engineFuelRate);
    }
    if (data.voltage > 0) {
      _update(PidKey.adapterVoltage, data.voltage);
    }
  }

  /// Updates sensor statistics from a map of latest PID updates.
  void updateFromValues(Map<PidKey, num> values) {
    for (final entry in values.entries) {
      _update(entry.key, entry.value.toDouble());
    }
  }

  void updateValue(PidKey key, double val) {
    _update(key, val);
  }

  void _update(PidKey key, double val) {
    final existing = _sensors[key];
    if (existing != null) {
      _sensors[key] = existing.updateValue(val);
    }
  }

  /// Returns all tracked sensors.
  List<LiveSensorItem> getAllSensors() {
    return _sensors.values.toList();
  }

  /// Returns sensors filtered by category, optional text query, and optional allowed keys.
  List<LiveSensorItem> getFilteredSensors({
    String category = 'All',
    String query = '',
    Set<PidKey>? allowedKeys,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    return _sensors.values.where((item) {
      if (allowedKeys != null && !allowedKeys.contains(item.key)) {
        return false;
      }
      final matchesCategory = category == 'All' || item.category == category;
      final matchesQuery = cleanQuery.isEmpty ||
          item.name.toLowerCase().contains(cleanQuery) ||
          item.category.toLowerCase().contains(cleanQuery) ||
          item.unit.toLowerCase().contains(cleanQuery);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  /// Resets statistics counters.
  void resetStats() {
    _initSensors();
  }
}
