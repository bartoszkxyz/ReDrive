import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:obdrive/obd/connection/tcp_obd_connection.dart';
import 'package:obdrive/obd/pid/pid_key.dart';
import 'package:obdrive/obd/polling/polling_controller.dart';
import 'package:obdrive/providers/obd_provider.dart';
import 'package:obdrive/services/dtc/dtc_service.dart';

import '../e2e/e2e_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Empirical Adversarial Challenges: Vehicle Motion Safety Interlock & Mode 04 Lifecycle', () {
    late DtcService dtcService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dtcService = DtcService();
    });

    group('1. Moving Vehicle in Real Mode (speed > 0, rpm == 0)', () {
      final testSpeeds = [1, 10, 50, 120, 250];

      for (final speed in testSpeeds) {
        test('strictly throws DtcSafetyException and prevents transmitting "04" at $speed km/h', () async {
          final setup = await _createLiveRealProvider(
            speed: speed,
            rpm: 0,
            storedDtcs: ['P0300'],
          );

          // Populate lastScannedCodes
          final initialCodes = await dtcService.scanAllCodes(setup.provider);
          expect(initialCodes, isNotEmpty);
          expect(dtcService.lastScannedCodes, isNotEmpty);

          // Pre-clear state verification
          expect(setup.server.clearReceived, isFalse);
          expect(setup.server.receivedCommands, isNot(contains('04')));

          // Attempt clear with speed > 0
          try {
            await dtcService.clearAllCodes(setup.provider, speed: speed, rpm: 0);
            fail('Should have thrown DtcSafetyException at speed $speed km/h');
          } on DtcSafetyException catch (e) {
            expect(e.speed, speed);
            expect(e.rpm, 0);
            expect(e.message, contains('Vehicle motion safety check'));
            expect(e.toString(), contains('speed: $speed km/h, RPM: 0'));
          }

          // Strict verification: command '04' was NEVER transmitted over socket
          expect(setup.server.clearReceived, isFalse);
          expect(setup.server.receivedCommands, isNot(contains('04')));
          expect(setup.server.storedDtcs, contains('P0300'));

          // Cached codes must NOT be wiped when clear fails
          expect(dtcService.lastScannedCodes, isNotEmpty);

          await _disposeLiveRealProvider(setup);
        });
      }
    });

    group('2. Running Engine in Real Mode (speed == 0, rpm > 0)', () {
      final testRpms = [1, 650, 800, 1500, 2500, 6800];

      for (final rpm in testRpms) {
        test('strictly throws DtcSafetyException and prevents transmitting "04" at $rpm RPM', () async {
          final setup = await _createLiveRealProvider(
            speed: 0,
            rpm: rpm,
            storedDtcs: ['P0171'],
          );

          await dtcService.scanAllCodes(setup.provider);
          expect(dtcService.lastScannedCodes, isNotEmpty);

          expect(setup.server.clearReceived, isFalse);
          expect(setup.server.receivedCommands, isNot(contains('04')));

          try {
            await dtcService.clearAllCodes(setup.provider, speed: 0, rpm: rpm);
            fail('Should have thrown DtcSafetyException at RPM $rpm');
          } on DtcSafetyException catch (e) {
            expect(e.speed, 0);
            expect(e.rpm, rpm);
            expect(e.message, contains('Vehicle motion safety check'));
            expect(e.toString(), contains('speed: 0 km/h, RPM: $rpm'));
          }

          expect(setup.server.clearReceived, isFalse);
          expect(setup.server.receivedCommands, isNot(contains('04')));
          expect(setup.server.storedDtcs, contains('P0171'));
          expect(dtcService.lastScannedCodes, isNotEmpty);

          await _disposeLiveRealProvider(setup);
        });
      }
    });

    group('3. Combined Vehicle Motion (speed > 0 and rpm > 0)', () {
      final testCombos = [
        (speed: 10, rpm: 800),
        (speed: 60, rpm: 2200),
        (speed: 140, rpm: 4500),
      ];

      for (final combo in testCombos) {
        test('blocks clearing and prevents transmitting "04" at ${combo.speed} km/h and ${combo.rpm} RPM', () async {
          final setup = await _createLiveRealProvider(
            speed: combo.speed,
            rpm: combo.rpm,
            storedDtcs: ['P0300'],
          );

          await expectLater(
            () => dtcService.clearAllCodes(
              setup.provider,
              speed: combo.speed,
              rpm: combo.rpm,
            ),
            throwsA(
              isA<DtcSafetyException>()
                  .having((e) => e.speed, 'speed', combo.speed)
                  .having((e) => e.rpm, 'rpm', combo.rpm),
            ),
          );

          expect(setup.server.clearReceived, isFalse);
          expect(setup.server.receivedCommands, isNot(contains('04')));

          await _disposeLiveRealProvider(setup);
        });
      }
    });

    group('4. Stationary Vehicle with Engine Off (speed == 0 && rpm == 0)', () {
      test('transmits "04", parses "44", clears cached codes, and returns true', () async {
        final setup = await _createLiveRealProvider(
          speed: 0,
          rpm: 0,
          storedDtcs: ['P0300', 'P0171'],
        );

        final initialCodes = await dtcService.scanAllCodes(setup.provider);
        expect(initialCodes.length, 2);
        expect(dtcService.lastScannedCodes.length, 2);

        final clearSuccess = await dtcService.clearAllCodes(
          setup.provider,
          speed: 0,
          rpm: 0,
        );

        expect(clearSuccess, isTrue);
        expect(setup.server.clearReceived, isTrue);
        expect(setup.server.receivedCommands, contains('04'));
        expect(setup.server.storedDtcs, isEmpty);
        expect(dtcService.lastScannedCodes, isEmpty);

        final postClearCodes = await dtcService.scanAllCodes(setup.provider);
        expect(postClearCodes, isEmpty);

        await _disposeLiveRealProvider(setup);
      });

      test('rejects bare "OK" as Mode 04 acknowledgment (only a 44 positive response counts)', () async {
        final customServer = _CustomMode04Server(mode04Response: 'OK\r\n>');
        await customServer.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: customServer.port);
        await connection.connect();

        final provider = ObdProvider();
        provider.attachConnection(connection);
        unawaited(provider.startRealMode());

        await _waitUntilConnected(provider);

        final success = await dtcService.clearAllCodes(provider, speed: 0, rpm: 0);
        expect(success, isFalse);
        expect(customServer.receivedCommands, contains('04'));
        expect(dtcService.lastScannedCodes, isEmpty);

        await provider.stopRealMode();
        provider.dispose();
        await connection.disconnect();
        await customServer.stop();
      });

      test('returns false and retains cached codes when ECU responds with failure/malformed response', () async {
        final customServer = _CustomMode04Server(mode04Response: '7F 04 22\r\n>');
        await customServer.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: customServer.port);
        await connection.connect();

        final provider = ObdProvider();
        provider.attachConnection(connection);
        unawaited(provider.startRealMode());

        await _waitUntilConnected(provider);

        // Pre-populate lastScannedCodes
        final codes = await dtcService.scanAllCodes(provider);
        expect(codes.length, 1);
        expect(dtcService.lastScannedCodes.length, 1);

        final success = await dtcService.clearAllCodes(provider, speed: 0, rpm: 0);
        expect(success, isFalse);
        expect(customServer.receivedCommands, contains('04'));
        // Cached codes must NOT be cleared on failure
        expect(dtcService.lastScannedCodes.length, 1);

        await provider.stopRealMode();
        provider.dispose();
        await connection.disconnect();
        await customServer.stop();
      });
    });

    group('5. Testing Override (allowWhileMoving: true)', () {
      test('allows clearing even if speed > 0 and rpm > 0', () async {
        final setup = await _createLiveRealProvider(
          speed: 120,
          rpm: 3500,
          storedDtcs: ['P0300'],
        );

        final initialCodes = await dtcService.scanAllCodes(setup.provider);
        expect(initialCodes, isNotEmpty);

        final success = await dtcService.clearAllCodes(
          setup.provider,
          allowWhileMoving: true,
          speed: 120,
          rpm: 3500,
        );

        expect(success, isTrue);
        expect(setup.server.clearReceived, isTrue);
        expect(setup.server.receivedCommands, contains('04'));
        expect(setup.server.storedDtcs, isEmpty);
        expect(dtcService.lastScannedCodes, isEmpty);

        await _disposeLiveRealProvider(setup);
      });
    });

    group('6. Disconnected ECU Handling', () {
      test('strictly throws StateError when ECU is not connected', () async {
        final obd = ObdProvider();
        expect(obd.isEcuConnected, isFalse);

        await expectLater(
          () => dtcService.clearAllCodes(obd),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Vehicle ECU is not connected.',
            ),
          ),
        );

        // Even with allowWhileMoving: true
        await expectLater(
          () => dtcService.clearAllCodes(obd, allowWhileMoving: true),
          throwsA(isA<StateError>()),
        );

        // Even with speed/rpm override
        await expectLater(
          () => dtcService.clearAllCodes(obd, speed: 0, rpm: 0),
          throwsA(isA<StateError>()),
        );

        obd.dispose();
      });
    });

    group('7. Demo Mode Clearing Lifecycle', () {
      test('simulated clearing works seamlessly regardless of simulated motion', () async {
        final obd = ObdProvider();
        await obd.startDemoMode();

        final initialCodes = await dtcService.scanAllCodes(obd);
        expect(initialCodes.length, 3);
        expect(dtcService.lastScannedCodes.length, 3);

        // Clear codes in demo mode
        final success = await dtcService.clearAllCodes(obd);
        expect(success, isTrue);
        expect(dtcService.lastScannedCodes, isEmpty);

        // Rescan verifies codes are empty
        final rescanned = await dtcService.scanAllCodes(obd);
        expect(rescanned, isEmpty);

        // Reset demo codes restores initial set
        dtcService.resetDemoCodes();
        final resetCodes = await dtcService.scanAllCodes(obd);
        expect(resetCodes.length, 3);

        await obd.stopDemoMode();
        obd.dispose();
      });
    });

    group('8. Live Socket Telemetry E2E Pipeline (No explicit speed/rpm overrides)', () {
      test('reads motion directly from live socket stream: blocks when moving, succeeds when stopped', () async {
        final server = MockElmTcpServer();
        server.speed = 65;
        server.rpm = 2100;
        server.storedDtcs = ['P0300'];
        server.pendingDtcs = [];
        await server.start();

        final connection = TcpObdConnection(host: '127.0.0.1', port: server.port);
        await connection.connect();

        final obdProvider = ObdProvider();
        obdProvider.attachConnection(connection);
        unawaited(obdProvider.startRealMode());

        await _waitUntilConnected(obdProvider);

        // Set screen watchlist to include speed and RPM so polling delivers live telemetry
        obdProvider.setWatchlist(
          WatchSource.visibleScreen,
          {PidKey.vehicleSpeed, PidKey.engineRpm},
        );

        // Wait for live polling to populate provider.data with server telemetry
        final pollDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(pollDeadline)) {
          if (obdProvider.data.speed == 65 && obdProvider.data.rpm == 2100) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        expect(obdProvider.data.speed, 65);
        expect(obdProvider.data.rpm, 2100);

        // Crucial test: call clearAllCodes WITHOUT passing speed or rpm!
        try {
          await dtcService.clearAllCodes(obdProvider);
          fail('Should have thrown DtcSafetyException based on live telemetry');
        } on DtcSafetyException catch (e) {
          expect(e.speed, 65);
          expect(e.rpm, 2100);
          expect(e.message, contains('Vehicle motion safety check'));
        }

        expect(server.clearReceived, isFalse);
        expect(server.receivedCommands, isNot(contains('04')));

        // Now vehicle comes to a complete halt
        server.speed = 0;
        server.rpm = 0;

        final haltDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(haltDeadline)) {
          if (obdProvider.data.speed == 0 && obdProvider.data.rpm == 0) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        expect(obdProvider.data.speed, 0);
        expect(obdProvider.data.rpm, 0);

        // Now clearAllCodes WITHOUT passing speed or rpm must succeed
        final success = await dtcService.clearAllCodes(obdProvider);
        expect(success, isTrue);
        expect(server.clearReceived, isTrue);
        expect(server.receivedCommands, contains('04'));

        await obdProvider.stopRealMode();
        obdProvider.dispose();
        await connection.disconnect();
        await server.stop();
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

  await _waitUntilConnected(provider);

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

Future<void> _waitUntilConnected(ObdProvider provider) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (provider.isEcuConnected) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Timed out waiting for ObdProvider ECU connection');
}

/// Specialized mock server returning custom responses to Mode 04
class _CustomMode04Server {
  final String mode04Response;
  ServerSocket? _server;
  Socket? _clientSocket;
  final List<String> receivedCommands = [];
  String _rxBuffer = '';

  _CustomMode04Server({required this.mode04Response});

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((socket) {
      _clientSocket = socket;
      socket.listen(
        (Uint8List data) {
          final text = String.fromCharCodes(data);
          _rxBuffer += text;

          while (_rxBuffer.contains('\r') || _rxBuffer.contains('\n')) {
            final newlineIdx = _rxBuffer.indexOf(RegExp(r'[\r\n]'));
            final cmd = _rxBuffer.substring(0, newlineIdx).trim().toUpperCase();
            _rxBuffer = _rxBuffer.substring(newlineIdx + 1);

            if (cmd.isEmpty) continue;
            receivedCommands.add(cmd);
            _handle(cmd, socket);
          }
        },
        onError: (_) {},
        onDone: () => _clientSocket = null,
      );
    });
  }

  void _handle(String cmd, Socket socket) {
    void reply(String res) {
      try {
        socket.add(Uint8List.fromList(res.codeUnits));
      } catch (_) {}
    }

    if (cmd == 'ATZ' || cmd == 'ATWS') {
      reply('ELM327 v2.3\r\n>');
    } else if (cmd == 'ATE0' || cmd == 'ATE1' || cmd == 'ATL0' || cmd == 'ATL1') {
      reply('OK\r\n>');
    } else if (cmd == 'ATS0' || cmd == 'ATS1' || cmd == 'ATH0' || cmd == 'ATH1') {
      reply('OK\r\n>');
    } else if (cmd.startsWith('ATSP') || cmd.startsWith('ATAT')) {
      reply('OK\r\n>');
    } else if (cmd == 'ATDP') {
      reply('ISO 14230-4 (KWP FAST)\r\n>');
    } else if (cmd == 'ATDPN') {
      reply('A5\r\n>');
    } else if (cmd == 'ATRV') {
      reply('14.1V\r\n>');
    } else if (cmd.startsWith('AT')) {
      reply('OK\r\n>');
    } else if (cmd == '0100') {
      reply('SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>');
    } else if (cmd == '0120') {
      reply('41 20 80 02 02 01\r\n>');
    } else if (cmd == '0140') {
      reply('41 40 44 04 00 00\r\n>');
    } else if (cmd == '0104') {
      reply('41 04 00\r\n>');
    } else if (cmd == '0105') {
      reply('41 05 50\r\n>');
    } else if (cmd == '010C') {
      reply('41 0C 00 00\r\n>');
    } else if (cmd == '010D') {
      reply('41 0D 00\r\n>');
    } else if (cmd == '010F') {
      reply('41 0F 40\r\n>');
    } else if (cmd == '0110') {
      reply('41 10 00 00\r\n>');
    } else if (cmd == '0111') {
      reply('41 11 00\r\n>');
    } else if (cmd == '03') {
      reply('43 01 71\r\n>');
    } else if (cmd == '07') {
      reply('47 00\r\n>');
    } else if (cmd == '04') {
      reply(mode04Response);
    } else {
      reply('NO DATA\r\n>');
    }
  }

  Future<void> stop() async {
    try {
      await _clientSocket?.close();
    } catch (_) {}
    try {
      await _server?.close();
    } catch (_) {}
    _clientSocket = null;
    _server = null;
  }
}
