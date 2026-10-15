import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/dtc/dtc_decoder.dart';
import 'package:redrive/services/dtc/dtc_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../e2e/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const decoder = DtcDecoder();

  group('Challenger Gen2: Framing Edge Cases', () {
    test('ISO-TP continuation lines with P2xxx codes (0x20-0x2F as DTC high byte)', () {
      // Line 0: Mode 43, count 4, P0133 (01 33), P0171 (01 71)
      // Line 1: P2100 (21 00), P2096 (20 96), P2195 (21 95)
      // Line-indexed ELM format:
      final rawIndexed = '0: 43 05 01 33 01 71\r'
          '1: 21 00 20 96 21 95\r>';
      final resIndexed = decoder.decode(rawIndexed);
      final codesIndexed = resIndexed.map((c) => c.code).toList();
      expect(codesIndexed, containsAll(['P0133', 'P0171', 'P2100', 'P2096', 'P2195']));

      // Raw CAN format with ISO-TP PCI:
      // First frame (10 0C = 12 bytes), CF seq 1 (21 ...), CF seq 2 (22 ...)
      // P2101 (21 01) immediately following seq byte 21
      final rawCan = '7E8 10 0C 43 05 01 33 01 71\r'
          '7E8 21 21 01 20 96 21 95 00\r'
          '7E8 22 00 00 00 00 00 00 00\r>';
      final resCan = decoder.decode(rawCan);
      final codesCan = resCan.map((c) => c.code).toList();
      expect(codesCan, containsAll(['P0133', 'P0171', 'P2101', 'P2096', 'P2195']));
    });

    test('ISO-TP continuation lines containing 0x43 embedded in data', () {
      // 0x43 in data byte represents Chassis DTC C03xx:
      // C0300 is hex bytes 43 00
      // In indexed frame 1: '1: 43 00 04 20' -> should NOT be treated as a new header
      final rawIndexed = '0: 43 04 01 33 01 71\r'
          '1: 43 00 04 20 00 00\r>';
      final res = decoder.decode(rawIndexed).map((c) => c.code).toList();
      expect(res, ['P0133', 'P0171', 'C0300', 'P0420']);

      // In raw CAN consecutive frame:
      final rawCan = '7E8 10 0A 43 04 01 33 01 71\r'
          '7E8 21 43 00 04 20 00 00 00\r>';
      final resCan = decoder.decode(rawCan).map((c) => c.code).toList();
      expect(resCan, ['P0133', 'P0171', 'C0300', 'P0420']);
    });

    test('K-Line header + checksum payloads with odd and even lengths', () {
      // Header: 48 6B 11 43. Real DTCs: 01 33 (P0133), 04 20 (P0420).
      // Padding: 00 00. Checksum: 5A.
      // Total tokens: 11. Rest after 48 6B 11 43 is 7 tokens (odd).
      final rawOddWithChecksum = '48 6B 11 43 01 33 04 20 00 00 5A';
      final resOdd = decoder.decode(rawOddWithChecksum).map((c) => c.code).toList();
      expect(resOdd, ['P0133', 'P0420']);

      // Without checksum: 48 6B 11 43 01 33 04 20 00 00 (even rest length = 6)
      final rawEven = '48 6B 11 43 01 33 04 20 00 00';
      final resEven = decoder.decode(rawEven).map((c) => c.code).toList();
      expect(resEven, ['P0133', 'P0420']);

      // Single DTC on K-Line with checksum: 48 6B 11 43 03 00 E4
      final rawSingleWithCs = '48 6B 11 43 03 00 E4';
      final resSingle = decoder.decode(rawSingleWithCs).map((c) => c.code).toList();
      expect(resSingle, ['P0300']);
    });

    test('Count byte parity bounds and padding truncation', () {
      // Count byte = 1, but followed by 3 DTCs and padding:
      final countTruncated = decoder.decode('43 01 01 33 01 71 04 20 00 00');
      expect(countTruncated.map((c) => c.code).toList(), ['P0133']);

      // Count byte = 4, but payload only contains 2 DTCs:
      final countExcess = decoder.decode('43 04 01 33 01 71');
      expect(countExcess.map((c) => c.code).toList(), ['P0133', 'P0171']);

      // 00 00 pairs anywhere must never decode into P0000:
      final paddingOnly = decoder.decode('43 00 00 00 00 00');
      expect(paddingOnly, isEmpty);

      final trailingPadding = decoder.decode('43 02 01 33 01 71 00 00 00 00');
      expect(trailingPadding.map((c) => c.code).toList(), containsAll(['P0133', 'P0171']));
      expect(trailingPadding.any((c) => c.code == 'P0000'), isFalse);
    });

    test('All prefix categories bitwise decoding: P, C, B, U', () {
      // Bits 7-6:
      // 00 = P (e.g. 01 33 -> P0133)
      // 01 = C (e.g. 41 33 -> C0133)
      // 10 = B (e.g. 81 33 -> B0133)
      // 11 = U (e.g. C1 33 -> U0133)
      final allPrefixes = decoder.decode('43 04 01 33 41 33 81 33 C1 33');
      final codes = allPrefixes.map((c) => c.code).toList();
      expect(codes, ['P0133', 'C0133', 'B0133', 'U0133']);
    });
  });

  group('Challenger Gen2: Motion Interlock Robustness', () {
    late DtcService dtcService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dtcService = DtcService();
    });

    test('negative overrides (speed: -1, rpm: -1, or either negative) throw DtcSafetyException', () async {
      final s = await _setupLiveServer(speed: 0, rpm: 0);

      // speed: -1, rpm: 0
      await expectLater(
        dtcService.clearAllCodes(s.provider, speed: -1, rpm: 0),
        throwsA(isA<DtcSafetyException>()),
      );
      expect(s.server.clearReceived, isFalse);

      // speed: 0, rpm: -500
      await expectLater(
        dtcService.clearAllCodes(s.provider, speed: 0, rpm: -500),
        throwsA(isA<DtcSafetyException>()),
      );
      expect(s.server.clearReceived, isFalse);

      // speed: -100, rpm: -100
      await expectLater(
        dtcService.clearAllCodes(s.provider, speed: -100, rpm: -100),
        throwsA(isA<DtcSafetyException>()),
      );
      expect(s.server.clearReceived, isFalse);

      await _teardownLiveServer(s);
    });

    test('live telemetry speed > 0 or rpm > 0 throws DtcSafetyException without manual override', () async {
      // Moving at 45 km/h, engine running at 1800 rpm
      final s = await _setupLiveServer(speed: 45, rpm: 1800);

      await expectLater(
        dtcService.clearAllCodes(s.provider),
        throwsA(isA<DtcSafetyException>()
            .having((e) => e.speed, 'speed', 45)
            .having((e) => e.rpm, 'rpm', 1800)),
      );
      expect(s.server.clearReceived, isFalse);

      await _teardownLiveServer(s);
    });

    test('fail-closed: unparseable or error response during live speed/rpm query returns false and does not send 04', () async {
      final badServer = _FailingSpeedRpmServer();
      await badServer.start();

      final conn = TcpObdConnection(host: '127.0.0.1', port: badServer.port);
      await conn.connect();
      final provider = ObdProvider();
      provider.attachConnection(conn);
      unawaited(provider.startRealMode());

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline) && !provider.isEcuConnected) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(provider.isEcuConnected, isTrue);

      // Call clearAllCodes - server responds with NO DATA / error to 010D
      final result = await dtcService.clearAllCodes(provider);
      expect(result, isFalse, reason: 'Fail closed: cannot verify stationary, must return false');
      expect(badServer.receivedCommands, isNot(contains('04')));

      await provider.stopRealMode();
      provider.dispose();
      await conn.disconnect();
      await badServer.stop();
    });

    test('concurrent clear calls deduplicate execution and send Mode 04 exactly once', () async {
      final s = await _setupLiveServer(speed: 0, rpm: 0);

      final results = await Future.wait([
        dtcService.clearAllCodes(s.provider),
        dtcService.clearAllCodes(s.provider),
        dtcService.clearAllCodes(s.provider),
        dtcService.clearAllCodes(s.provider),
        dtcService.clearAllCodes(s.provider),
      ]);

      expect(results.every((r) => r == true), isTrue);
      final count04 = s.server.receivedCommands.where((cmd) => cmd == '04').length;
      expect(count04, 1, reason: 'In-flight operation guard must transmit Mode 04 exactly once');

      await _teardownLiveServer(s);
    });
  });
}

typedef _ServerSetup = ({ObdProvider provider, TcpObdConnection connection, MockElmTcpServer server});

Future<_ServerSetup> _setupLiveServer({int speed = 0, int rpm = 0}) async {
  final server = MockElmTcpServer()
    ..speed = speed
    ..rpm = rpm
    ..storedDtcs = ['P0300']
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
  if (!provider.isEcuConnected) throw TimeoutException('ECU connection failed');
  return (provider: provider, connection: connection, server: server);
}

Future<void> _teardownLiveServer(_ServerSetup s) async {
  await s.provider.stopRealMode();
  s.provider.dispose();
  await s.connection.disconnect();
  await s.server.stop();
}

class _FailingSpeedRpmServer {
  ServerSocket? _server;
  Socket? _client;
  final List<String> receivedCommands = [];
  String _rx = '';

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _client = socket;
      socket.listen((data) {
        _rx += String.fromCharCodes(data);
        while (_rx.contains('\r') || _rx.contains('\n')) {
          final idx = _rx.indexOf(RegExp(r'[\r\n]'));
          final cmd = _rx.substring(0, idx).trim().toUpperCase();
          _rx = _rx.substring(idx + 1);
          if (cmd.isEmpty) continue;
          receivedCommands.add(cmd);
          void reply(String res) {
            try {
              socket.add(res.codeUnits);
            } catch (_) {}
          }

          if (cmd == 'ATZ' || cmd == 'ATWS') {
            reply('ELM327 v2.3\r\n>');
          } else if (cmd == 'ATRV') {
            reply('14.1V\r\n>');
          } else if (cmd == 'ATDP') {
            reply('ISO 14230-4 (KWP FAST)\r\n>');
          } else if (cmd == 'ATDPN') {
            reply('A5\r\n>');
          } else if (cmd.startsWith('AT')) {
            reply('OK\r\n>');
          } else if (cmd == '0100') {
            reply('SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>');
          } else if (cmd == '0120') {
            reply('41 20 80 02 02 01\r\n>');
          } else if (cmd == '0140') {
            reply('41 40 44 04 00 00\r\n>');
          } else if (cmd == '010D') {
            // Live Speed fails with NO DATA
            reply('NO DATA\r\n>');
          } else if (cmd == '010C') {
            // Live RPM fails with NO DATA
            reply('NO DATA\r\n>');
          } else if (cmd == '04') {
            reply('44\r\n>');
          } else {
            reply('NO DATA\r\n>');
          }
        }
      });
    });
  }

  Future<void> stop() async {
    await _client?.close();
    await _server?.close();
  }
}
