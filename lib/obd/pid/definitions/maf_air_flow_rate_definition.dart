import '../decoders/maf_air_flow_rate_decoder.dart';
import '../pid_definition.dart';
import '../pid_key.dart';

final PidDefinition<double> mafAirFlowRateDefinition = PidDefinition<double>(
  key: PidKey.mafAirFlowRate,
  command: "0110",
  pid: 0x10,
  decoder: decodeMafAirFlowRate,
);
