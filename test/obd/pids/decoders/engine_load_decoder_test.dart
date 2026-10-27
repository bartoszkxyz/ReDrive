import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/pid/decoders/engine_load_decoder.dart';

void main() {
  group('decodeEngineLoad', () {
    test('decodes engine load correctly from hex response', () {
      // 0x66 = 102 -> (102 * 100) / 255 = 40.0%
      final response = ElmResponse(
        raw: '41 04 66\r>',
        lines: ['41 04 66'],
        type: ElmResponseType.data,
      );

      final load = decodeEngineLoad(response);
      expect(load, closeTo(40.0, 0.1));
    });

    test('decodes 0% and 100% load correctly', () {
      final zeroResponse = ElmResponse(
        raw: '41 04 00\r>',
        lines: ['41 04 00'],
        type: ElmResponseType.data,
      );
      expect(decodeEngineLoad(zeroResponse), 0.0);

      final fullResponse = ElmResponse(
        raw: '41 04 FF\r>',
        lines: ['41 04 FF'],
        type: ElmResponseType.data,
      );
      expect(decodeEngineLoad(fullResponse), 100.0);
    });

    test('throws FormatException for wrong PID header', () {
      final response = ElmResponse(
        raw: '41 05 66\r>',
        lines: ['41 05 66'],
        type: ElmResponseType.data,
      );

      expect(() => decodeEngineLoad(response), throwsA(isA<FormatException>()));
    });
  });
}
