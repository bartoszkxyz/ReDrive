import '../decoders/engine_fuel_rate_decoder.dart';
import '../pid_definition.dart';
import '../pid_key.dart';

final PidDefinition<double> engineFuelRateDefinition = PidDefinition<double>(
  key: PidKey.engineFuelRate,
  command: "015E",
  pid: 0x5E,
  decoder: decodeEngineFuelRate,
);
