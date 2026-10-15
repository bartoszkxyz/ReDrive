import 'definitions/adapter_voltage_definition.dart';
import 'definitions/coolant_temperature_definition.dart';
import 'definitions/engine_fuel_rate_definition.dart';
import 'definitions/engine_load_definition.dart';
import 'definitions/engine_rpm_definition.dart';
import 'definitions/maf_air_flow_rate_definition.dart';
import 'definitions/standard_sensor_definitions.dart';
import 'definitions/throttle_position_definition.dart';
import 'definitions/vehicle_speed_definition.dart';
import 'pid_definition.dart';
import 'pid_key.dart';

/// Registry of supported OBD-II PID definitions.
///
/// Maps PID keys to commands, decoders, and metadata,
/// and resolves which PIDs are supported by the connected ECU.
class PidRegistry {
  final Map<PidKey, PidDefinition<num>> _definitions = {
    PidKey.engineRpm: engineRpmDefinition,
    PidKey.vehicleSpeed: vehicleSpeedDefinition,
    PidKey.coolantTemperature: coolantTemperatureDefinition,
    PidKey.adapterVoltage: adapterVoltageDefinition,
    PidKey.engineLoad: engineLoadDefinition,
    PidKey.throttlePosition: throttlePositionDefinition,
    PidKey.mafAirFlowRate: mafAirFlowRateDefinition,
    PidKey.engineFuelRate: engineFuelRateDefinition,
    // Expanded standard Mode 01 sensors
    PidKey.intakeAirTemperature: intakeAirTemperatureDefinition,
    PidKey.intakeManifoldPressure: intakeManifoldPressureDefinition,
    PidKey.timingAdvance: timingAdvanceDefinition,
    PidKey.shortTermFuelTrim1: shortTermFuelTrim1Definition,
    PidKey.longTermFuelTrim1: longTermFuelTrim1Definition,
    PidKey.fuelPressure: fuelPressureDefinition,
    PidKey.fuelTankLevel: fuelTankLevelDefinition,
    PidKey.barometricPressure: barometricPressureDefinition,
    PidKey.controlModuleVoltage: controlModuleVoltageDefinition,
    PidKey.ambientAirTemperature: ambientAirTemperatureDefinition,
    PidKey.engineOilTemperature: engineOilTemperatureDefinition,
    PidKey.runTimeSinceStart: runTimeSinceStartDefinition,
  };

  static const Set<PidKey> coreKeys = {
    PidKey.vehicleSpeed,
    PidKey.engineRpm,
    PidKey.coolantTemperature,
    PidKey.adapterVoltage,
    PidKey.engineLoad,
    PidKey.throttlePosition,
    PidKey.mafAirFlowRate,
    PidKey.engineFuelRate,
    PidKey.intakeAirTemperature,
  };

  Set<PidKey> get allKeys => Set.unmodifiable(_definitions.keys);

  Set<PidKey> get ecuKeys => Set.unmodifiable(
        _definitions.values
            .where((d) => d.source == PidSource.ecu)
            .map((d) => d.key),
      );

  PidDefinition<num>? find(PidKey key) {
    return _definitions[key];
  }

  Set<PidKey> findSupportedEcuKeys(Set<int> supportedPids) {
    final supportedPidKeySet = <PidKey>{};

    for (final definition in _definitions.values) {
      if (definition.source == PidSource.ecu &&
          definition.pid != null &&
          supportedPids.contains(definition.pid)) {
        supportedPidKeySet.add(definition.key);
      }
    }

    return supportedPidKeySet;
  }
}

