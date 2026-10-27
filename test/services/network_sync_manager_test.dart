import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    test('server restarts cleanly multiple times on same port without SocketException (shared bind)', () async {
      final headunitService = BluetoothSyncService(
        deviceId: 'headunit_restart_test',
        deviceRole: 'headunit',
        inMemory: true,
      );
      final headunitManager = NetworkSyncManager(
        syncService: headunitService,
        isHeadunit: true,
      );

      final tempServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dynamicPort = tempServer.port;
      await tempServer.close();

      // Start 1
      final ok1 = await headunitManager.startServer(port: dynamicPort);
      expect(ok1, isTrue);
      expect(headunitManager.isServerRunning, isTrue);
      expect(headunitManager.lastError, isNull);

      // Rapid Restart 2 (simulating user tapping "RESTART" on headunit)
      final ok2 = await headunitManager.startServer(port: dynamicPort);
      expect(ok2, isTrue);
      expect(headunitManager.isServerRunning, isTrue);
      expect(headunitManager.lastError, isNull);

      // Rapid Restart 3
      final ok3 = await headunitManager.startServer(port: dynamicPort);
      expect(ok3, isTrue);
      expect(headunitManager.isServerRunning, isTrue);
      expect(headunitManager.lastError, isNull);

      await headunitManager.stopServer();
      expect(headunitManager.isServerRunning, isFalse);
    });

    test('custom target host persists and restores across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final service = BluetoothSyncService(
        deviceId: 'phone_pref_test',
        deviceRole: 'phone',
        inMemory: true,
      );
      final manager1 = NetworkSyncManager(
        syncService: service,
        isHeadunit: false,
      );

      await manager1.setCustomTargetHost('192.168.1.188');
      expect(manager1.discoveredTargetHost, '192.168.1.188');
      expect(manager1.activeTargetHost, '192.168.1.188');

      final manager2 = NetworkSyncManager(
        syncService: service,
        isHeadunit: false,
      );
      await manager2.loadSavedTargetHost();
      expect(manager2.discoveredTargetHost, '192.168.1.188');
      expect(manager2.activeTargetHost, '192.168.1.188');
    });

    test('evaluateInCarCandidates resolves Android Auto Wi-Fi Direct p2p subnet and gateway', () {
      final interfaces = [
        const NetworkInterfaceInfo(
          name: 'rmnet_data0',
          addresses: ['10.155.42.11'],
        ),
        const NetworkInterfaceInfo(
          name: 'p2p-wlan0-0',
          addresses: ['192.168.49.125'],
        ),
      ];

      final candidate = NetworkSyncManager.evaluateInCarCandidates(interfaces);
      expect(candidate, isNotNull);
      expect(candidate!.interfaceName, 'p2p-wlan0-0');
      expect(candidate.localAddress, '192.168.49.125');
      expect(candidate.gatewayAddress, '192.168.49.1');
      expect(candidate.isAndroidAutoSubnet, isTrue);
    });

    test('evaluateInCarCandidates resolves Carlinkit / dongle subnet (192.168.50.x)', () {
      final interfaces = [
        const NetworkInterfaceInfo(
          name: 'wlan0',
          addresses: ['192.168.50.15'],
        ),
      ];

      final candidate = NetworkSyncManager.evaluateInCarCandidates(interfaces);
      expect(candidate, isNotNull);
      expect(candidate!.interfaceName, 'wlan0');
      expect(candidate.localAddress, '192.168.50.15');
      expect(candidate.gatewayAddress, '192.168.50.1');
      expect(candidate.isAndroidAutoSubnet, isTrue);
    });

    test('evaluateInCarCandidates resolves Hotspot AP mode where phone is at .1', () {
      final interfaces = [
        const NetworkInterfaceInfo(
          name: 'wlan0',
          addresses: ['192.168.43.1'],
        ),
      ];

      final candidate = NetworkSyncManager.evaluateInCarCandidates(interfaces);
      expect(candidate, isNotNull);
      expect(candidate!.gatewayAddress, '192.168.43.2');
      expect(candidate.isAndroidAutoSubnet, isTrue);
    });

    test('evaluateInCarCandidates ignores cellular and loopback interfaces', () {
      final interfaces = [
        const NetworkInterfaceInfo(
          name: 'rmnet_data0',
          addresses: ['10.0.0.5'],
        ),
        const NetworkInterfaceInfo(
          name: 'tun0',
          addresses: ['172.16.0.1'],
        ),
      ];

      final candidate = NetworkSyncManager.evaluateInCarCandidates(interfaces);
      expect(candidate, isNull);
    });

    test('sharesSubnet correctly identifies matching and non-matching /24 subnets', () {
      expect(NetworkSyncManager.sharesSubnet('192.168.43.26', '192.168.43.1'), isTrue);
      expect(NetworkSyncManager.sharesSubnet('192.168.49.12', '192.168.49.1'), isTrue);
      expect(NetworkSyncManager.sharesSubnet('192.168.43.26', '192.168.49.1'), isFalse);
      expect(NetworkSyncManager.sharesSubnet('10.0.0.5', '192.168.43.1'), isFalse);
      expect(NetworkSyncManager.sharesSubnet('invalid', '192.168.43.1'), isFalse);
    });
  });
}
