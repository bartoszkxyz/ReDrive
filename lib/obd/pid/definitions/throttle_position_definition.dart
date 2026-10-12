import '../decoders/throttle_position_decoder.dart';
import '../pid_definition.dart';
import '../pid_key.dart';

final PidDefinition<double> throttlePositionDefinition = PidDefinition<double>(
  key: PidKey.throttlePosition,
  command: "0111",
  pid: 0x11,
  decoder: decodeThrottlePosition,
);
