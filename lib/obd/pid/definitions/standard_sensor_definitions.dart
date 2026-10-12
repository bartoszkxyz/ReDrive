import '../decoders/standard_sensor_decoders.dart';
import '../pid_definition.dart';
import '../pid_key.dart';

final PidDefinition<double> intakeAirTemperatureDefinition = PidDefinition<double>(
  key: PidKey.intakeAirTemperature,
  command: "010F",
  pid: 0x0F,
  decoder: decodeIntakeAirTemperature,
);

final PidDefinition<double> intakeManifoldPressureDefinition = PidDefinition<double>(
  key: PidKey.intakeManifoldPressure,
  command: "010B",
  pid: 0x0B,
  decoder: decodeIntakeManifoldPressure,
);

final PidDefinition<double> timingAdvanceDefinition = PidDefinition<double>(
  key: PidKey.timingAdvance,
  command: "010E",
  pid: 0x0E,
  decoder: decodeTimingAdvance,
);

final PidDefinition<double> shortTermFuelTrim1Definition = PidDefinition<double>(
  key: PidKey.shortTermFuelTrim1,
  command: "0106",
  pid: 0x06,
  decoder: decodeShortTermFuelTrim1,
);

final PidDefinition<double> longTermFuelTrim1Definition = PidDefinition<double>(
  key: PidKey.longTermFuelTrim1,
  command: "0107",
  pid: 0x07,
  decoder: decodeLongTermFuelTrim1,
);

final PidDefinition<double> fuelPressureDefinition = PidDefinition<double>(
  key: PidKey.fuelPressure,
  command: "010A",
  pid: 0x0A,
  decoder: decodeFuelPressure,
);

final PidDefinition<double> fuelTankLevelDefinition = PidDefinition<double>(
  key: PidKey.fuelTankLevel,
  command: "012F",
  pid: 0x2F,
  decoder: decodeFuelTankLevel,
);

final PidDefinition<double> barometricPressureDefinition = PidDefinition<double>(
  key: PidKey.barometricPressure,
  command: "0133",
  pid: 0x33,
  decoder: decodeBarometricPressure,
);

final PidDefinition<double> controlModuleVoltageDefinition = PidDefinition<double>(
  key: PidKey.controlModuleVoltage,
  command: "0142",
  pid: 0x42,
  decoder: decodeControlModuleVoltage,
);

final PidDefinition<double> ambientAirTemperatureDefinition = PidDefinition<double>(
  key: PidKey.ambientAirTemperature,
  command: "0146",
  pid: 0x46,
  decoder: decodeAmbientAirTemperature,
);

final PidDefinition<double> engineOilTemperatureDefinition = PidDefinition<double>(
  key: PidKey.engineOilTemperature,
  command: "015C",
  pid: 0x5C,
  decoder: decodeEngineOilTemperature,
);

final PidDefinition<double> runTimeSinceStartDefinition = PidDefinition<double>(
  key: PidKey.runTimeSinceStart,
  command: "011F",
  pid: 0x1F,
  decoder: decodeRunTimeSinceStart,
);
