import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/pid/decoders/maf_air_flow_rate_decoder.dart';

void main() {
  group('decodeMafAirFlowRate', () {
    test('decodes MAF correctly from hex response', () {
      // 41 10 09 C4 -> (9 * 256 + 196) / 100 = 2500 / 100 = 25.00 g/s
      final response = ElmResponse(
        raw: '41 10 09 C4\r>',
        lines: ['41 10 09 C4'],
        type: ElmResponseType.data,
      );

      final maf = decodeMafAirFlowRate(response);
      expect(maf, 25.0);
    });

    test('throws FormatException for wrong PID header', () {
      final response = ElmResponse(
        raw: '41 0C 09 C4\r>',
        lines: ['41 0C 09 C4'],
        type: ElmResponseType.data,
      );

      expect(() => decodeMafAirFlowRate(response), throwsA(isA<FormatException>()));
    });
  });
}
