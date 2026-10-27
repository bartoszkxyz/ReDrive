import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/obd/elm/elm_response.dart';
import 'package:obdrive/obd/elm/elm_response_parser.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/services/dtc/dtc_decoder.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';

import '../e2e/e2e_harness.dart';

List<String> d(String s, {bool pending = false, String? sid}) =>
    const DtcDecoder().decode(s, isPending: pending, serviceId: sid).map((c) => c.code).toList();

List<String> viaParser(String raw, {bool pending = false}) {
  final r = const ElmResponseParser().parse(raw);
  return const DtcDecoder().decode(r, isPending: pending).map((c) => c.code).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Decoder: basics / noise', () {
    test('empty & garbage', () {
      expect(d(''), isEmpty);
      expect(d('>'), isEmpty);
      expect(d('???'), isEmpty);
      expect(d('NO DATA'), isEmpty);
      expect(d('no data\r\r>'), isEmpty);
      expect(d('SEARCHING...\rNO DATA\r>'), isEmpty);
      expect(d('UNABLE TO CONNECT'), isEmpty);
      expect(d('CAN ERROR'), isEmpty);
      expect(d('BUS INIT: ...ERROR'), isEmpty);
    });
    test('non-string/non-response input', () {
      expect(const DtcDecoder().decode(null), isEmpty);
      expect(const DtcDecoder().decode(42), isEmpty);
    });
    test('zero DTCs variants', () {
      expect(d('43 00'), isEmpty);
      expect(d('43 00 00 00 00 00 00'), isEmpty);
      expect(d('7E8 02 43 00'), isEmpty);
      expect(d('7E8 02 43 00 00 00 00 00'), isEmpty);
      expect(d('4300'), isEmpty);
      expect(d('47 00', pending: true), isEmpty);
    });
    test('lowercase', () {
      expect(d('43 01 03 00'), ['P0300']);
      expect(d('7e8 06 43 02 01 33 c1 00'), ['P0133', 'U0100']);
      expect(d('4301033'), isA<List<String>>()); // must not throw
    });
    test('echo + searching + data', () {
      expect(d('03\rSEARCHING...\r43 01 03 00\r>'), ['P0300']);
      expect(viaParser('03\r\rSEARCHING...\r43 01 03 00\r\r>'), ['P0300']);
    });
    test('SEARCHING... then NO DATA via parser', () {
      expect(viaParser('SEARCHING...\rNO DATA\r>'), isEmpty);
    });
    test('padding 00 00 pairs after real DTCs', () {
      expect(d('43 02 01 33 01 71 00 00 00 00'.replaceFirst('02 01', '02 01')), ['P0133', 'P0171']);
      expect(d('43 01 33 01 71 00 00 00 00 00 00'), isA<List<String>>());
    });
    test('count smaller than payload (>N DTCs): limit to count', () {
      expect(d('43 01 01 33 01 71'), ['P0133']);
    });
    test('count larger than payload', () {
      expect(d('43 05 01 33'), ['P0133']);
    });
    test('truncated mid-pair does not fabricate codes', () {
      // count=2 but second DTC truncated to a single byte
      final r = d('43 02 01 33 02');
      expect(r, isNot(contains('P3302')), reason: 'even token count => count byte not recognised => bogus P3302');
    });
    test('odd-length compact hex', () {
      expect(d('430101330'), isA<List<String>>());
      expect(d('43010133'), isA<List<String>>());
    });
    test('non-hex tokens in data line', () {
      expect(d('43 01 ZZ 33'), isEmpty);
    });
    test('duplicate DTCs deduped', () {
      expect(d('43 02 01 33 01 33'), ['P0133']);
    });
    test('pending serviceId 47 ignores 43 lines', () {
      expect(d('43 01 01 33', sid: '47'), isEmpty);
      expect(d('47 01 01 33', sid: '47'), ['P0133']);
    });
  });

  group('Decoder: CAN / K-Line / ISO-TP', () {
    test('CAN header-included single frame', () {
      expect(d('7E8 06 43 02 01 33 04 20'), ['P0133', 'P0420']);
      expect(d('7E8 06 43 02 01 33 04 20 \r7E9 02 43 00'), ['P0133', 'P0420']);
    });
    test('CAN 29-bit header', () {
      expect(d('18DAF110 06 43 02 01 33 04 20'), ['P0133', 'P0420']);
    });
    test('K-Line header-included, no count byte, no checksum', () {
      expect(d('48 6B 11 43 01 33 04 20 00 00'), ['P0133', 'P0420']);
    });
    test('K-Line header-included WITH checksum byte (ISO 14230 / ISO 9141)', () {
      // 48 6B 11 43 | 01 33 | 04 20 | 00 00 | CS=0x5A  => odd tail, first DTC byte misread as count
      expect(d('48 6B 11 43 01 33 04 20 00 00 5A'), ['P0133', 'P0420']);
    });
    test('K-Line multi-ECU responses', () {
      expect(d('48 6B 10 43 01 33 00 00 00 00\r48 6B 11 43 04 20 00 00 00 00'), ['P0133', 'P0420']);
    });
    test('ELM indexed multi-line ISO-TP, with length line', () {
      expect(d('00A\r0: 43 04 01 33 01 71\r1: 04 20 00 00 00 00'), ['P0133', 'P0171', 'P0420']);
    });
    test('ELM indexed: P2xxx DTC as first bytes of continuation line', () {
      // P2100 = bytes 21 00 ; looks like ISO-TP sequence byte 0x21
      expect(d('0: 43 04 01 33 01 71\r1: 21 00 04 20 00 00'), ['P0133', 'P0171', 'P2100', 'P0420']);
    });
    test('ELM indexed: C0300 (bytes 43 00) at start of continuation line', () {
      expect(d('0: 43 04 01 33 01 71\r1: 43 00 04 20 00 00'), ['P0133', 'P0171', 'C0300', 'P0420']);
    });
    test('raw CAN ISO-TP FF/CF with 0x43 as DTC byte in CF', () {
      expect(d('7E8 10 0A 43 04 01 33 01 71\r7E8 21 43 00 04 20 00 00 00'),
          ['P0133', 'P0171', 'C0300', 'P0420']);
    });
    test('raw CAN ISO-TP FF/CF normal', () {
      expect(d('7E8 10 0A 43 04 01 33 01 71\r7E8 21 04 20 00 00 00 00 00'),
          ['P0133', 'P0171', 'P0420']);
    });
    test('raw CAN ISO-TP: P2xxx in CF after seq byte', () {
      expect(d('7E8 10 0A 43 04 01 33 01 71\r7E8 21 21 00 04 20 00 00 00'),
          ['P0133', 'P0171', 'P2100', 'P0420']);
    });
    test('multi-frame: second ECU (7E9) count must not truncate first ECU', () {
      expect(d('7E8 06 43 02 01 33 04 20\r7E9 04 43 01 03 00'), ['P0133', 'P0420', 'P0300']);
    });
    test('multi-frame: CF belonging to count of ECU1 does not leak across ECUs', () {
      // ECU 1 reports 1 DTC (full), ECU2 reports 2 DTC; limit tracking is global not per-ECU
      final r = d('7E8 04 43 01 01 33\r7E9 06 43 02 04 20 03 00');
      expect(r, ['P0133', 'P0420', 'P0300']);
    });
    test('DTC bytes all B/U/C prefixes', () {
      expect(d('43 03 41 23 81 23 C1 23'), ['C0123', 'B0123', 'U0123']);
    });
    test('hex-looking noise line containing "43" substring (compact path)', () {
      // e.g. adapter id / garbage; must not fabricate DTCs
      expect(d('ELM327 V1.5 4300'), isEmpty);
      expect(d('BUFFER FULL'), isEmpty);
    });
    test('large DTC list 20 codes via line-indexed frames', () {
      final codes = [for (var i = 0; i < 20; i++) 'P0${(100 + i).toRadixString(16).toUpperCase().padLeft(3, '0')}'];
      String bytes(String c) => c.substring(1);
      final flat = StringBuffer();
      for (final c in codes) {
        flat.write('${bytes(c).substring(0, 2)} ${bytes(c).substring(2)} ');
      }
      final all = flat.toString().trim().split(' ');
      final lines = <String>[];
      lines.add('0: 43 14 ${all.sublist(0, 4).join(' ')}');
      var idx = 1;
      for (var i = 4; i < all.length; i += 6) {
        lines.add('$idx: ${all.sublist(i, (i + 6).clamp(0, all.length)).join(' ')}');
        idx++;
      }
      final r = d(lines.join('\r'));
      expect(r.length, 20);
    });
  });

  group('Decoder: ElmResponse input', () {
    test('non-data response types return empty', () {
      expect(const DtcDecoder().decode(const ElmResponse(type: ElmResponseType.noData, raw: 'NO DATA')), isEmpty);
    });
    test('data response with empty lines', () {
      expect(const DtcDecoder().decode(const ElmResponse(type: ElmResponseType.data, raw: '')), isEmpty);
    });
  });

  group('DtcService Mode 04 interlock', () {
    late DtcService svc;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      svc = DtcService();
    });

    test('overrides speed:0 rpm:0 clears; sends exactly one 04', () async {
      final s = await _live(speed: 0, rpm: 0);
      expect(await svc.clearAllCodes(s.provider, speed: 0, rpm: 0), isTrue);
      expect(s.server.receivedCommands.where((c) => c == '04').length, 1);
      await _dispose(s);
    });

    test('speed:0 override but live RPM>0 (partial override, rpm null) must block', () async {
      final s = await _live(speed: 0, rpm: 0);
      s.server.rpm = 2000;
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        await svc.clearAllCodes(s.provider, speed: 0);
        fail('cleared with engine running (live rpm=${s.provider.data.rpm})');
      } on DtcSafetyException {
        // ok
      }
      expect(s.server.clearReceived, isFalse);
      await _dispose(s);
    });

    test('rpm:0 override but live speed>0 must block', () async {
      final s = await _live(speed: 0, rpm: 0);
      s.server.speed = 80;
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        await svc.clearAllCodes(s.provider, rpm: 0);
        fail('cleared while moving (live speed=${s.provider.data.speed})');
      } on DtcSafetyException {
        // ok
      }
      expect(s.server.clearReceived, isFalse);
      await _dispose(s);
    });

    test('nulls: live telemetry nonzero blocks', () async {
      final s = await _live(speed: 60, rpm: 1500);
      await Future<void>.delayed(const Duration(seconds: 3));
      await expectLater(svc.clearAllCodes(s.provider), throwsA(isA<DtcSafetyException>()));
      expect(s.server.clearReceived, isFalse);
      await _dispose(s);
    });

    test('nulls: telemetry not yet received (fail-open?) with moving car', () async {
      // Vehicle is moving but no telemetry sample has arrived yet: data.speed/rpm default 0.
      final s = await _live(speed: 90, rpm: 3000);
      final seen = s.provider.data.speed;
      final seenRpm = s.provider.data.rpm;
      if (seen == 0 && seenRpm == 0) {
        await expectLater(svc.clearAllCodes(s.provider), throwsA(isA<DtcSafetyException>()),
            reason: 'no telemetry yet (speed/rpm default 0) but car is moving; interlock fails open');
      }
      await _dispose(s);
    });

    test('stale telemetry: car starts moving right after last poll', () async {
      final s = await _live(speed: 0, rpm: 0);
      await Future<void>.delayed(const Duration(seconds: 2));
      s.server.speed = 100;
      s.server.rpm = 3000;
      // immediately attempt clear (cached data still 0/0)
      final staleSpeed = s.provider.data.speed;
      Object? err;
      try {
        await svc.clearAllCodes(s.provider);
      } catch (e) {
        err = e;
      }
      expect(staleSpeed, 0);
      expect(err, isA<DtcSafetyException>(),
          reason: 'interlock used cached telemetry; did not re-query live speed/rpm before sending 04');
      await _dispose(s);
    });

    test('negative override values must not bypass interlock', () async {
      final s = await _live(speed: 60, rpm: 1500);
      await Future<void>.delayed(const Duration(seconds: 2));
      await expectLater(svc.clearAllCodes(s.provider, speed: -1, rpm: -1), throwsA(isA<DtcSafetyException>()),
          reason: 'negative overrides (e.g. sentinel -1 for unknown) treated as stationary');
      await _dispose(s);
    });

    test('allowWhileMoving explicit true sends 04', () async {
      final s = await _live(speed: 60, rpm: 1500);
      expect(await svc.clearAllCodes(s.provider, allowWhileMoving: true, speed: 60, rpm: 1500), isTrue);
      await _dispose(s);
    });

    test('unconfirmed 04 (server does not ack) returns false, keeps cache', () async {
      final s = await _live(speed: 0, rpm: 0);
      await svc.scanAllCodes(s.provider);
      final before = svc.lastScannedCodes.length;
      await s.connection.disconnect();
      final r = await svc.clearAllCodes(s.provider, speed: 0, rpm: 0).timeout(const Duration(seconds: 40),
          onTimeout: () => throw StateError('clearAllCodes hung > 40s with dead link'));
      expect(r, isFalse);
      expect(svc.lastScannedCodes.length, before);
      await _dispose(s);
    });

    test('concurrent clear calls send at most one 04', () async {
      final s = await _live(speed: 0, rpm: 0);
      final res = await Future.wait([
        svc.clearAllCodes(s.provider, speed: 0, rpm: 0),
        svc.clearAllCodes(s.provider, speed: 0, rpm: 0),
        svc.clearAllCodes(s.provider, speed: 0, rpm: 0),
      ]);
      expect(res.every((e) => e), isTrue);
      expect(s.server.receivedCommands.where((c) => c == '04').length, 1,
          reason: 'concurrent clears each transmit Mode 04 (no in-flight guard)');
      await _dispose(s);
    });

    test('concurrent scan during clear: cache consistent (empty after clear)', () async {
      final s = await _live(speed: 0, rpm: 0, stored: ['P0300']);
      final f = await Future.wait([
        svc.clearAllCodes(s.provider, speed: 0, rpm: 0),
        svc.scanAllCodes(s.provider),
      ]);
      expect(f[0], isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final post = await svc.scanAllCodes(s.provider);
      expect(post, isEmpty);
      expect(svc.lastScannedCodes, isEmpty);
      await _dispose(s);
    });

    test('concurrent clear (blocked) + clear (allowed) only allowed one sends 04', () async {
      final s = await _live(speed: 60, rpm: 1500);
      await Future<void>.delayed(const Duration(seconds: 2));
      final a = svc.clearAllCodes(s.provider);
      final b = svc.clearAllCodes(s.provider, allowWhileMoving: true);
      await expectLater(a, throwsA(isA<DtcSafetyException>()));
      expect(await b, isTrue);
      expect(s.server.receivedCommands.where((c) => c == '04').length, 1);
      await _dispose(s);
    });
  });
}

typedef _S = ({ObdProvider provider, TcpObdConnection connection, MockElmTcpServer server});

Future<_S> _live({int speed = 0, int rpm = 0, List<String> stored = const ['P0300']}) async {
  final server = MockElmTcpServer()
    ..speed = speed
    ..rpm = rpm
    ..storedDtcs = List.from(stored)
    ..pendingDtcs = [];
  await server.start();
  final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
  await connection.connect();
  final provider = ObdProvider();
  provider.attachConnection(connection);
  unawaited(provider.startRealMode());
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline) && !provider.isEcuConnected) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!provider.isEcuConnected) throw TimeoutException('no connect');
  return (provider: provider, connection: connection, server: server);
}

Future<void> _dispose(_S s) async {
  await s.provider.stopRealMode();
  s.provider.dispose();
  await s.connection.disconnect();
  await s.server.stop();
}
