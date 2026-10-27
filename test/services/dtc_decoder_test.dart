import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/services/dtc/dtc_decoder.dart';
import 'package:obdrive/services/dtc/dtc_database.dart';

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

    test('padding 00 00 pairs after real DTC yield no P0000', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 01 00 00 00 00\r',
        lines: ['43 01 00 00 00 00'],
      );
      final codes = decoder.decode(response);
      expect(codes.map((c) => c.code), isNot(contains('P0000')));
      expect(codes, isEmpty);
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

    test('decodes K-Line ATH0 response with count byte (43 01 01 33 00 00) to P0133 without phantom codes', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 01 01 33 00 00\r',
        lines: ['43 01 01 33 00 00'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 1);
      expect(codes.first.code, 'P0133');
      expect(codes.first.title, contains('O2 Sensor Circuit Slow Response'));
    });

    test('decodes K-Line ATH0 response with 2 codes (43 02 03 00 01 71) to P0300 and P0171', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 02 03 00 01 71\r',
        lines: ['43 02 03 00 01 71'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 2);
      expect(codes[0].code, 'P0300');
      expect(codes[1].code, 'P0171');
    });

    test('decodes Mode 07 pending response with count byte (47 01 04 20) to P0420', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '47 01 04 20\r',
        lines: ['47 01 04 20'],
      );

      final codes = decoder.decode(response, isPending: true);
      expect(codes.length, 1);
      expect(codes.first.code, 'P0420');
      expect(codes.first.isPending, isTrue);
    });

    test('decodes Mode 07 pending response with count byte = 2 (47 02 01 18 01 02)', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '47 02 01 18 01 02\r',
        lines: ['47 02 01 18 01 02'],
      );

      final codes = decoder.decode(response, isPending: true);
      expect(codes.length, 2);
      expect(codes.map((c) => c.code), containsAll(['P0118', 'P0102']));
      expect(codes.every((c) => c.isPending), isTrue);
    });

    test('decodes Mode 07 zero-DTC response (47 00) to empty list', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '47 00\r',
        lines: ['47 00'],
      );

      expect(decoder.decode(response, isPending: true), isEmpty);
    });

    test('decodes multi-line ISO-TP responses with line numbers (0:, 1:)', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '0: 43 04 01 33 01 71\r\n1: 03 00 04 20 00 00\r',
        lines: ['0: 43 04 01 33 01 71', '1: 03 00 04 20 00 00'],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 4);
      expect(
        codes.map((c) => c.code),
        containsAll(['P0133', 'P0171', 'P0300', 'P0420']),
      );
    });

    test('decodes multi-frame CAN response with first frame (10) and consecutive frame (21)', () {
      const response = ElmResponse(
        type: ElmResponseType.data,
        raw: '7E8 10 09 43 03 03 00 01 71\r\n7E8 21 04 20 00 00 00 00\r',
        lines: [
          '7E8 10 09 43 03 03 00 01 71',
          '7E8 21 04 20 00 00 00 00',
        ],
      );

      final codes = decoder.decode(response, isPending: false);
      expect(codes.length, 3);
      expect(codes.map((c) => c.code), containsAll(['P0300', 'P0171', 'P0420']));
    });

    test('decodes compact hex with count byte (430101330000 and 430203000171)', () {
      const resp1 = ElmResponse(
        type: ElmResponseType.data,
        raw: '430101330000\r',
        lines: ['430101330000'],
      );
      final codes1 = decoder.decode(resp1);
      expect(codes1.length, 1);
      expect(codes1.first.code, 'P0133');

      const resp2 = ElmResponse(
        type: ElmResponseType.data,
        raw: '430203000171\r',
        lines: ['430203000171'],
      );
      final codes2 = decoder.decode(resp2);
      expect(codes2.length, 2);
      expect(codes2.map((c) => c.code), containsAll(['P0300', 'P0171']));

      const respZero = ElmResponse(
        type: ElmResponseType.data,
        raw: '4300\r',
        lines: ['4300'],
      );
      expect(decoder.decode(respZero), isEmpty);
    });

    test('supports decodeRaw convenience method for raw hex strings', () {
      final codes = decoder.decodeRaw('43', '43 01 01 33 00 00');
      expect(codes.length, 1);
      expect(codes.first.code, 'P0133');

      final pendingCodes = decoder.decodeRaw('47', '47 01 04 20');
      expect(pendingCodes.length, 1);
      expect(pendingCodes.first.code, 'P0420');
      expect(pendingCodes.first.isPending, isTrue);

      final cleanCodes = decoder.decodeRaw('43', '43 00');
      expect(cleanCodes, isEmpty);
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

    test('resolves Suzuki Swift 3 (M15A) powertrain trouble codes with full descriptions', () {
      final p0011 = DtcDatabase.resolve('P0011');
      expect(p0011.code, 'P0011');
      expect(p0011.system, 'Powertrain');
      expect(p0011.title, contains('Timing Over-Advanced'));
      expect(p0011.description, contains('Variable Valve Timing'));
      expect(p0011.possibleCauses, contains('oil control valve'));

      final p0012 = DtcDatabase.resolve('P0012');
      expect(p0012.code, 'P0012');
      expect(p0012.title, contains('Timing Over-Retarded'));

      final p0103 = DtcDatabase.resolve('P0103');
      expect(p0103.code, 'P0103');
      expect(p0103.title, contains('Circuit High Input'));

      final p0117 = DtcDatabase.resolve('P0117');
      expect(p0117.code, 'P0117');
      expect(p0117.severity, 'Critical');
      expect(p0117.title, contains('Circuit Low Input'));

      final p0118 = DtcDatabase.resolve('P0118');
      expect(p0118.code, 'P0118');
      expect(p0118.severity, 'Warning');
      expect(p0118.title, contains('Circuit High Input'));
      expect(p0118.symptoms, contains('Hard engine starting'));

      final p0121 = DtcDatabase.resolve('P0121');
      expect(p0121.code, 'P0121');
      expect(p0121.title, contains('Throttle Position Sensor'));

      final p0134 = DtcDatabase.resolve('P0134');
      expect(p0134.code, 'P0134');
      expect(p0134.title, contains('No Activity Detected'));

      final p0135 = DtcDatabase.resolve('P0135');
      expect(p0135.code, 'P0135');
      expect(p0135.title, contains('Heater Circuit Malfunction'));

      final p0325 = DtcDatabase.resolve('P0325');
      expect(p0325.code, 'P0325');
      expect(p0325.title, contains('Knock Sensor'));

      final p0335 = DtcDatabase.resolve('P0335');
      expect(p0335.code, 'P0335');
      expect(p0335.severity, 'Critical');
      expect(p0335.title, contains('Crankshaft Position Sensor'));

      final p0340 = DtcDatabase.resolve('P0340');
      expect(p0340.code, 'P0340');
      expect(p0340.severity, 'Critical');
      expect(p0340.title, contains('Camshaft Position Sensor'));
    });
  });
}
