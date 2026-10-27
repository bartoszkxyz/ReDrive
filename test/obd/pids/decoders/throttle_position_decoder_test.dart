import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/pid/decoders/throttle_position_decoder.dart';

void main() {
  group('decodeThrottlePosition', () {
    test('decodes throttle position correctly from hex response', () {
      // 0x4D = 77 -> (77 * 100) / 255 = 30.2%
      final response = ElmResponse(
        raw: '41 11 4D\r>',
        lines: ['41 11 4D'],
        type: ElmResponseType.data,
      );

      final throttle = decodeThrottlePosition(response);
      expect(throttle, closeTo(30.2, 0.1));
    });

    test('throws FormatException for wrong PID header', () {
      final response = ElmResponse(
        raw: '41 05 4D\r>',
        lines: ['41 05 4D'],
        type: ElmResponseType.data,
      );

      expect(() => decodeThrottlePosition(response), throwsA(isA<FormatException>()));
    });
  });
}
