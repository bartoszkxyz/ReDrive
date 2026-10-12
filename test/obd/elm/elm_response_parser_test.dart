import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/elm/elm_response_parser.dart';

void main() {
  const parser = ElmResponseParser();

  group('ElmResponseParser - Suzuki Swift & Vgate iCar Pro Handshake', () {
    test('parses standard PID 0100 response', () {
      final res = parser.parse('41 00 BE 3F B8 13\r>');
      expect(res.type, ElmResponseType.data);
      expect(res.lines, ['41 00 BE 3F B8 13']);
      expect(res.wasSearching, isFalse);
    });

    test('parses Suzuki Swift K-Line response with SEARCHING and BUS INIT: OK', () {
      const raw = 'SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>';
      final res = parser.parse(raw);
      expect(res.type, ElmResponseType.data);
      expect(res.lines, ['41 00 BE 3F B8 13']);
      expect(res.wasSearching, isTrue);
    });

    test('parses K-Line response with progress dots and BUS INIT: ...OK', () {
      const raw = 'SEARCHING...\r\n...\r\nBUS INIT: ...OK\r\n41 00 08 18 00 00\r\n>';
      final res = parser.parse(raw);
      expect(res.type, ElmResponseType.data);
      expect(res.lines, ['41 00 08 18 00 00']);
      expect(res.wasSearching, isTrue);
    });

    test('parses failed bus init with SEARCHING and BUS INIT: ERROR', () {
      const raw = 'SEARCHING...\r\nBUS INIT: ERROR\r\n>';
      final res = parser.parse(raw);
      expect(res.type, ElmResponseType.busError);
      expect(res.wasSearching, isTrue);
    });

    test('parses Vgate iCar Pro ELM327 v2.3 adapter info banner', () {
      final res1 = parser.parse('ELM327 v2.3\r\n>');
      expect(res1.type, ElmResponseType.adapterInfo);

      final res2 = parser.parse('iCar Pro v2.3\r\n>');
      expect(res2.type, ElmResponseType.adapterInfo);

      final res3 = parser.parse('Vgate iCar Pro\r\n>');
      expect(res3.type, ElmResponseType.adapterInfo);
    });

    test('parses OK responses', () {
      final res = parser.parse('OK\r\n>');
      expect(res.type, ElmResponseType.ok);
    });

    test('parses voltage responses', () {
      final res = parser.parse('14.2V\r\n>');
      expect(res.type, ElmResponseType.adapterVoltage);
    });

    test('parses UNABLE TO CONNECT', () {
      final res = parser.parse('SEARCHING...\r\nUNABLE TO CONNECT\r\n>');
      expect(res.type, ElmResponseType.unableToConnect);
      expect(res.wasSearching, isTrue);
    });

    test('parses NO DATA', () {
      final res = parser.parse('NO DATA\r\n>');
      expect(res.type, ElmResponseType.noData);
    });
  });
}
