import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/pid/decoders/supported_pids_decoder.dart';

void main() {
  group('decodeSupportedPids', () {
    test('decodes supported PIDs from bitmap', () {
      final response = ElmResponse(
        raw: '41 00 08 18 00 00',
        type: ElmResponseType.data,
        lines: ['41 00 08 18 00 00'],
      );

      final result = decodeSupportedPids(response);

      expect(result, {5, 12, 13});
    });

    test('decodes PID 20 from last bit', () {
      final response = ElmResponse(
        raw: '41 00 00 00 00 01',
        type: ElmResponseType.data,
        lines: ['41 00 00 00 00 01'],
      );

      final result = decodeSupportedPids(response);

      expect(result, {32});
    });

    test('decodes multi-range PIDs with basePid offset', () {
      // Range 0x21 to 0x40 (basePid = 0x20)
      final response20 = ElmResponse(
        raw: '41 20 00 00 00 01',
        type: ElmResponseType.data,
        lines: ['41 20 00 00 00 01'],
      );
      final result20 = decodeSupportedPids(response20, basePid: 0x20);
      expect(result20, {64}); // 0x40

      // Range 0x41 to 0x60 (basePid = 0x40)
      // Bit for PID 0x5E (94): 94 - 64 = 30 -> bit 2 of last byte -> 0x04
      final response40 = ElmResponse(
        raw: '41 40 00 00 00 04',
        type: ElmResponseType.data,
        lines: ['41 40 00 00 00 04'],
      );
      final result40 = decodeSupportedPids(response40, basePid: 0x40);
      expect(result40, {0x5E});
    });

    test('returns empty set when no PIDs are supported', () {
      final response = ElmResponse(
        raw: '41 00 00 00 00 00',
        type: ElmResponseType.data,
        lines: ['41 00 00 00 00 00'],
      );

      final result = decodeSupportedPids(response);

      expect(result, isEmpty);
    });

    test('throws when response contains too few bytes', () {
      final response = ElmResponse(
        raw: '41 00 08',
        type: ElmResponseType.data,
        lines: ['41 00 08'],
      );

      expect(
        () => decodeSupportedPids(response),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when response is not for expected base PID', () {
      final response = ElmResponse(
        raw: '41 0C 08 18 00 00',
        type: ElmResponseType.data,
        lines: ['41 0C 08 18 00 00'],
      );

      expect(
        () => decodeSupportedPids(response),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
