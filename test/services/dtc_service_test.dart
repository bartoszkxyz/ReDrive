import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';

import '../e2e/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DtcService Unit Tests', () {
    late DtcService dtcService;

    setUp(() {
      dtcService = DtcService();
    });

    group('scanAllCodes', () {
      test('throws StateError when ECU is disconnected and not demo mode', () async {
        final obd = ObdProvider();
        expect(obd.isEcuConnected, isFalse);
        expect(() => dtcService.scanAllCodes(obd), throwsA(isA<StateError>()));
        obd.dispose();
      });

      test('returns demo DTCs in demo mode and updates lastScannedCodes', () async {
        final obd = ObdProvider();
        await obd.startDemoMode();
        final codes = await dtcService.scanAllCodes(obd);
        expect(codes.length, 3);
        expect(codes.map((c) => c.code), containsAll(['P0300', 'P0171', 'P0420']));
        expect(dtcService.lastScannedCodes.length, 3);

        await obd.stopDemoMode();
        obd.dispose();
      });

      test('queries Mode 03 and Mode 07 on real ECU connection', () async {
        final setup = await _createLiveRealProvider(
          storedDtcs: ['P0300', 'P0171'],
          pendingDtcs: ['P0420'],
        );

        final codes = await dtcService.scanAllCodes(setup.provider);
        expect(codes.length, 3);
        expect(codes.map((c) => c.code), containsAll(['P0300', 'P0171', 'P0420']));
        expect(dtcService.lastScannedCodes.length, 3);

        await _disposeLiveRealProvider(setup);
      });
    });

    group('clearAllCodes - Motion Safety Interlock', () {
      test('throws StateError when ECU is disconnected in real mode', () async {
        final obd = ObdProvider();
        expect(obd.isEcuConnected, isFalse);
        expect(
          () => dtcService.clearAllCodes(obd),
          throwsA(isA<StateError>()),
        );
        obd.dispose();
      });

      test('clears simulated codes in demo mode and returns true', () async {
        final obd = ObdProvider();
        await obd.startDemoMode();

        final initialCodes = await dtcService.scanAllCodes(obd);
        expect(initialCodes, isNotEmpty);
        expect(dtcService.lastScannedCodes, isNotEmpty);

        final success = await dtcService.clearAllCodes(obd);
        expect(success, isTrue);
        expect(dtcService.lastScannedCodes, isEmpty);

        final postClearCodes = await dtcService.scanAllCodes(obd);
        expect(postClearCodes, isEmpty);

        await obd.stopDemoMode();
        obd.dispose();
      });

      test('blocks clearing and throws DtcSafetyException when vehicle speed > 0', () async {
        final setup = await _createLiveRealProvider(speed: 45, rpm: 0);

        try {
          await dtcService.clearAllCodes(setup.provider, speed: 45, rpm: 0);
          fail('Should have thrown DtcSafetyException');
        } on DtcSafetyException catch (e) {
          expect(e.speed, 45);
          expect(e.rpm, 0);
          expect(e.message, contains('Vehicle motion safety check'));
        }

        await _disposeLiveRealProvider(setup);
      });

      test('blocks clearing and throws DtcSafetyException when engine RPM > 0', () async {
        final setup = await _createLiveRealProvider(speed: 0, rpm: 850);

        try {
          await dtcService.clearAllCodes(setup.provider, speed: 0, rpm: 850);
          fail('Should have thrown DtcSafetyException');
        } on DtcSafetyException catch (e) {
          expect(e.speed, 0);
          expect(e.rpm, 850);
          expect(e.toString(), contains('speed: 0 km/h, RPM: 850'));
        }

        await _disposeLiveRealProvider(setup);
      });

      test('blocks clearing and throws DtcSafetyException when both speed > 0 and RPM > 0', () async {
        final setup = await _createLiveRealProvider(speed: 60, rpm: 2200);

        await expectLater(
          () => dtcService.clearAllCodes(setup.provider, speed: 60, rpm: 2200),
          throwsA(
            isA<DtcSafetyException>()
                .having((e) => e.speed, 'speed', 60)
                .having((e) => e.rpm, 'rpm', 2200),
          ),
        );

        await _disposeLiveRealProvider(setup);
      });

      test('allows clearing while moving if allowWhileMoving override is true', () async {
        final setup = await _createLiveRealProvider(
          speed: 70,
          rpm: 2500,
          storedDtcs: ['P0300'],
        );

        final success = await dtcService.clearAllCodes(
          setup.provider,
          allowWhileMoving: true,
          speed: 70,
          rpm: 2500,
        );
        expect(success, isTrue);
        expect(setup.server.clearReceived, isTrue);
        expect(setup.server.storedDtcs, isEmpty);

        await _disposeLiveRealProvider(setup);
      });

      test('allows clearing when stationary (speed == 0 && rpm == 0)', () async {
        final setup = await _createLiveRealProvider(
          speed: 0,
          rpm: 0,
          storedDtcs: ['P0300'],
        );

        final success = await dtcService.clearAllCodes(
          setup.provider,
          speed: 0,
          rpm: 0,
        );
        expect(success, isTrue);
        expect(setup.server.clearReceived, isTrue);
        expect(setup.server.storedDtcs, isEmpty);

        await _disposeLiveRealProvider(setup);
      });

      test('clears cached lastScannedCodes upon successful Mode 04 clear', () async {
        final setup = await _createLiveRealProvider(
          speed: 0,
          rpm: 0,
          storedDtcs: ['P0300'],
        );

        final scanned = await dtcService.scanAllCodes(setup.provider);
        expect(scanned.length, 1);
        expect(dtcService.lastScannedCodes.length, 1);

        final cleared = await dtcService.clearAllCodes(setup.provider, speed: 0, rpm: 0);
        expect(cleared, isTrue);
        expect(dtcService.lastScannedCodes, isEmpty);

        final postClear = await dtcService.scanAllCodes(setup.provider);
        expect(postClear, isEmpty);

        await _disposeLiveRealProvider(setup);
      });

      test('resetDemoCodes resets demo state and clears cached codes', () {
        dtcService.resetDemoCodes();
        expect(dtcService.lastScannedCodes, isEmpty);
      });
    });
  });
}

Future<({ObdProvider provider, TcpObdConnection connection, MockElmTcpServer server})>
    _createLiveRealProvider({
  int speed = 0,
  int rpm = 0,
  List<String> storedDtcs = const ['P0300'],
  List<String> pendingDtcs = const [],
}) async {
  final server = MockElmTcpServer();
  server.speed = speed;
  server.rpm = rpm;
  server.storedDtcs = List.from(storedDtcs);
  server.pendingDtcs = List.from(pendingDtcs);
  await server.start();

  final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
  await connection.connect();

  final provider = ObdProvider();
  provider.attachConnection(connection);
  unawaited(provider.startRealMode());

  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (provider.isEcuConnected) break;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  if (!provider.isEcuConnected) {
    throw TimeoutException('Provider failed to connect to mock server');
  }

  return (provider: provider, connection: connection, server: server);
}

Future<void> _disposeLiveRealProvider(({
  ObdProvider provider,
  TcpObdConnection connection,
  MockElmTcpServer server,
}) setup) async {
  await setup.provider.stopRealMode();
  setup.provider.dispose();
  await setup.connection.disconnect();
  await setup.server.stop();
}
