import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/pid/decoders/standard_sensor_decoders.dart';

ElmResponse _resp(String line) => ElmResponse(
      raw: '$line\r>',
      lines: [line],
      type: ElmResponseType.data,
    );

void main() {
  group('Standard Sensor Decoders', () {
    test('decodeIntakeAirTemperature decodes 010F correctly (A - 40)', () {
      // 0x4B = 75 -> 75 - 40 = 35°C
      expect(decodeIntakeAirTemperature(_resp('41 0F 4B')), 35.0);
    });

    test('decodeIntakeManifoldPressure decodes 010B correctly (A kPa)', () {
      // 0x64 = 100 kPa
      expect(decodeIntakeManifoldPressure(_resp('41 0B 64')), 100.0);
    });

    test('decodeTimingAdvance decodes 010E correctly ((A / 2) - 64)', () {
      // 0xA0 = 160 -> (160 / 2) - 64 = 80 - 64 = 16.0°
      expect(decodeTimingAdvance(_resp('41 0E A0')), 16.0);
    });

    test('decodeShortTermFuelTrim1 decodes 0106 correctly ((A - 128) * 100 / 128)', () {
      // 0x80 = 128 -> (128 - 128) * 100 / 128 = 0.0%
      expect(decodeShortTermFuelTrim1(_resp('41 06 80')), 0.0);
    });

    test('decodeLongTermFuelTrim1 decodes 0107 correctly', () {
      // 0x8A = 138 -> (138 - 128) * 100 / 128 = 7.8125%
      expect(decodeLongTermFuelTrim1(_resp('41 07 8A')), closeTo(7.81, 0.01));
    });

    test('decodeFuelPressure decodes 010A correctly (A * 3 kPa)', () {
      // 0x64 = 100 -> 100 * 3 = 300 kPa
      expect(decodeFuelPressure(_resp('41 0A 64')), 300.0);
    });

    test('decodeFuelTankLevel decodes 012F correctly ((A * 100) / 255)', () {
      // 0xFF = 255 -> 100.0%
      expect(decodeFuelTankLevel(_resp('41 2F FF')), 100.0);
    });

    test('decodeBarometricPressure decodes 0133 correctly', () {
      // 0x65 = 101 kPa
      expect(decodeBarometricPressure(_resp('41 33 65')), 101.0);
    });

    test('decodeControlModuleVoltage decodes 0142 correctly (((256 * A) + B) / 1000)', () {
      // 14.15V -> 14150 = 0x3746 -> A=0x37 (55), B=0x46 (70)
      expect(decodeControlModuleVoltage(_resp('41 42 37 46')), closeTo(14.15, 0.01));
    });

    test('decodeAmbientAirTemperature decodes 0146 correctly (A - 40)', () {
      // 0x3B = 59 -> 59 - 40 = 19°C
      expect(decodeAmbientAirTemperature(_resp('41 46 3B')), 19.0);
    });

    test('decodeEngineOilTemperature decodes 015C correctly (A - 40)', () {
      // 0x85 = 133 -> 133 - 40 = 93°C
      expect(decodeEngineOilTemperature(_resp('41 5C 85')), 93.0);
    });

    test('decodeRunTimeSinceStart decodes 011F correctly ((256 * A) + B)', () {
      // 0x01 0xF4 = (256 * 1) + 244 = 500 seconds
      expect(decodeRunTimeSinceStart(_resp('41 1F 01 F4')), 500.0);
    });
  });
}
