import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/obd/connection/tcp_obd_connection.dart';
import 'package:redrive/obd/pid/pid_key.dart';
import 'package:redrive/obd/polling/polling_controller.dart';
import 'package:redrive/obd/source/obd_source_state.dart';
import 'package:redrive/providers/obd_provider.dart';

void main() {
  test('full Suzuki Swift M15A K-Line handshake and polling over TCP connection', () async {
    // 1. Bind a mock TCP server simulating Vgate iCar Pro on Suzuki Swift
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    Socket? serverSideSocket;
    final serverReceived = <String>[];
    String rxBuffer = '';

    server.listen((socket) {
      serverSideSocket = socket;
      socket.listen((Uint8List data) {
        final text = String.fromCharCodes(data);
        rxBuffer += text;

        while (rxBuffer.contains('\r')) {
          final parts = rxBuffer.split('\r');
          final cmd = parts[0].trim().toUpperCase();
          rxBuffer = parts.sublist(1).join('\r');

          if (cmd.isEmpty) continue;
          serverReceived.add(cmd);

          void reply(String response) {
            try {
              socket.add(response.codeUnits);
            } catch (_) {}
          }

          if (cmd == 'ATZ') {
            reply('ELM327 v2.3\r\n>');
          } else if (cmd == 'ATE0' || cmd == 'ATL0' || cmd == 'ATSP0' || cmd == 'ATSP5') {
            reply('OK\r\n>');
          } else if (cmd == '0100') {
            // Emulate Suzuki Swift K-Line protocol search and bus init banner
            reply('SEARCHING...\r\nBUS INIT: OK\r\n41 00 BE 3F B8 13\r\n>');
          } else if (cmd == '0120') {
            reply('41 20 80 00 00 01\r\n>');
          } else if (cmd == '010C') {
            // RPM = 2000 -> 2000 * 4 = 8000 = 0x1F40
            reply('41 0C 1F 40\r\n>');
          } else if (cmd == '010D') {
            // Speed = 45 km/h = 0x2D
            reply('41 0D 2D\r\n>');
          } else if (cmd == '0105') {
            // Coolant = 86°C -> 86 + 40 = 126 = 0x7E
            reply('41 05 7E\r\n>');
          } else {
            reply('NO DATA\r\n>');
          }
        }
      });
    });

    addTearDown(() async {
      await serverSideSocket?.close();
      await server.close();
    });

    // 2. Connect ObdProvider via TcpObdConnection
    final tcpConnection = TcpObdConnection(host: '127.0.0.1', port: port);
    final connected = await tcpConnection.connect();
    expect(connected, isTrue);

    final obdProvider = ObdProvider();
    obdProvider.attachConnection(tcpConnection);

    // Watch RPM and Speed
    obdProvider.setWatchlist(WatchSource.visibleScreen, {
      PidKey.engineRpm,
      PidKey.vehicleSpeed,
    });
    obdProvider.startRealMode();

    // 3. Wait for the handshake to complete and enter polling
    final completer = Completer<void>();
    obdProvider.addListener(() {
      if (obdProvider.state == ObdSourceState.polling && !completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future.timeout(const Duration(seconds: 5));

    expect(obdProvider.state, ObdSourceState.polling);
    expect(obdProvider.isEcuConnected, isTrue);
    expect(serverReceived, containsAll(['ATZ', 'ATE0', 'ATL0', 'ATSP0', '0100']));

    // Cleanup
    await obdProvider.stopRealMode();
    await tcpConnection.disconnect();
  });
}
