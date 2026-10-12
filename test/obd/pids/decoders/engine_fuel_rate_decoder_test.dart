import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/pid/decoders/engine_fuel_rate_decoder.dart';

void main() {
  group('decodeEngineFuelRate', () {
    test('decodes fuel rate correctly from hex response', () {
      // 41 5E 00 78 -> (0 * 256 + 120) / 20 = 6.00 L/h
      final response = ElmResponse(
        raw: '41 5E 00 78\r>',
        lines: ['41 5E 00 78'],
        type: ElmResponseType.data,
      );

      final fuelRate = decodeEngineFuelRate(response);
      expect(fuelRate, 6.0);
    });

    test('throws FormatException for wrong PID header', () {
      final response = ElmResponse(
        raw: '41 0D 00 78\r>',
        lines: ['41 0D 00 78'],
        type: ElmResponseType.data,
      );

      expect(() => decodeEngineFuelRate(response), throwsA(isA<FormatException>()));
    });
  });
}
