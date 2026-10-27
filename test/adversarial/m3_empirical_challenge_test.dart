import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/models/dtc_code.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/elm/elm_response_parser.dart';
import 'package:obdrive/services/dtc/dtc_database.dart';
import 'package:obdrive/services/dtc/dtc_decoder.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/obd/models/obd_data.dart';

class _FakeObdProvider extends ObdProvider {
  ObdMode _mockMode = ObdMode.real;
  bool _mockEcuConnected = true;
  ObdData _mockData = const ObdData();
  String _mockExecuteResponse = '44\r>';
  int executeCallCount = 0;
  String? lastExecutedCommand;

  @override
  ObdMode get mode => _mockMode;

  @override
  bool get isEcuConnected => _mockEcuConnected;

  @override
  ObdData get data => _mockData;

  void setMockState({
    ObdMode mode = ObdMode.real,
    bool isEcuConnected = true,
    int speed = 0,
    int rpm = 0,
    String executeResponse = '44\r>',
  }) {
    _mockMode = mode;
    _mockEcuConnected = isEcuConnected;
    _mockData = _mockData.copyWith(speed: speed, rpm: rpm);
    _mockExecuteResponse = executeResponse;
    executeCallCount = 0;
    lastExecutedCommand = null;
  }

  @override
  Future<ElmResponse> executeCommand(String command) async {
    // Live interlock queries (Mode 01 speed/rpm) are answered from mock state
    // and are not counted as ECU command executions.
    const p = ElmResponseParser();
    if (command == '010D') {
      return p.parse('41 0D ${_mockData.speed.toRadixString(16).padLeft(2, '0')}\r>');
    }
    if (command == '010C') {
      final raw = _mockData.rpm * 4;
      final a = (raw >> 8).toRadixString(16).padLeft(2, '0');
      final b = (raw & 0xFF).toRadixString(16).padLeft(2, '0');
      return p.parse('41 0C $a $b\r>');
    }
    executeCallCount++;
    lastExecutedCommand = command;
    const parser = ElmResponseParser();
    return parser.parse(_mockExecuteResponse);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = ElmResponseParser();
  const decoder = DtcDecoder();

  group('M3 Challenge 1: ElmResponseParser Adversarial Protocol Framing', () {
    test('1.1: Zero DTC frames (43 00, 47 00) must return ElmResponseType.data with verbatim line', () {
      final res43_00 = parser.parse('43 00\r>');
      expect(res43_00.type, ElmResponseType.data);
      expect(res43_00.lines, ['43 00']);

      final res47_00 = parser.parse('47 00\r\n>');
      expect(res47_00.type, ElmResponseType.data);
      expect(res47_00.lines, ['47 00']);

      final res4300Padded = parser.parse(' 43 00 \r>');
      expect(res4300Padded.type, ElmResponseType.data);
      expect(res4300Padded.lines, ['43 00']);
    });

    test('1.2: Mode 04 clear acknowledgment frames (44, OK) parse accurately as data/ok', () {
      final res44 = parser.parse('44\r>');
      expect(res44.type, ElmResponseType.data);
      expect(res44.lines, ['44']);

      final res44Spaced = parser.parse(' 44 \r\n>');
      expect(res44Spaced.type, ElmResponseType.data);
      expect(res44Spaced.lines, ['44']);

      final resOk = parser.parse('OK\r>');
      expect(resOk.type, ElmResponseType.ok);
      expect(resOk.lines, ['OK']);
    });

    test('1.3: Unspaced compact hex payloads parse as ElmResponseType.data without rejection', () {
      final samples = <String, List<String>>{
        '4100BE3FB813\r>': ['4100BE3FB813'],
        '4300\r>': ['4300'],
        '4700\r>': ['4700'],
        '4303000171\r>': ['4303000171'],
        '470420\r>': ['470420'],
        '41057B\r>': ['41057B'],
      };

      for (final entry in samples.entries) {
        final res = parser.parse(entry.key);
        expect(res.type, ElmResponseType.data, reason: 'Failed for sample: ${entry.key}');
        expect(res.lines, entry.value);
      }
    });

    test('1.4: CAN 11-bit and 29-bit header frames parse as ElmResponseType.data', () {
      final can11 = parser.parse('7E8 06 43 02 03 00 01 71\r>');
      expect(can11.type, ElmResponseType.data);
      expect(can11.lines, ['7E8 06 43 02 03 00 01 71']);

      final can29 = parser.parse('18DAF110 06 43 02 03 00 01 71\r>');
      expect(can29.type, ElmResponseType.data);
      expect(can29.lines, ['18DAF110 06 43 02 03 00 01 71']);

      final canMultiLine = parser.parse(
        '7E8 10 09 43 03 03 00 01 71\r\n7E8 21 04 20 00 00 00 00\r>',
      );
      expect(canMultiLine.type, ElmResponseType.data);
      expect(canMultiLine.lines.length, 2);
    });

    test('1.5: Error banners strictly classify to expected error response types and never data', () {
      final errorCases = <String, ElmResponseType>{
        'UNABLE TO CONNECT\r>': ElmResponseType.unableToConnect,
        'SEARCHING...\r\nUNABLE TO CONNECT\r>': ElmResponseType.unableToConnect,
        'NO DATA\r>': ElmResponseType.noData,
        'CAN ERROR\r>': ElmResponseType.busError,
        'BUS ERROR\r>': ElmResponseType.busError,
        'BUS BUSY\r>': ElmResponseType.busError,
        'BUS INIT: ERROR\r>': ElmResponseType.busError,
        'BUFFER FULL\r>': ElmResponseType.adapterError,
        'DATA ERROR\r>': ElmResponseType.adapterError,
        '<DATA ERROR\r>': ElmResponseType.adapterError,
        'RX ERROR\r>': ElmResponseType.adapterError,
        'FB ERROR\r>': ElmResponseType.adapterError,
        'LV RESET\r>': ElmResponseType.adapterError,
        '?\r>': ElmResponseType.unknownCommand,
        'STOPPED\r>': ElmResponseType.stopped,
        'ERR01\r>': ElmResponseType.adapterError,
        'ERR2A\r>': ElmResponseType.adapterError,
      };

      for (final entry in errorCases.entries) {
        final res = parser.parse(entry.key);
        expect(res.type, entry.value, reason: 'Misclassified error banner: ${entry.key}');
      }
    });

    test('1.6: Corrupted and odd-token hex strings are rejected as ElmResponseType.malformed', () {
      final malformedCases = [
        '41 05 7\r>', // 1-digit token
        '41 05 G1\r>', // invalid hex char
        '4100BE3FB81\r>', // odd number of hex digits in unspaced string
        'INVALID COMMAND\r>',
        '7E8 06 GG 02\r>',
      ];

      for (final mal in malformedCases) {
        final res = parser.parse(mal);
        expect(res.type, ElmResponseType.malformed, reason: 'Should be malformed: $mal');
      }
    });
  });

  group('M3 Challenge 2: DtcDecoder Parity & Count Byte Stripping', () {
    test('2.1: K-Line ATH0 count byte stripping: 43 01 01 33 00 00 strictly decodes P0133 only', () {
      final res = decoder.decodeRaw('43', '43 01 01 33 00 00');
      expect(res.length, 1);
      expect(res.first.code, 'P0133');

      // Paranoia check against phantom codes
      final codes = res.map((c) => c.code).toSet();
      expect(codes.contains('P0101'), isFalse, reason: 'Phantom P0101 detected!');
      expect(codes.contains('P3300'), isFalse, reason: 'Phantom P3300 detected!');
      expect(codes.contains('P0000'), isFalse, reason: 'Zero padding P0000 detected!');
    });

    test('2.2: K-Line ATH0 count byte stripping: 43 02 03 00 01 71 strictly decodes P0300 and P0171', () {
      final res = decoder.decodeRaw('43', '43 02 03 00 01 71');
      expect(res.length, 2);
      expect(res[0].code, 'P0300');
      expect(res[1].code, 'P0171');

      // Paranoia check against phantom codes
      final codes = res.map((c) => c.code).toSet();
      expect(codes.contains('P0203'), isFalse, reason: 'Phantom P0203 detected!');
      expect(codes.contains('P0001'), isFalse, reason: 'Phantom P0001 detected!');
    });

    test('2.3: Count byte truncation: trailing garbage padding ignored beyond count byte', () {
      // Count byte = 1, followed by P0133 (01 33), and non-zero padding (04 20 = P0420)
      final res = decoder.decodeRaw('43', '43 01 01 33 04 20');
      expect(res.length, 1);
      expect(res.first.code, 'P0133');
      expect(res.any((c) => c.code == 'P0420'), isFalse,
          reason: 'DtcDecoder failed to obey DTC count limit byte!');
    });

    test('2.4: Zero count byte with trailing padding returns empty list', () {
      final res = decoder.decodeRaw('43', '43 00 00 00 00 00');
      expect(res, isEmpty);

      final resPending = decoder.decodeRaw('47', '47 00 00 00');
      expect(resPending, isEmpty);
    });

    test('2.5: Odd token counts and malformed trailing byte do not throw or crash', () {
      // 43 followed by 2 bytes (even count, no count byte) plus an odd trailing byte
      final res1 = decoder.decodeRaw('43', '43 03 00 12');
      // Should not throw FormatException or RangeError
      expect(res1, isA<List<DtcCode>>());

      // Truncated service headers
      expect(decoder.decodeRaw('43', '43'), isEmpty);
      expect(decoder.decodeRaw('43', '43 01'), isEmpty);
      expect(decoder.decodeRaw('43', ''), isEmpty);
    });

    test('2.6: Compact hex parity: 430101330000 and 430203000171 decode without phantoms', () {
      final res1 = decoder.decodeRaw('43', '430101330000');
      expect(res1.length, 1);
      expect(res1.first.code, 'P0133');

      final res2 = decoder.decodeRaw('43', '430203000171');
      expect(res2.length, 2);
      expect(res2.map((c) => c.code), containsAll(['P0300', 'P0171']));

      // Compact hex with non-zero trailing padding respecting count byte
      final resPadded = decoder.decodeRaw('43', '430101330420');
      expect(resPadded.length, 1);
      expect(resPadded.first.code, 'P0133');
    });

    test('2.7: Multi-frame ISO-TP frames lacking 43 in continuation lines', () {
      // 1st frame has count 3: P0133, P0171 in 1st frame; P0300 in continuation frame
      const multiIsoTp = '0: 43 03 01 33 01 71\r\n1: 03 00 04 20 00 00\r>';
      final res = decoder.decode(multiIsoTp);
      expect(res.length, 3);
      expect(res.map((c) => c.code), containsAll(['P0133', 'P0171', 'P0300']));
      // P0420 should be ignored because count was 3
      expect(res.any((c) => c.code == 'P0420'), isFalse);
    });

    test('2.8: Multi-frame CAN frames with ISO-TP sequence byte (21, 22)', () {
      const canFrames =
          '7E8 10 0B 43 04 01 33 01 71\r\n7E8 21 03 00 04 20 00 00\r>';
      final res = decoder.decode(canFrames);
      expect(res.length, 4);
      expect(res.map((c) => c.code), containsAll(['P0133', 'P0171', 'P0300', 'P0420']));
    });

    test('2.9: All 4 DTC prefixes (P, C, B, U) and bitwise decoding validation', () {
      // 0x01 0x33 -> P0133 (prefix 0)
      // 0x40 0x35 -> C0035 (prefix 1)
      // 0x81 0x00 -> B0100 (prefix 2)
      // 0xC1 0x20 -> U0120 (prefix 3)
      final res = decoder.decodeRaw('43', '43 04 01 33 40 35 81 00 C1 20');
      expect(res.length, 4);
      expect(res[0].code, 'P0133');
      expect(res[0].system, 'Powertrain');
      expect(res[1].code, 'C0035');
      expect(res[1].system, 'Chassis');
      expect(res[2].code, 'B0100');
      expect(res[2].system, 'Body');
      expect(res[3].code, 'U0120');
      expect(res[3].system, 'Network');
    });
  });

  group('M3 Challenge 3: DtcService Motion Interlock & Mode 04 Execution', () {
    final fakeProvider = _FakeObdProvider();
    final service = DtcService();

    test('3.1: Blocks Mode 04 when vehicle is moving (speed > 0, RPM = 0)', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: true,
        speed: 45,
        rpm: 0,
      );

      await expectLater(
        () => service.clearAllCodes(fakeProvider),
        throwsA(
          isA<DtcSafetyException>()
              .having((e) => e.speed, 'speed', 45)
              .having((e) => e.rpm, 'rpm', 0),
        ),
      );
      expect(fakeProvider.executeCallCount, 0);
    });

    test('3.2: Blocks Mode 04 when engine is running (speed = 0, RPM > 0)', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: true,
        speed: 0,
        rpm: 750,
      );

      await expectLater(
        () => service.clearAllCodes(fakeProvider),
        throwsA(
          isA<DtcSafetyException>()
              .having((e) => e.speed, 'speed', 0)
              .having((e) => e.rpm, 'rpm', 750),
        ),
      );
      expect(fakeProvider.executeCallCount, 0);
    });

    test('3.3: Allows Mode 04 when stationary with engine stopped (speed = 0, RPM = 0)', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: true,
        speed: 0,
        rpm: 0,
        executeResponse: '44\r>',
      );

      final result = await service.clearAllCodes(fakeProvider);
      expect(result, isTrue);
      expect(fakeProvider.executeCallCount, 1);
      expect(fakeProvider.lastExecutedCommand, '04');
    });

    test('3.4: allowWhileMoving override allows Mode 04 execution despite motion', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: true,
        speed: 100,
        rpm: 3000,
        executeResponse: '44\r>',
      );

      final result = await service.clearAllCodes(fakeProvider, allowWhileMoving: true);
      expect(result, isTrue);
      expect(fakeProvider.executeCallCount, 1);
    });

    test('3.5: Returns false when ECU returns error or negative acknowledgment', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: true,
        speed: 0,
        rpm: 0,
        executeResponse: 'CAN ERROR\r>',
      );

      final result = await service.clearAllCodes(fakeProvider);
      expect(result, isFalse);
    });

    test('3.6: Throws StateError when ECU is disconnected in real mode', () async {
      fakeProvider.setMockState(
        mode: ObdMode.real,
        isEcuConnected: false,
      );

      await expectLater(
        () => service.clearAllCodes(fakeProvider),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('M3 Challenge 4: Suzuki Swift M15A Powertrain DTC Definitions', () {
    test('4.1: Critical M15A VVT, Crankshaft, Camshaft, and Coolant sensors resolved with full details', () {
      final criticalCodes = ['P0011', 'P0012', 'P0117', 'P0335', 'P0340'];
      for (final code in criticalCodes) {
        final dtc = DtcDatabase.resolve(code);
        expect(dtc.code, code);
        expect(dtc.system, 'Powertrain');
        expect(dtc.description, isNotEmpty);
        expect(dtc.possibleCauses, isNotEmpty);
      }
    });

    test('4.2: Suzuki Swift O2 sensor heater and knock sensor definitions', () {
      final o2 = DtcDatabase.resolve('P0135');
      expect(o2.title, contains('Heater Circuit Malfunction'));

      final knock = DtcDatabase.resolve('P0325');
      expect(knock.title, contains('Knock Sensor'));
    });
  });
}
