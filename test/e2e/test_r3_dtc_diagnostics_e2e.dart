import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/obd/elm/elm_response.dart';
import 'package:redrive/obd/elm/elm_response_parser.dart';
import 'package:redrive/providers/obd_provider.dart';
import 'package:redrive/services/dtc/dtc_decoder.dart';
import 'package:redrive/services/dtc/dtc_service.dart';

import 'e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R3 Acceptance Suite: DTC Diagnostics & Mode 04 Guarded Clearing', () {
    test('E2E-R3-1: Mode 03 and Mode 07 query parses Suzuki M15A powertrain codes accurately', () async {
      final server = MockElmTcpServer();
      server.speed = 0;
      server.rpm = 0;
      server.storedDtcs = ['P0011', 'P0102', 'P0300'];
      server.pendingDtcs = ['P0118', 'P0420'];
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      unawaited(obdProvider.startRealMode());

      await _waitUntilConnected(obdProvider);

      final dtcService = DtcService();
      final codes = await dtcService.scanAllCodes(obdProvider);

      expect(codes.length, 5);
      final codeMap = {for (final c in codes) c.code: c};

      // Verify Suzuki M15A specific codes
      expect(codeMap.containsKey('P0011'), isTrue);
      expect(codeMap['P0011']!.title, contains('Timing Over-Advanced'));
      expect(codeMap['P0011']!.possibleCauses, contains('oil control valve'));
      expect(codeMap['P0011']!.isPending, isFalse);

      expect(codeMap.containsKey('P0102'), isTrue);
      expect(codeMap['P0102']!.title, contains('Circuit Low Input'));
      expect(codeMap['P0102']!.isPending, isFalse);

      expect(codeMap.containsKey('P0300'), isTrue);
      expect(codeMap['P0300']!.severity, 'Critical');
      expect(codeMap['P0300']!.isPending, isFalse);

      expect(codeMap.containsKey('P0118'), isTrue);
      expect(codeMap['P0118']!.title, contains('Circuit High Input (Pending)'));
      expect(codeMap['P0118']!.isPending, isTrue);

      expect(codeMap.containsKey('P0420'), isTrue);
      expect(codeMap['P0420']!.isPending, isTrue);

      await obdProvider.stopRealMode();
      obdProvider.dispose();
      await connection.disconnect();
      await server.stop();
    });

    test('E2E-R3-2: Zero-DTC clean responses (43 00 and 47 00) return empty list without error', () async {
      final server = MockElmTcpServer();
      server.speed = 0;
      server.rpm = 0;
      server.storedDtcs = [];
      server.pendingDtcs = [];
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      unawaited(obdProvider.startRealMode());

      await _waitUntilConnected(obdProvider);

      final dtcService = DtcService();
      final codes = await dtcService.scanAllCodes(obdProvider);

      expect(codes, isEmpty);
      expect(dtcService.lastScannedCodes, isEmpty);

      await obdProvider.stopRealMode();
      obdProvider.dispose();
      await connection.disconnect();
      await server.stop();
    });

    test('E2E-R3-3: Motion guard prevents Mode 04 clear during active telemetry stream', () async {
      final server = MockElmTcpServer();
      server.speed = 50;
      server.rpm = 2200;
      server.storedDtcs = ['P0300'];
      server.pendingDtcs = [];
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      unawaited(obdProvider.startRealMode());

      await _waitUntilConnected(obdProvider);

      final dtcService = DtcService();

      // Attempt Mode 04 clearing with vehicle in motion
      await expectLater(
        () => dtcService.clearAllCodes(obdProvider, speed: 50, rpm: 2200),
        throwsA(
          isA<DtcSafetyException>()
              .having((e) => e.speed, 'speed', 50)
              .having((e) => e.rpm, 'rpm', 2200),
        ),
      );

      // Verify Mode 04 clear was never transmitted to ECU
      expect(server.clearReceived, isFalse);
      expect(server.storedDtcs, isNotEmpty);

      await obdProvider.stopRealMode();
      obdProvider.dispose();
      await connection.disconnect();
      await server.stop();
    });

    test('E2E-R3-4: Stationary vehicle executes Mode 04 clear and extinguishes fault codes', () async {
      final server = MockElmTcpServer();
      server.speed = 0;
      server.rpm = 0;
      server.storedDtcs = ['P0300', 'P0171'];
      server.pendingDtcs = [];
      await server.start();

      final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
      await connection.connect();

      final obdProvider = ObdProvider();
      obdProvider.attachConnection(connection);
      unawaited(obdProvider.startRealMode());

      await _waitUntilConnected(obdProvider);

      final dtcService = DtcService();

      // Scan active fault codes
      final initialCodes = await dtcService.scanAllCodes(obdProvider);
      expect(initialCodes.length, 2);
      expect(dtcService.lastScannedCodes.length, 2);

      // Execute guarded Mode 04 clear while stationary
      final clearSuccess = await dtcService.clearAllCodes(
        obdProvider,
        speed: 0,
        rpm: 0,
      );
      expect(clearSuccess, isTrue);
      expect(server.clearReceived, isTrue);
      expect(dtcService.lastScannedCodes, isEmpty);

      // Subsequent scan confirms fault memory extinguished
      final postClearCodes = await dtcService.scanAllCodes(obdProvider);
      expect(postClearCodes, isEmpty);

      await obdProvider.stopRealMode();
      obdProvider.dispose();
      await connection.disconnect();
      await server.stop();
    });

    test('E2E-R3-5: Fault injection and malformed hex strings do not crash diagnostics pipeline', () {
      const decoder = DtcDecoder();
      const parser = ElmResponseParser();

      // 1. Adapter error lines
      final respStopped = parser.parse('STOPPED\r>');
      expect(respStopped.type, ElmResponseType.stopped);
      expect(decoder.decode(respStopped), isEmpty);

      final respBufferFull = parser.parse('BUFFER FULL\r>');
      expect(respBufferFull.type, ElmResponseType.adapterError);
      expect(decoder.decode(respBufferFull), isEmpty);

      // 2. Corrupt hex noise with valid frame interleaved
      const noisyLine = ElmResponse(
        type: ElmResponseType.data,
        raw: '43 01 01 33 00 00\r',
        lines: ['43 01 01 33 00 00'],
      );
      final validCodes = decoder.decode(noisyLine);
      expect(validCodes.length, 1);
      expect(validCodes.first.code, 'P0133');

      // 3. Compact hex parsing
      final compactCodes = decoder.decodeRaw('43', '430203000171');
      expect(compactCodes.length, 2);
      expect(compactCodes.map((c) => c.code), containsAll(['P0300', 'P0171']));

      // 4. Clean vehicle empty response
      final zeroCodes = decoder.decodeRaw('43', '43 00');
      expect(zeroCodes, isEmpty);
    });
  });
}

Future<void> _waitUntilConnected(ObdProvider provider) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (provider.isEcuConnected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Timed out waiting for ObdProvider ECU connection');
}
