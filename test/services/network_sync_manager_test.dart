import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';
import 'package:redrive/services/sync/network_sync_manager.dart';

void main() {
  group('SocketSyncTransport', () {
    test('transfers raw bytes bidirectionally between loopback sockets', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverSocketCompleter = Completer<Socket>();
      server.listen((socket) {
        if (!serverSocketCompleter.isCompleted) {
          serverSocketCompleter.complete(socket);
        }
      });

      final clientSocket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final acceptedSocket = await serverSocketCompleter.future;

      final serverTransport = SocketSyncTransport(acceptedSocket);
      final clientTransport = SocketSyncTransport(clientSocket);

      final clientReceived = <List<int>>[];
      final serverReceived = <List<int>>[];

      final clientSub = clientTransport.inboundBytes.listen(clientReceived.add);
      final serverSub = serverTransport.inboundBytes.listen(serverReceived.add);

      serverTransport.sendBytes([1, 2, 3, 4, 5]);
      clientTransport.sendBytes([10, 20, 30]);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(clientReceived.expand((x) => x).toList(), [1, 2, 3, 4, 5]);
      expect(serverReceived.expand((x) => x).toList(), [10, 20, 30]);

      await clientSub.cancel();
      await serverSub.cancel();
      await clientTransport.close();
      await serverTransport.close();
      await server.close();
    });
  });

  group('NetworkSyncManager', () {
    test('server binds and phone client connects and completes frame handshake', () async {
      final headunitService = BluetoothSyncService(
        deviceId: 'headunit_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final phoneService = BluetoothSyncService(
        deviceId: 'phone_test',
        deviceRole: 'phone',
        inMemory: true,
      );

      final headunitManager = NetworkSyncManager(
        syncService: headunitService,
        isHeadunit: true,
      );
      final phoneManager = NetworkSyncManager(
        syncService: phoneService,
        isHeadunit: false,
      );

      // 1. Start server on a dynamic port
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dynamicPort = server.port;
      await server.close();

      final started = await headunitManager.startServer(port: dynamicPort);
      expect(started, isTrue);
      expect(headunitManager.isServerRunning, isTrue);

      // 2. Connect phone client
      final connected = await phoneManager.connectToHeadunit(
        host: '127.0.0.1',
        port: dynamicPort,
      );
      expect(connected, isTrue);

      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Verify sync states are connected/synced
      expect(phoneService.state, anyOf(
        SyncConnectionState.connected,
        SyncConnectionState.syncing,
        SyncConnectionState.synced,
      ));

      // 4. Verify local IP discovery
      final ips = await headunitManager.getLocalIpAddresses();
      expect(ips, isA<List<String>>());

      // 5. Clean teardown
      await phoneManager.stopServer();
      await headunitManager.stopServer();
      expect(headunitManager.isServerRunning, isFalse);
    });
  });
}
