import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/services/dtc/dtc_decoder.dart';
import 'package:redrive/services/dtc/dtc_database.dart';

void main() {
  const decoder = DtcDecoder();

  group('DtcDecoder', () {
    test('decodes Mode 03 spaced response into confirmed DTCs', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 03 00 01 71\r',
        lines: ['43 03 00 01 71'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes[0].code, 'P0300');
      expect(codes[0].isPending, isFalse);
      expect(codes[0].severity, 'Critical');

      expect(codes[1].code, 'P0171');
      expect(codes[1].isPending, isFalse);
      expect(codes[1].severity, 'Critical');
    });

    test('decodes Mode 07 response into pending DTCs', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '47 04 20 00 00\r',
        lines: ['47 04 20 00 00'],
      );

      final codes = decoder.decode(response, isPending: true);
      expect(codes.length, 1);
      expect(codes[0].code, 'P0420');
      expect(codes[0].isPending, isTrue);
      expect(codes[0].severity, 'Warning');
    });

    test('decodes compact hex response without spaces', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '4303000171\r',
        lines: ['4303000171'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes.map((c) => c.code), containsAll(['P0300', 'P0171']));
    });

    test('decodes CAN multiline response with ECU header', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '7E8 06 43 02 03 00 01 71\r',
        lines: ['7E8 06 43 02 03 00 01 71'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes[0].code, 'P0300');
      expect(codes[1].code, 'P0171');
    });

    test('returns empty list for no trouble codes (43 00 or NO DATA)', () {
      const responseNoData = ElmResponse(
        type: ElmResponseType.data,
        raw: 'NO DATA\r',
        lines: ['NO DATA'],
      );
      expect(decoder.decode(responseNoData), isEmpty);

      const responseZero = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 00\r',
        lines: ['43 00'],
      );
      expect(decoder.decode(responseZero), isEmpty);

      const responseAllZeros = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 00 00 00 00 00 00\r',
        lines: ['43 00 00 00 00 00 00'],
      );
      expect(decoder.decode(responseAllZeros), isEmpty);
    });

    test('correctly decodes Chassis (C), Body (B), and Network (U) codes', () {
      // 0x40 0x35 -> C0035
      // 0x80 0x01 -> B0001
      // 0xC1 0x00 -> U0100
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 40 35 80 01 C1 00\r',
        lines: ['43 40 35 80 01 C1 00'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 3);
      expect(codes[0].code, 'C0035');
      expect(codes[0].system, 'Chassis');
      expect(codes[1].code, 'B0001');
      expect(codes[1].system, 'Body');
      expect(codes[2].code, 'U0100');
      expect(codes[2].system, 'Network');
    });
  });

  group('DtcDatabase', () {
    test('resolves known DTC with full metadata', () {
      final code = DtcDatabase.resolve('P0300');
      expect(code.code, 'P0300');
      expect(code.title, contains('Random/Multiple Cylinder Misfire'));
      expect(code.severity, 'Critical');
      expect(code.system, 'Powertrain');
    });

    test('resolves unknown code with fallback system classification', () {
      final unknownP = DtcDatabase.resolve('P0999');
      expect(unknownP.code, 'P0999');
      expect(unknownP.system, 'Powertrain');
      expect(unknownP.severity, 'Warning');

      final unknownU = DtcDatabase.resolve('U0999');
      expect(unknownU.code, 'U0999');
      expect(unknownU.system, 'Network');
    });
  });
}
