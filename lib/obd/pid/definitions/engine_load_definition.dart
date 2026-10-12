import '../decoders/engine_load_decoder.dart';
import '../pid_definition.dart';
import '../pid_key.dart';

final PidDefinition<double> engineLoadDefinition = PidDefinition<double>(
  key: PidKey.engineLoad,
  command: "0104",
  pid: 0x04,
  decoder: decodeEngineLoad,
);
