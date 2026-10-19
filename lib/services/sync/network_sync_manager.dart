import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:redrive/services/logging/log_service.dart';
import 'package:redrive/services/sync/bluetooth_sync_service.dart';

/// Concrete [SyncTransport] implementation wrapping a standard bidirectional TCP [Socket].
///
/// Designed to operate over the local Wi-Fi link established by Android Auto / CarLink
/// (or shared local vehicle hotspot) without competing with the ELM327 adapter for
/// the single Bluetooth SPP channel on Chinese Android headunits (Topway TS18).
class SocketSyncTransport implements SyncTransport {
  final Socket _socket;
  final StreamController<List<int>> _inbound = StreamController<List<int>>.broadcast();
  bool _closed = false;

  SocketSyncTransport(this._socket) {
    _socket.listen(
      (Uint8List data) {
        if (!_closed) {
          _inbound.add(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        LogService.w('SocketSyncTransport error: $error', tag: 'Sync');
        if (!_closed) {
          _inbound.addError(error, stackTrace);
        }
      },
      onDone: () {
        close();
      },
      cancelOnError: false,
    );
  }

  @override
  Stream<List<int>> get inboundBytes => _inbound.stream;

  @override
  void sendBytes(List<int> bytes) {
    if (!_closed) {
      try {
        _socket.add(bytes);
      } catch (e) {
        LogService.w('SocketSyncTransport send error: $e', tag: 'Sync');
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _inbound.close();
    } catch (_) {}
    try {
      await _socket.flush();
      await _socket.close();
      _socket.destroy();
    } catch (_) {}
  }
}

/// Orchestrates local TCP network synchronization between the Headunit server
/// and Phone Companion client.
class NetworkSyncManager extends ChangeNotifier {
  static const int defaultPort = 7355;
  static const String defaultAndroidAutoGateway = '192.168.43.1';

  final BluetoothSyncService syncService;
  final bool isHeadunit;

  ServerSocket? _serverSocket;
  Socket? _activeClientSocket;
  SocketSyncTransport? _activeTransport;

  bool _isServerRunning = false;
  bool get isServerRunning => _isServerRunning;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  int _serverPort = defaultPort;
  int get serverPort => _serverPort;

  String? _lastError;
  String? get lastError => _lastError;

  String? _connectedPeerAddress;
  String? get connectedPeerAddress => _connectedPeerAddress;

  NetworkSyncManager({
    required this.syncService,
    required this.isHeadunit,
  });

  bool _isDisposed = false;

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Starts the TCP Sync Server on the Headunit.
  Future<bool> startServer({int port = defaultPort}) async {
    await stopServer();
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverPort = port;
      _isServerRunning = true;
      _lastError = null;
      _safeNotifyListeners();

      LogService.i('NetworkSyncManager server listening on port $port', tag: 'Sync');

      _serverSocket!.listen(
        _handleIncomingConnection,
        onError: (Object error) {
          _lastError = 'Server error: $error';
          _isServerRunning = false;
          _safeNotifyListeners();
          LogService.e('NetworkSyncManager server listen error', tag: 'Sync', error: error);
        },
        onDone: () {
          _isServerRunning = false;
          _safeNotifyListeners();
        },
      );
      return true;
    } catch (e) {
      _lastError = 'Failed to bind server on port $port: $e';
      _isServerRunning = false;
      _safeNotifyListeners();
      LogService.w(_lastError!, tag: 'Sync');
      return false;
    }
  }

  void _handleIncomingConnection(Socket socket) async {
    LogService.i('Incoming sync connection from ${socket.remoteAddress.address}:${socket.port}', tag: 'Sync');
    _connectedPeerAddress = socket.remoteAddress.address;

    await _activeTransport?.close();
    _activeClientSocket?.destroy();

    _activeClientSocket = socket;
    final transport = SocketSyncTransport(socket);
    _activeTransport = transport;

    // Attach transport to the sync service (Headunit server waits for peer hello)
    await syncService.attachTransport(transport, initiateHandshake: false);
    _safeNotifyListeners();
  }

  /// Stops the TCP Sync Server.
  Future<void> stopServer() async {
    _isServerRunning = false;
    try {
      await _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    await _activeTransport?.close();
    _activeTransport = null;
    _activeClientSocket?.destroy();
    _activeClientSocket = null;
    _connectedPeerAddress = null;

    _safeNotifyListeners();
  }

  /// Connects to the Headunit TCP Sync Server from the Phone Companion.
  Future<bool> connectToHeadunit({
    String host = defaultAndroidAutoGateway,
    int port = defaultPort,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isConnecting) return false;

    _isConnecting = true;
    _lastError = null;
    _safeNotifyListeners();

    try {
      LogService.i('Connecting to Headunit Sync Server at $host:$port...', tag: 'Sync');
      final socket = await Socket.connect(host, port, timeout: timeout);
      _connectedPeerAddress = host;

      await _activeTransport?.close();
      _activeClientSocket?.destroy();

      _activeClientSocket = socket;
      final transport = SocketSyncTransport(socket);
      _activeTransport = transport;

      // Attach transport and initiate handshake from Phone Companion
      await syncService.attachTransport(transport, initiateHandshake: true);

      _isConnecting = false;
      _safeNotifyListeners();
      return true;
    } catch (e) {
      _isConnecting = false;
      _lastError = 'Connection to $host:$port failed: $e';
      _safeNotifyListeners();
      LogService.w(_lastError!, tag: 'Sync');
      return false;
    }
  }

  /// Retrieves list of local IPv4 network addresses (e.g. Wi-Fi hotspot address).
  Future<List<String>> getLocalIpAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ips.add('${addr.address} (${iface.name})');
        }
      }
      return ips;
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isServerRunning = false;
    try {
      _serverSocket?.close();
    } catch (_) {}
    _serverSocket = null;

    try {
      _activeTransport?.close();
    } catch (_) {}
    _activeTransport = null;

    try {
      _activeClientSocket?.destroy();
    } catch (_) {}
    _activeClientSocket = null;
    _connectedPeerAddress = null;

    super.dispose();
  }
}
